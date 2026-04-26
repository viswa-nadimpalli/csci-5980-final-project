from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from core.config import settings

engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_size=20,
    max_overflow=20,
    pool_timeout=30,
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
