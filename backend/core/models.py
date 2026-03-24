import uuid
import enum
from sqlalchemy import Column, String, ForeignKey, DateTime, Enum, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .db import Base 
from datetime import datetime, timezone

class PackRole(str, enum.Enum):
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

    owned_packs = relationship("StickerPack", back_populates="owner", foreign_keys="StickerPack.owner_id")
    memberships = relationship("PackMembership", back_populates="user", cascade="all, delete-orphan")
    images = relationship("Image", back_populates="uploader")

class StickerPack(Base):
    __tablename__ = "sticker_packs"

    __table_args__ = (UniqueConstraint("name", "owner_id", name="uq_pack_name_owner"),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String, nullable=False)
    description = Column(String, nullable=True)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

    owner = relationship("User", back_populates="owned_packs", foreign_keys=[owner_id])
    memberships = relationship("PackMembership", back_populates="pack", cascade="all, delete-orphan")
    images = relationship("Image", back_populates="pack", cascade="all, delete-orphan")

class PackMembership(Base):
    __tablename__ = "pack_memberships"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    pack_id = Column(UUID(as_uuid=True), ForeignKey("sticker_packs.id"), primary_key=True)
    role = Column(Enum(PackRole), nullable=False)

    user = relationship("User", back_populates="memberships")
    pack = relationship("StickerPack", back_populates="memberships")

class Image(Base):
    __tablename__ = "images"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    pack_id = Column(UUID(as_uuid=True), ForeignKey("sticker_packs.id", ondelete="CASCADE"), nullable=False)
    uploaded_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

    s3_key = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

    pack = relationship("StickerPack", back_populates="images")
    uploader = relationship("User", back_populates="images")

class UserIdentities(Base):
    __tablename__ = "user_identities"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    provider = Column(Enum(AuthProvider), nullable=False)
    provider_sub = Column(String, nullable=False)

    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

    __table_args__ = (UniqueConstraint("provider", "provider_sub", name="uq_identity_provider_sub"),)

    user = relationship("User", back_populates="identities")
