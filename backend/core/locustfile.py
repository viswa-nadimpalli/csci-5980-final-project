import csv
import random
import uuid
from locust import HttpUser, task, between

# start master
# locust -f locustfile.py --master --host=api-host:3001

# start workers 
# locust -f locustfile.py --worker --master-host=127.0.0.1

USERS = []
USER_PACKS = {}

def load_data():
    global USERS, USER_PACKS

    with open("test_users.csv", newline="") as f:
        reader = csv.DictReader(f)
        USERS = [row["user_id"] for row in reader]

    with open("test_packs.csv", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            user_id = row["user_id"]
            pack_id = row["pack_id"]
            USER_PACKS.setdefault(user_id, []).append(pack_id)

load_data()


class StickerAppUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        self.user_id = random.choice(USERS)
        self.pack_ids = USER_PACKS.get(self.user_id, [])

    @task(60)
    def list_packs(self):
        self.client.get(
            "/packs",
            params={"requester_id": self.user_id},
            name="/packs"
        )

    @task(25)
    def get_pack(self):
        if not self.pack_ids:
            return
        pack_id = random.choice(self.pack_ids)
        self.client.get(
            f"/packs/{pack_id}",
            params={"requester_id": self.user_id},
            name="/packs/{pack_id}"
        )

    @task(10)
    def list_stickers(self):
        if not self.pack_ids:
            return
        pack_id = random.choice(self.pack_ids)
        self.client.get(
            f"/packs/{pack_id}/stickers",
            params={"user_id": self.user_id},
            name="/packs/{pack_id}/stickers"
        )

    @task(4)
    def create_pack(self):
        payload = {
            "name": f"loadtest-pack-{uuid.uuid4().hex[:8]}",
            "description": "created by locust",
            "owner_id": self.user_id
        }
        self.client.post(
            "/packs",
            json=payload,
            name="POST /packs"
        )

    @task(1)
    def create_sticker(self):
        if not self.pack_ids:
            return
        pack_id = random.choice(self.pack_ids)
        payload = {
            "user_id": self.user_id,
            "s3_key": f"stickers/{pack_id}/{uuid.uuid4()}.png"
        }
        self.client.post(
            f"/packs/{pack_id}/stickers",
            json=payload,
            name="POST /packs/{pack_id}/stickers"
        )