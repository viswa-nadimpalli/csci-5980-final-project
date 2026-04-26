#!/usr/bin/env python3
"""
ws_benchmark.py — WebSocket delivery-latency benchmark.

Subscribes to one or more pack WebSocket endpoints and measures the
server-to-client delivery latency for every incoming event.

Intended to run alongside Locust (which triggers REST mutations). Locust
drives the load; this script passively listens and reports latency stats.

Requirements:
    pip install websockets

Usage:
    python ws_benchmark.py --packs <pack_id1> <pack_id2> ...
    python ws_benchmark.py --packs <pack_id1> --host wss://your-host --duration 120

Output:
    Per-event lines printed to stdout while running.
    Summary statistics (min/mean/p50/p95/p99/max) printed on exit.
    Optional CSV export via --csv <path>.
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


async def listen_pack(pack_id: str, host: str, latencies: list[float], csv_writer) -> None:
    url = f"{host}/ws/packs/{pack_id}"
    print(f"[{pack_id[:8]}] connecting to {url}")

    # Retry loop so a dropped connection doesn't silently end measurement.
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
                        latency_ms = (received_at - server_ts) * 1000
                        latencies.append(latency_ms)

                        line = (
                            f"[{pack_id[:8]}] "
                            f"event={data.get('event_type', '?'):15s} "
                            f"version={data.get('pack_version', '?'):>4}  "
                            f"latency={latency_ms:7.1f}ms"
                        )
                        print(line)

                        if csv_writer:
                            csv_writer.writerow({
                                "pack_id": pack_id,
                                "event_type": data.get("event_type", ""),
                                "pack_version": data.get("pack_version", ""),
                                "server_timestamp": ts_str,
                                "received_timestamp": datetime.fromtimestamp(
                                    received_at, tz=timezone.utc
                                ).isoformat(),
                                "latency_ms": f"{latency_ms:.3f}",
                            })

                    except Exception as e:
                        print(f"[{pack_id[:8]}] parse error: {e}")

        except (websockets.exceptions.ConnectionClosed, OSError) as e:
            print(f"[{pack_id[:8]}] connection lost ({e}), retrying in 2s...")
            await asyncio.sleep(2)


def print_summary(latencies: list[float]) -> None:
    print("\n" + "=" * 50)
    print("Latency summary (server timestamp → client receipt)")
    print("=" * 50)
    if not latencies:
        print("  No events received.")
        return

    s = sorted(latencies)
    n = len(s)

    def percentile(p: float) -> float:
        idx = max(0, int(n * p / 100) - 1)
        return s[idx]

    print(f"  n       = {n}")
    print(f"  min     = {min(s):.1f} ms")
    print(f"  mean    = {statistics.mean(s):.1f} ms")
    print(f"  p50     = {percentile(50):.1f} ms")
    print(f"  p95     = {percentile(95):.1f} ms")
    print(f"  p99     = {percentile(99):.1f} ms")
    print(f"  max     = {max(s):.1f} ms")
    if n >= 2:
        print(f"  stdev   = {statistics.stdev(s):.1f} ms")


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--packs", nargs="+", required=True, metavar="PACK_ID", help="Pack IDs to subscribe to")
    parser.add_argument("--host", default="wss://api.18-191-85-231.nip.io", help="WebSocket base URL")
    parser.add_argument("--duration", type=int, default=60, metavar="SECONDS", help="How long to run (default 60s)")
    parser.add_argument("--csv", metavar="PATH", help="Write per-event data to a CSV file")
    args = parser.parse_args()

    latencies: list[float] = []
    csv_file = None
    csv_writer = None

    if args.csv:
        csv_file = open(args.csv, "w", newline="")
        fields = ["pack_id", "event_type", "pack_version", "server_timestamp", "received_timestamp", "latency_ms"]
        csv_writer = csv.DictWriter(csv_file, fieldnames=fields)
        csv_writer.writeheader()
        print(f"Writing per-event data to {args.csv}")

    print(f"Listening on {len(args.packs)} pack(s) for {args.duration}s  (Ctrl-C to stop early)\n")

    tasks = [listen_pack(pid, args.host, latencies, csv_writer) for pid in args.packs]
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
