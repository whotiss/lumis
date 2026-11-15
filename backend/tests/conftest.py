"""Tests never read backend/.env or this computer's environment variables. They behave the same everywhere,
and they can never call the real Claude API or touch a real database or bucket by accident."""
import pytest

from app.config import Settings

LUMIS_VARIABLES = ["ENVIRONMENT", "DATABASE_URL", "JWT_SECRET", "JWT_EXPIRE_DAYS", "ANTHROPIC_API_KEY", "IMAGE_BUCKET",
                   "IMAGE_DIR", "MODEL_DIR", "MODEL_CONFIG_FILE", "PHOTO_CHECK_FILE", "ONNX_THREADS", "MAX_UPLOAD_MB",
                   "LOG_LEVEL"]


@pytest.fixture(autouse=True)
def _isolated_settings(monkeypatch):
    monkeypatch.setitem(Settings.model_config, "env_file", None)
    for name in LUMIS_VARIABLES:
        monkeypatch.delenv(name, raising=False)
