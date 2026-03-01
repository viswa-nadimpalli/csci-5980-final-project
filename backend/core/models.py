import uuid
import enum
from sqlalchemy import Column, String, ForeignKey, DateTime, Enum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .db import Base 
from datetime import datetime, timezone

class GroupRole(str, enum.Enum):
    owner = "owner"
    contributor = "contributor"
    viewer = "viewer"

class AuthProvider(str, enum.Enum):
    apple = "apple"
    google = "google"

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String, unique=True)
    hashed_password = Column(String)

    identities = relationship("UserIdentities", back_populates="user", cascade="all, delete-orphan")

    memberships = relationship("GroupMembership", back_populates="user", cascade="all, delete-orphan")
    images = relationship("Image", back_populates="uploader")

class Group(Base):
    __tablename__ = "groups"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String, unique=True, nullable=False)

    memberships = relationship("GroupMembership", back_populates="group", cascade="all, delete-orphan")
    images = relationship("Image", back_populates="group")

class GroupMembership(Base):
    __tablename__ = "group_memberships"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    group_id = Column(UUID(as_uuid=True), ForeignKey("groups.id"), primary_key=True)
    role = Column(Enum(GroupRole), nullable=False)

    user = relationship("User", back_populates="memberships")
    group = relationship("Group", back_populates="memberships")

class Image(Base):
    __tablename__ = "images"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    group_id = Column(UUID(as_uuid=True), ForeignKey("groups.id"), nullable=False)
    uploaded_by = Column(UUID(as_uuid=True), ForeignKey("users.id"))

    s3_key = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

    group = relationship("Group", back_populates="images")
    uploader = relationship("User", back_populates="images")

class UserIdentities(Base):
    __tablename__ = "user_identities"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    provider = Column(Enum(AuthProvider), nullable=False)
    provider_sub = Column(String, nullable=False)

    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

    user = relationship("User", back_populates="identities")

# CREATE TABLE IF NOT EXISTS user_identities (
#     id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
#     user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
#     provider        TEXT NOT NULL,             -- e.g., "google", "apple"
#     provider_sub    TEXT NOT NULL,             -- provider subject/id
#     created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
#     UNIQUE(provider, provider_sub)
# );