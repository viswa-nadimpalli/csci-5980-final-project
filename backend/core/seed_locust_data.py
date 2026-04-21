import csv
import uuid
from pathlib import Path

from core.db import SessionLocal, Base, engine
from core.models import User, StickerPack, Image

OUT_DIR = Path(__file__).parent

USER_COUNT = 100
PACKS_PER_USER = 5
STICKERS_PER_PACK = 20


def main():
    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    users_csv = []
    packs_csv = []

    try:
        for i in range(USER_COUNT):
            user = User(
                email=f"loadtest-{i}@example.com",
                hashed_password="hashed::loadtest",
            )
            db.add(user)
            db.flush()

            users_csv.append({"user_id": str(user.id)})

            for j in range(PACKS_PER_USER):
                pack = StickerPack(
                    name=f"loadtest-user-{i}-pack-{j}",
                    description="Locust benchmark seed pack",
                    owner_id=user.id,
                )
                db.add(pack)
                db.flush()

                packs_csv.append({
                    "user_id": str(user.id),
                    "pack_id": str(pack.id),
                })

                for k in range(STICKERS_PER_PACK):
                    sticker_id = uuid.uuid4()
                    db.add(Image(
                        id=sticker_id,
                        pack_id=pack.id,
                        uploaded_by=user.id,
                        s3_key=f"loadtest/packs/{pack.id}/stickers/{sticker_id}.png",
                    ))

        db.commit()

    except Exception:
        db.rollback()
        raise

    finally:
        db.close()

    with open(OUT_DIR / "test_users.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["user_id"])
        writer.writeheader()
        writer.writerows(users_csv)

    with open(OUT_DIR / "test_packs.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["user_id", "pack_id"])
        writer.writeheader()
        writer.writerows(packs_csv)


if __name__ == "__main__":
    main()
