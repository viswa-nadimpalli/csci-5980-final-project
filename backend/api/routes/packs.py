from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import String, cast, func, or_
from sqlalchemy.exc import IntegrityError

from core.db import get_db
from core.models import PackMembership, PackRole, StickerPack, User
from core.cache import cache_delete, cache_get, cache_set

router = APIRouter(prefix="/packs", tags=["packs"])


def _get_pack_or_404(pack_id: UUID, db: Session) -> StickerPack:
    pack = db.get(StickerPack, pack_id)
    if not pack:
        raise HTTPException(status_code=404, detail="Pack not found")
    return pack


def _effective_role(user_id: UUID, pack: StickerPack, db: Session) -> str | None:
    """Return 'owner', 'contributor', 'viewer', or None if the user has no access."""
    if pack.owner_id == user_id:
        return "owner"
    membership = db.get(PackMembership, (user_id, pack.id))
    return membership.role.value if membership else None


def _require_role(user_id: UUID, pack: StickerPack, db: Session, *allowed: str) -> None:
    role = _effective_role(user_id, pack, db)
    if role not in allowed:
        raise HTTPException(status_code=403, detail="Insufficient permissions")


class PackCreate(BaseModel):
    name: str
    description: str | None = None
    owner_id: UUID


class PackOut(BaseModel):
    id: UUID
    name: str
    description: str | None = None
    owner_id: UUID

    class Config:
        from_attributes = True


class MemberAdd(BaseModel):
    user_id: UUID
    role: PackRole  # contributor | viewer only


class MemberOut(BaseModel):
    user_id: UUID
    pack_id: UUID
    role: PackRole

    class Config:
        from_attributes = True


class TransferOwnership(BaseModel):
    new_owner_id: UUID


@router.post("", response_model=PackOut, status_code=status.HTTP_201_CREATED)
async def create_pack(
    payload: PackCreate,
    db: Session = Depends(get_db),
):
    pack = StickerPack(
        name=payload.name,
        description=payload.description,
        owner_id=payload.owner_id,
    )
    db.add(pack)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="You already have a pack with that name")
    db.refresh(pack)
    await cache_delete(f"packs:user:{payload.owner_id}")
    return pack


@router.get("/{pack_id}", response_model=PackOut)
async def get_pack(
    pack_id: UUID,
    requester_id: UUID = Query(...),
    db: Session = Depends(get_db),
):
    cache_key = f"pack:{pack_id}"
    cached = await cache_get(cache_key)
    if cached is not None:
        # Auth still requires a DB lookup; ownership is stored in the cached payload
        # so we only hit the DB for membership check when the requester is not the owner.
        pack = _get_pack_or_404(pack_id, db)
        _require_role(requester_id, pack, db, "owner", "contributor", "viewer")
        return cached

    pack = _get_pack_or_404(pack_id, db)
    _require_role(requester_id, pack, db, "owner", "contributor", "viewer")
    out = PackOut.model_validate(pack).model_dump(mode="json")
    await cache_set(cache_key, out)
    return out


@router.get("", response_model=list[PackOut])
async def list_packs(
    requester_id: UUID = Query(...),
    db: Session = Depends(get_db),
):
    cache_key = f"packs:user:{requester_id}"
    cached = await cache_get(cache_key)
    if cached is not None:
        return cached

    if not db.get(User, requester_id):
        raise HTTPException(status_code=404, detail="User not found")

    requester_hex = requester_id.hex

    membership_pack_ids = (
        db.query(PackMembership.pack_id)
        .filter(PackMembership.user_id == requester_id)
    )

    packs = (
        db.query(StickerPack)
        .filter(
            or_(
                StickerPack.owner_id == requester_id,
                # Fallback compare for deployments where UUID may be surfaced
                # as text with formatting differences.
                func.lower(func.replace(cast(StickerPack.owner_id, String), "-", "")) == requester_hex,
                StickerPack.id.in_(membership_pack_ids),
            )
        )
        .order_by(StickerPack.name.asc(), StickerPack.id.asc())
        .all()
    )

    out = [PackOut.model_validate(p).model_dump(mode="json") for p in packs]
    await cache_set(cache_key, out)
    return out


@router.delete("/{pack_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_pack(
    pack_id: UUID,
    requester_id: UUID = Query(...),
    db: Session = Depends(get_db),
):
    pack = _get_pack_or_404(pack_id, db)
    _require_role(requester_id, pack, db, "owner")
    db.delete(pack)
    db.commit()
    await cache_delete(f"pack:{pack_id}", f"packs:user:{requester_id}")


@router.post("/{pack_id}/members", response_model=MemberOut, status_code=status.HTTP_201_CREATED)
async def add_member(
    pack_id: UUID,
    payload: MemberAdd,
    requester_id: UUID = Query(...),
    db: Session = Depends(get_db),
):
    pack = _get_pack_or_404(pack_id, db)
    # owner and contributor can add members
    _require_role(requester_id, pack, db, "owner", "contributor")

    if payload.user_id == pack.owner_id:
        raise HTTPException(status_code=409, detail="User is already the owner of this pack")

    if not db.get(User, payload.user_id):
        raise HTTPException(status_code=404, detail="User not found")

    existing = db.get(PackMembership, (payload.user_id, pack_id))
    if existing:
        raise HTTPException(status_code=409, detail="User is already a member of this pack")

    membership = PackMembership(user_id=payload.user_id, pack_id=pack_id, role=payload.role)
    db.add(membership)
    db.commit()
    db.refresh(membership)
    # New member's pack list is now stale, as is the pack's own cached record.
    await cache_delete(f"packs:user:{payload.user_id}", f"pack:{pack_id}")
    return membership


@router.delete("/{pack_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_member(
    pack_id: UUID,
    user_id: UUID,
    requester_id: UUID = Query(...),
    db: Session = Depends(get_db),
):
    pack = _get_pack_or_404(pack_id, db)
    # only owner can remove members
    _require_role(requester_id, pack, db, "owner")

    membership = db.get(PackMembership, (user_id, pack_id))
    if not membership:
        raise HTTPException(status_code=404, detail="Membership not found")
    db.delete(membership)
    db.commit()
    await cache_delete(f"packs:user:{user_id}", f"pack:{pack_id}")


@router.post("/{pack_id}/transfer-ownership", response_model=PackOut)
async def transfer_ownership(
    pack_id: UUID,
    payload: TransferOwnership,
    requester_id: UUID = Query(...),
    db: Session = Depends(get_db),
):
    pack = _get_pack_or_404(pack_id, db)
    _require_role(requester_id, pack, db, "owner")

    if payload.new_owner_id == pack.owner_id:
        raise HTTPException(status_code=409, detail="User is already the owner")

    if not db.get(User, payload.new_owner_id):
        raise HTTPException(status_code=404, detail="New owner user not found")

    old_owner_id = pack.owner_id

    # if the new owner has an existing membership, remove it (they'll be owner via FK)
    existing = db.get(PackMembership, (payload.new_owner_id, pack_id))
    if existing:
        db.delete(existing)

    # demote current owner to contributor
    old_owner_membership = db.get(PackMembership, (pack.owner_id, pack_id))
    if old_owner_membership:
        old_owner_membership.role = PackRole.contributor
    else:
        db.add(PackMembership(user_id=pack.owner_id, pack_id=pack_id, role=PackRole.contributor))

    pack.owner_id = payload.new_owner_id
    db.commit()
    db.refresh(pack)
    await cache_delete(
        f"pack:{pack_id}",
        f"packs:user:{old_owner_id}",
        f"packs:user:{payload.new_owner_id}",
    )
    return pack
