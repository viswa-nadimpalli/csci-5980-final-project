"""
ws_locustfile.py — Mutation-focused Locust file for the WebSocket benchmark.

All users target a single pack (set via PACK_ID env var) and alternate
between adding and deleting stickers, generating a steady stream of
pack_updated WebSocket events for ws_benchmark.py to measure.

Usage:
    PACK_ID=<uuid> USER_ID=<uuid> locust -f ws_locustfile.py \
        --users 20 --spawn-rate 2 --run-time 120s --headless
"""

import csv
import os
import random
import uuid

from locust import HttpUser, between, task

PACK_ID = os.environ.get("PACK_ID", "")

USERS = []

def _load_users():
    global USERS
    try:
        with open("test_users.csv", newline="") as f:
            USERS = [row["user_id"] for row in csv.DictReader(f)]
    except FileNotFoundError:
        fallback = os.environ.get("USER_ID", "")
        if fallback:
            USERS = [fallback]

_load_users()


class WSMutationUser(HttpUser):
    host = "https://api.18-191-85-231.nip.io"
    wait_time = between(0.5, 2)

    def on_start(self):
        if not PACK_ID:
            raise ValueError("Set PACK_ID env var to the pack you want to monitor")
        if not USERS:
            raise ValueError("No users found — provide test_users.csv or set USER_ID env var")
        self.pack_id = PACK_ID
        self.user_id = random.choice(USERS)
        self.sticker_ids: list[str] = []

    @task(3)
    def add_sticker(self):
        resp = self.client.post(
            f"/packs/{self.pack_id}/stickers",
            json={
                "user_id": self.user_id,
                "s3_key": f"stickers/{self.pack_id}/{uuid.uuid4()}.png",
            },
            name="POST /packs/{pack_id}/stickers",
        )
        if resp.status_code == 201:
            self.sticker_ids.append(resp.json()["id"])

    @task(1)
    def delete_sticker(self):
        if not self.sticker_ids:
            return
        sticker_id = self.sticker_ids.pop(random.randrange(len(self.sticker_ids)))
        self.client.delete(
            f"/stickers/{sticker_id}",
            params={"user_id": self.user_id},
            name="DELETE /stickers/{sticker_id}",
        )
