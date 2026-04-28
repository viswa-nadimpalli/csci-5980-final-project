from fastapi import FastAPI
from sqlalchemy import inspect, text

from api.routes.health import router as health_router
from api.routes.packs import router as packs_router
from api.routes.users import router as users_router
from api.routes.stickers import router as stickers_router

from core.db import engine, Base
import core.models

app = FastAPI(title="Sticker")


def ensure_schema() -> None:
    inspector = inspect(engine)
    if "sticker_packs" not in inspector.get_table_names():
        return

    columns = {column["name"] for column in inspector.get_columns("sticker_packs")}
    if "pack_version" not in columns:
        with engine.begin() as connection:
            connection.execute(
                text("ALTER TABLE sticker_packs ADD COLUMN pack_version INTEGER NOT NULL DEFAULT 0")
            )
            if "stickers_version" in columns:
                connection.execute(
                    text("UPDATE sticker_packs SET pack_version = stickers_version WHERE pack_version = 0")
                )

@app.on_event("startup")
def startup():
    ensure_schema()
    Base.metadata.create_all(bind=engine)

app.include_router(health_router)
app.include_router(packs_router)
app.include_router(users_router)
app.include_router(stickers_router)
