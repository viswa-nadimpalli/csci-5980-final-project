from fastapi import FastAPI

from api.routes.health import router as health_router
from api.routes.packs import router as packs_router
from api.routes.users import router as users_router
from api.routes.stickers import router as stickers_router

from core.db import engine, Base
import core.models

app = FastAPI(title="Sticker")

@app.on_event("startup")
def startup():
    Base.metadata.create_all(bind=engine)

app.include_router(health_router)
app.include_router(packs_router)
app.include_router(users_router)
app.include_router(stickers_router)