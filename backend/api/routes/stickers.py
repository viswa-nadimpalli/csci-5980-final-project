import uuid
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from core.db import get_db
from core.models import Image, PackMembership, StickerPack
from core.s3 import presigned_download_url, presigned_upload_url
from core.config import settings

router = APIRouter(tags=["stickers"])


class UploadUrlOut(BaseModel):
    upload_url: str
    s3_key: str
    expires_in: int


class StickerCreate(BaseModel):
    user_id: UUID
    s3_key: str


class StickerOut(BaseModel):
    id: UUID
    pack_id: UUID
    uploaded_by: UUID
    s3_key: str
    download_url: str


def _effective_role(db: Session, user_id: UUID, pack_id: UUID) -> str | None:
    """Return 'owner', 'contributor', 'viewer', or None"""
    pack = db.get(StickerPack, pack_id)
    if not pack:
        return None
    if pack.owner_id == user_id:
        return "owner"
    membership = db.get(PackMembership, (user_id, pack_id))
    return membership.role.value if membership else None


def _require_role(db: Session, user_id: UUID, pack_id: UUID, *allowed: str) -> None:
    role = _effective_role(db, user_id, pack_id)
    if role not in allowed:
        raise HTTPException(status_code=403, detail="Insufficient permissions")


def _sticker_out(image: Image) -> StickerOut:
    return StickerOut(
        id=image.id,
        pack_id=image.pack_id,
        uploaded_by=image.uploaded_by,
        s3_key=image.s3_key,
        download_url=presigned_download_url(image.s3_key),
    )


@router.get("/packs/{pack_id}/stickers/upload-url", response_model=UploadUrlOut)
def get_upload_url(
    pack_id: UUID,
    user_id: UUID = Query(...),
    db: Session = Depends(get_db),
):
    """Generate a presigned S3 PUT URL. Client uploads directly to S3, then calls POST /stickers to register."""
    _require_role(db, user_id, pack_id, "owner", "contributor")
    s3_key = f"packs/{pack_id}/stickers/{uuid.uuid4()}"
    url = presigned_upload_url(s3_key)
    return UploadUrlOut(upload_url=url, s3_key=s3_key, expires_in=settings.PRESIGN_EXPIRES_SECONDS)


@router.post("/packs/{pack_id}/stickers", response_model=StickerOut, status_code=status.HTTP_201_CREATED)
def add_sticker(pack_id: UUID, payload: StickerCreate, db: Session = Depends(get_db)):
    """Register a sticker in the DB after the file has been uploaded to S3."""
    _require_role(db, payload.user_id, pack_id, "owner", "contributor")
    sticker = Image(pack_id=pack_id, uploaded_by=payload.user_id, s3_key=payload.s3_key)
    db.add(sticker)
    db.commit()
    db.refresh(sticker)
    return _sticker_out(sticker)


@router.get("/packs/{pack_id}/stickers", response_model=list[StickerOut])
def list_stickers(pack_id: UUID, user_id: UUID = Query(...), db: Session = Depends(get_db)):
    _require_role(db, user_id, pack_id, "owner", "contributor", "viewer")
    images = db.query(Image).filter_by(pack_id=pack_id).order_by(Image.created_at.desc()).all()
    return [_sticker_out(img) for img in images]


@router.delete("/stickers/{sticker_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_sticker(sticker_id: UUID, user_id: UUID = Query(...), db: Session = Depends(get_db)):
    sticker = db.get(Image, sticker_id)
    if not sticker:
        raise HTTPException(status_code=404, detail="Sticker not found")
    _require_role(db, user_id, sticker.pack_id, "owner", "contributor")
    db.delete(sticker)
    db.commit()

