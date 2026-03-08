from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.orm import Session

from core.db import get_db
from core.models import User

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

@router.post("", response_model=UserOut, status_code=201)
def create_user(payload: UserCreate, db: Session = Depends(get_db)):
    user = User(email=payload.email, hashed_password=hash_password(payload.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    return user