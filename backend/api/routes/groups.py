from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ...core.models import Group, GroupMembership, GroupRole
# from {something} import get_db, get_current_user

router = APIRouter(prefix="/groups", tags=["groups"])

@router.post("/")
def create_group(name: str,
                 db: Session = Depends(get_db),
                 user=Depends(get_current_user)):
    
    group = Group(name=name, created_by=user.id)
    db.add(group)
    db.commit()
    db.refresh(group)

    membership = GroupMembership(user_id=user.id, group_id=group.id, role = GroupRole.owner)
    db.add(membership)
    db.commit()

    return group