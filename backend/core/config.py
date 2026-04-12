from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DATABASE_URL: str

    AWS_ACCESS_KEY_ID: str
    AWS_SECRET_ACCESS_KEY: str
    AWS_REGION: str = "us-east-2"
    S3_BUCKET: str
    PRESIGN_EXPIRES_SECONDS: int = 300

    CLERK_JWKS_URL: str
    CLERK_ISSUER: str
    CLERK_AUTHORIZED_PARTY: str | None = None

settings = Settings()
