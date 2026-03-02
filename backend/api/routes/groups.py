from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from core.db import get_db
from core.models import Group, GroupMembership, GroupRole


def get_current_user():
    raise HTTPException(status_code=501, detail="get_current_user dependency not configured")


class GroupCreate(BaseModel):
    name: str
    owner: UUID


class GroupOut(BaseModel):
    id: UUID
    name: str

    class Config:
        from_attributes = True

router = APIRouter(prefix="/groups", tags=["groups"])

@router.post("", response_model=GroupOut, status_code=status.HTTP_201_CREATED)
def create_group(
    payload: GroupCreate,
    db: Session = Depends(get_db),
    # user=Depends(get_current_user),
):
    group = Group(name=payload.name)
    db.add(group)
    db.commit()
    db.refresh(group)

    membership = GroupMembership(user_id=payload.owner, group_id=group.id, role=GroupRole.owner)
    db.add(membership)
    db.commit()

    return group
