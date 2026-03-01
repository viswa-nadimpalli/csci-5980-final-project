from fastapi import FastAPI

from api.routes.health import router as health_router
from api.routes.packs import router as packs_router

from core.db import engine, Base
import core.models

app = FastAPI(title="Sticker")

# create tables automatically (MVP only, Alembic later)
@app.on_event("startup")
def startup():
    Base.metadata.create_all(bind=engine)

app.include_router(health_router)
app.include_router(packs_router)