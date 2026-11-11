"""Settings, read from environment variables or backend/.env (never committed). See .env.example."""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[1]
DEV_SECRET = "dev-only-not-a-secret-set-JWT_SECRET-in-production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BACKEND_DIR / ".env", env_file_encoding="utf-8",
                                      extra="ignore", protected_namespaces=())

    environment: str = "development"                 # 'development' or 'production'
    database_url: str = f"sqlite:///{(BACKEND_DIR / 'lumis_dev.db').as_posix()}"
    jwt_secret: str = DEV_SECRET
    jwt_expire_days: int = 7
    model_dir: Path = BACKEND_DIR / "models"
    image_dir: Path = BACKEND_DIR / "uploads"         # local image store for development
    max_upload_mb: int = 10

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024

    def check(self) -> None:
        """Refuse to run in production with development defaults."""
        if self.environment == "production":
            if self.jwt_secret == DEV_SECRET or len(self.jwt_secret) < 32:
                raise RuntimeError("Set JWT_SECRET to a long random value in production.")
            if self.database_url.startswith("sqlite"):
                raise RuntimeError("Production must use PostgreSQL (DATABASE_URL).")


@lru_cache
def get_settings() -> Settings:
    return Settings()
