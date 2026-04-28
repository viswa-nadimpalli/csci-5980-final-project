#!/usr/bin/env python3
"""
ws_benchmark.py — WebSocket delivery-latency + end-to-end benchmark.

Subscribes to one or more pack WebSocket endpoints and measures:
  1. ws_latency     — server broadcast timestamp → client receipt
  2. fetch_latency  — GET /packs/{pack_id}/full response time after event
  3. total_latency  — server broadcast timestamp → full response received

Intended to run alongside Locust (which triggers REST mutations). Locust
drives the load; this script passively listens and reports latency stats.

Requirements:
    pip install websockets aiohttp

Usage:
    python ws_benchmark.py --packs <pack_id> --user <user_id>
    python ws_benchmark.py --packs <pack_id1> <pack_id2> --user <user_id> \\
        --host wss://your-host --duration 120 --csv results.csv
"""

import argparse
import asyncio
import csv
import json
import statistics
import sys
import time
from datetime import datetime, timezone

try:
    import websockets
except ImportError:
    print("websockets is required: pip install websockets", file=sys.stderr)
    sys.exit(1)

try:
    import aiohttp
except ImportError:
    print("aiohttp is required: pip install aiohttp", file=sys.stderr)
    sys.exit(1)


def _http_base(ws_host: str) -> str:
    return ws_host.replace("wss://", "https://").replace("ws://", "http://")


async def fetch_pack_full(
    http_base: str,
    pack_id: str,
    user_id: str,
    session: aiohttp.ClientSession,
) -> float:
    url = f"{http_base}/packs/{pack_id}/full"
    t0 = time.time()
    async with session.get(url, params={"requester_id": user_id}) as resp:
        await resp.read()
    return (time.time() - t0) * 1000


async def listen_pack(
    pack_id: str,
    ws_host: str,
    user_id: str,
    latencies: dict[str, list[float]],
    csv_writer,
    session: aiohttp.ClientSession,
) -> None:
    url = f"{ws_host}/ws/packs/{pack_id}"
    http_base = _http_base(ws_host)
    print(f"[{pack_id[:8]}] connecting to {url}")

    while True:
        try:
            async with websockets.connect(url) as ws:
                print(f"[{pack_id[:8]}] connected")
                async for raw in ws:
                    received_at = time.time()
                    try:
                        data = json.loads(raw)
                        ts_str = data.get("timestamp")
                        if not ts_str:
                            continue

                        server_ts = datetime.fromisoformat(ts_str).timestamp()
                        ws_latency = (received_at - server_ts) * 1000

                        fetch_latency = await fetch_pack_full(http_base, pack_id, user_id, session)
                        total_latency = ws_latency + fetch_latency

                        latencies["ws"].append(ws_latency)
                        latencies["fetch"].append(fetch_latency)
                        latencies["total"].append(total_latency)

                        print(
                            f"[{pack_id[:8]}] "
                            f"event={data.get('event_type', '?'):15s} "
                            f"version={data.get('pack_version', '?'):>4}  "
                            f"ws={ws_latency:7.1f}ms  "
                            f"fetch={fetch_latency:7.1f}ms  "
                            f"total={total_latency:7.1f}ms"
                        )

                        if csv_writer:
                            csv_writer.writerow({
                                "pack_id": pack_id,
                                "event_type": data.get("event_type", ""),
                                "pack_version": data.get("pack_version", ""),
                                "server_timestamp": ts_str,
                                "received_timestamp": datetime.fromtimestamp(
                                    received_at, tz=timezone.utc
                                ).isoformat(),
                                "ws_latency_ms": f"{ws_latency:.3f}",
                                "fetch_latency_ms": f"{fetch_latency:.3f}",
                                "total_latency_ms": f"{total_latency:.3f}",
                            })

                    except Exception as e:
                        print(f"[{pack_id[:8]}] error: {e}")

        except (websockets.exceptions.ConnectionClosed, OSError) as e:
            print(f"[{pack_id[:8]}] connection lost ({e}), retrying in 2s...")
            await asyncio.sleep(2)


def _print_metric(label: str, values: list[float]) -> None:
    if not values:
        print(f"  {label}: no data")
        return
    s = sorted(values)
    n = len(s)

    def pct(p: float) -> float:
        return s[max(0, int(n * p / 100) - 1)]

    print(f"  {label} (n={n})")
    print(f"    min={min(s):.1f}ms  mean={statistics.mean(s):.1f}ms  "
          f"p50={pct(50):.1f}ms  p95={pct(95):.1f}ms  p99={pct(99):.1f}ms  max={max(s):.1f}ms")
    if n >= 2:
        print(f"    stdev={statistics.stdev(s):.1f}ms")


def print_summary(latencies: dict[str, list[float]]) -> None:
    print("\n" + "=" * 60)
    print("Latency summary")
    print("=" * 60)
    if not any(latencies.values()):
        print("  No events received.")
        return
    _print_metric("ws_latency    (broadcast → receipt)", latencies["ws"])
    _print_metric("fetch_latency (GET /full round trip)", latencies["fetch"])
    _print_metric("total_latency (broadcast → served)  ", latencies["total"])


async def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--packs", nargs="+", required=True, metavar="PACK_ID",
                        help="Pack IDs to subscribe to")
    parser.add_argument("--user", required=True, metavar="USER_ID",
                        help="requester_id used for GET /packs/{pack_id}/full")
    parser.add_argument("--host", default="wss://api.18-191-85-231.nip.io",
                        help="WebSocket base URL (wss:// or ws://)")
    parser.add_argument("--duration", type=int, default=60, metavar="SECONDS",
                        help="How long to run (default 60s)")
    parser.add_argument("--csv", metavar="PATH", help="Write per-event data to a CSV file")
    args = parser.parse_args()

    latencies: dict[str, list[float]] = {"ws": [], "fetch": [], "total": []}
    csv_file = None
    csv_writer = None

    if args.csv:
        csv_file = open(args.csv, "w", newline="")
        fields = [
            "pack_id", "event_type", "pack_version",
            "server_timestamp", "received_timestamp",
            "ws_latency_ms", "fetch_latency_ms", "total_latency_ms",
        ]
        csv_writer = csv.DictWriter(csv_file, fieldnames=fields)
        csv_writer.writeheader()
        print(f"Writing per-event data to {args.csv}")

    print(f"Listening on {len(args.packs)} pack(s) for {args.duration}s  (Ctrl-C to stop early)\n")

    async with aiohttp.ClientSession() as session:
        tasks = [
            listen_pack(pid, args.host, args.user, latencies, csv_writer, session)
            for pid in args.packs
        ]
        try:
            await asyncio.wait_for(asyncio.gather(*tasks), timeout=args.duration)
        except asyncio.TimeoutError:
            pass
        except KeyboardInterrupt:
            pass
        finally:
            if csv_file:
                csv_file.close()

    print_summary(latencies)


if __name__ == "__main__":
    asyncio.run(main())
