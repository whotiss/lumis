"""Settings, read from environment variables or backend/.env (never committed). See .env.example."""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[1]
DEV_SECRET = "dev-only-not-a-secret-set-JWT_SECRET-in-production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BACKEND_DIR / ".env", env_file_encoding="utf-8",
                                      extra="ignore", protected_namespaces=(),
                                      str_strip_whitespace=True)   # a stray newline in a secret must not break it

    environment: str = "development"                 # 'development' or 'production'
    database_url: str = f"sqlite:///{(BACKEND_DIR / 'lumis_dev.db').as_posix()}"
    jwt_secret: str = DEV_SECRET
    jwt_expire_days: int = 7
    model_dir: Path = BACKEND_DIR / "models"
    model_config_file: str = "lumis_model_config_v3.json"   # MODEL_CONFIG_FILE; v1: lumis_model_config.json
    photo_check_file: str = "photo_check_v3.json"           # PHOTO_CHECK_FILE; v1: photo_check.json
    onnx_threads: int | None = None                    # ONNX_THREADS; default: ONNX Runtime decides (all cores)
    image_dir: Path = BACKEND_DIR / "uploads"         # local image store for development
    image_bucket: str | None = None                  # IMAGE_BUCKET: Cloud Storage bucket for photos (production)
    log_level: str = "INFO"
    max_upload_mb: int = 10
    anthropic_api_key: str | None = None             # ANTHROPIC_API_KEY; the Claude check runs only if set

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
            if not self.image_bucket:
                raise RuntimeError("Set IMAGE_BUCKET in production: the server's own disk is temporary, "
                                   "so photos saved there would be lost.")


@lru_cache
def get_settings() -> Settings:
    return Settings()
