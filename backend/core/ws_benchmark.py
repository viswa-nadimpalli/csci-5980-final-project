#!/usr/bin/env python3
"""
ws_benchmark.py — WebSocket delivery-latency + end-to-end benchmark.

Subscribes to one or more pack WebSocket endpoints and measures:
  1. ws_latency          — server broadcast timestamp → client receipt
  2. fetch_queue_latency — client receipt → refetch task starts
  3. fetch_latency       — GET /packs/{pack_id}/full response time
  4. total_latency       — server broadcast timestamp → full response received

Intended to run alongside Locust (which triggers REST mutations). Locust
drives the load; this script passively listens and reports latency stats.

The WebSocket receive loop never waits for /packs/{pack_id}/full. Refetches run
in bounded background tasks so ws_latency measures message delivery instead of
benchmark receive-buffer backlog. If fetch_queue_latency grows, the client-side
refetch workload is saturated for the selected --fetch-concurrency.

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
import itertools
import json
import statistics
import sys
import time
from datetime import datetime, timezone
from typing import Any

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
    t0 = time.perf_counter()
    async with session.get(url, params={"requester_id": user_id}) as resp:
        await resp.read()
        resp.raise_for_status()
    return (time.perf_counter() - t0) * 1000


def _parse_server_timestamp(ts_str: str) -> float:
    return datetime.fromisoformat(ts_str).timestamp()


async def handle_event(
    *,
    event_sequence: int,
    data: dict[str, Any],
    pack_id: str,
    received_at: float,
    http_base: str,
    user_id: str,
    latencies: dict[str, list[float]],
    csv_writer,
    session: aiohttp.ClientSession,
    fetch_semaphore: asyncio.Semaphore,
) -> None:
    try:
        ts_str = data["timestamp"]
        server_ts = _parse_server_timestamp(ts_str)
        ws_latency = (received_at - server_ts) * 1000

        async with fetch_semaphore:
            fetch_started_at = time.time()
            fetch_queue_latency = (fetch_started_at - received_at) * 1000
            fetch_latency = await fetch_pack_full(http_base, pack_id, user_id, session)
            completed_at = time.time()

        total_latency = (completed_at - server_ts) * 1000

        latencies["ws"].append(ws_latency)
        latencies["fetch_queue"].append(fetch_queue_latency)
        latencies["fetch"].append(fetch_latency)
        latencies["total"].append(total_latency)

        print(
            f"[{pack_id[:8]}] "
            f"event={data.get('event_type', '?'):15s} "
            f"version={data.get('pack_version', '?'):>4}  "
            f"ws={ws_latency:7.1f}ms  "
            f"queue={fetch_queue_latency:7.1f}ms  "
            f"fetch={fetch_latency:7.1f}ms  "
            f"total={total_latency:7.1f}ms"
        )

        if csv_writer:
            csv_writer.writerow({
                "event_sequence": event_sequence,
                "pack_id": pack_id,
                "event_type": data.get("event_type", ""),
                "pack_version": data.get("pack_version", ""),
                "server_timestamp": ts_str,
                "received_timestamp": datetime.fromtimestamp(
                    received_at, tz=timezone.utc
                ).isoformat(),
                "fetch_started_timestamp": datetime.fromtimestamp(
                    fetch_started_at, tz=timezone.utc
                ).isoformat(),
                "completed_timestamp": datetime.fromtimestamp(
                    completed_at, tz=timezone.utc
                ).isoformat(),
                "ws_latency_ms": f"{ws_latency:.3f}",
                "fetch_queue_latency_ms": f"{fetch_queue_latency:.3f}",
                "fetch_latency_ms": f"{fetch_latency:.3f}",
                "total_latency_ms": f"{total_latency:.3f}",
            })
    except Exception as e:
        print(f"[{pack_id[:8]}] refetch error: {e}")


async def listen_pack(
    pack_id: str,
    ws_host: str,
    user_id: str,
    latencies: dict[str, list[float]],
    csv_writer,
    session: aiohttp.ClientSession,
    fetch_semaphore: asyncio.Semaphore,
    event_tasks: set[asyncio.Task[None]],
    event_counter: itertools.count,
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

                        _parse_server_timestamp(ts_str)
                        task = asyncio.create_task(
                            handle_event(
                                event_sequence=next(event_counter),
                                data=data,
                                pack_id=pack_id,
                                received_at=received_at,
                                http_base=http_base,
                                user_id=user_id,
                                latencies=latencies,
                                csv_writer=csv_writer,
                                session=session,
                                fetch_semaphore=fetch_semaphore,
                            )
                        )
                        event_tasks.add(task)
                        task.add_done_callback(event_tasks.discard)

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
    _print_metric("fetch_queue   (receipt → refetch start)", latencies["fetch_queue"])
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
    parser.add_argument("--fetch-concurrency", type=int, default=4, metavar="N",
                        help="Max concurrent /packs/{pack_id}/full refetches (default 4)")
    parser.add_argument("--drain-timeout", type=int, default=30, metavar="SECONDS",
                        help="How long to wait for in-flight refetches after listening stops")
    args = parser.parse_args()

    if args.fetch_concurrency < 1:
        parser.error("--fetch-concurrency must be at least 1")
    if args.drain_timeout < 0:
        parser.error("--drain-timeout must be non-negative")

    latencies: dict[str, list[float]] = {"ws": [], "fetch_queue": [], "fetch": [], "total": []}
    csv_file = None
    csv_writer = None

    if args.csv:
        csv_file = open(args.csv, "w", newline="")
        fields = [
            "event_sequence", "pack_id", "event_type", "pack_version",
            "server_timestamp", "received_timestamp",
            "fetch_started_timestamp", "completed_timestamp",
            "ws_latency_ms", "fetch_queue_latency_ms",
            "fetch_latency_ms", "total_latency_ms",
        ]
        csv_writer = csv.DictWriter(csv_file, fieldnames=fields)
        csv_writer.writeheader()
        print(f"Writing per-event data to {args.csv}")

    print(
        f"Listening on {len(args.packs)} pack(s) for {args.duration}s "
        f"with fetch concurrency={args.fetch_concurrency}  (Ctrl-C to stop early)\n"
    )

    async with aiohttp.ClientSession() as session:
        fetch_semaphore = asyncio.Semaphore(args.fetch_concurrency)
        event_tasks: set[asyncio.Task[None]] = set()
        event_counter = itertools.count(1)
        tasks = [
            asyncio.create_task(
                listen_pack(
                    pid,
                    args.host,
                    args.user,
                    latencies,
                    csv_writer,
                    session,
                    fetch_semaphore,
                    event_tasks,
                    event_counter,
                )
            )
            for pid in args.packs
        ]
        try:
            await asyncio.sleep(args.duration)
        except KeyboardInterrupt:
            pass
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

            if event_tasks and args.drain_timeout:
                print(f"\nDraining {len(event_tasks)} in-flight refetch task(s)...")
                _done, pending = await asyncio.wait(event_tasks, timeout=args.drain_timeout)
                if pending:
                    print(f"Canceling {len(pending)} refetch task(s) after drain timeout")
                    for task in pending:
                        task.cancel()
                    await asyncio.gather(*pending, return_exceptions=True)
            elif event_tasks:
                for task in event_tasks:
                    task.cancel()
                await asyncio.gather(*event_tasks, return_exceptions=True)

            if csv_file:
                csv_file.close()

    print_summary(latencies)


if __name__ == "__main__":
    asyncio.run(main())
