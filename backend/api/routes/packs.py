from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from core.db import get_db
from core.models import StickerPack

router = APIRouter(prefix="/packs", tags=["packs"])

class PackCreate(BaseModel):
    name: str
    description: str | None = None
    thumbnail_key: str | None = None

class PackOut(BaseModel):
    id: int
    name: str
    description: str | None = None
    thumbnail_key: str | None = None

    class Config:
        from_attributes = True

@router.post("", response_model=PackOut, status_code=status.HTTP_201_CREATED)
def create_pack(payload: PackCreate, db: Session = Depends(get_db)):
    pack = StickerPack(**payload.model_dump())
    db.add(pack)
    db.commit()
    db.refresh(pack)
    return pack

@router.get("/{pack_id}", response_model=PackOut)
def get_pack(pack_id: int, db: Session = Depends(get_db)):
    pack = db.get(StickerPack, pack_id)
    if not pack:
        raise HTTPException(status_code=404, detail="Pack not found")
    return pack