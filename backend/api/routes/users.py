from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy import String, cast, func, or_, select
from sqlalchemy.orm import Session

from core.db import get_db
from core.models import PackMembership, StickerPack, User

router = APIRouter(prefix="/users", tags=["users"])

def hash_password(raw_password: str) -> str:
    # do something here
    return f"hashed::{raw_password}"

class UserOut(BaseModel):
    id: UUID
    email: EmailStr

    class Config:
        from_attributes = True

class UserCreate(BaseModel):
    email: EmailStr
    password: str


class PackVersionOut(BaseModel):
    pack_id: UUID
    pack_version: int


@router.post("", response_model=UserOut, status_code=201)
def create_user(payload: UserCreate, db: Session = Depends(get_db)):
    user = User(email=payload.email, hashed_password=hash_password(payload.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.get("/{user_id}/pack-versions", response_model=list[PackVersionOut])
def get_pack_versions(user_id: UUID, db: Session = Depends(get_db)):
    if not db.get(User, user_id):
        raise HTTPException(status_code=404, detail="User not found")

    membership_pack_ids = (
        db.query(PackMembership.pack_id)
        .filter(PackMembership.user_id == user_id)
    )

    user_hex = user_id.hex

    packs = (
        db.query(StickerPack)
        .filter(
            or_(
                StickerPack.owner_id == user_id,
                # Keep this consistent with /packs for deployments where UUIDs
                # are surfaced as text with formatting differences.
                func.lower(func.replace(cast(StickerPack.owner_id, String), "-", "")) == user_hex,
                StickerPack.id.in_(membership_pack_ids),
            )
        )
        .order_by(StickerPack.name.asc(), StickerPack.id.asc())
        .all()
    )

    return [PackVersionOut(pack_id=p.id, pack_version=p.pack_version) for p in packs]
