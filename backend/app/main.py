"""Lumis API. Run locally from the backend folder:  uvicorn app.main:app --reload
Interactive docs at http://127.0.0.1:8000/docs"""
import json
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from sqlalchemy.orm import sessionmaker

from .config import Settings, get_settings
from .db import Base, add_missing_columns, make_engine
from .clinics import Directory
from .ml.claude_check import ClaudeCheckConfig, ClaudeChecker
from .ml.predictor import LumisPredictor
from .models import Condition
from .routers import auth, clinics, info, screenings
from .storage import make_storage

CONDITIONS_FILE = Path(__file__).parent / "data" / "conditions.json"


def seed_conditions(session_factory) -> None:
    """Insert or update the condition reference rows from data/conditions.json."""
    with session_factory() as db:
        for row in json.loads(CONDITIONS_FILE.read_text(encoding="utf-8")):
            db.merge(Condition(**row))
        db.commit()


def create_app(settings: Settings | None = None, predictor=None, claude_checker=None) -> FastAPI:
    settings = settings or get_settings()
    settings.check()
    # Lumis's own log lines (model version, time per photo) go to the console, which Cloud Run collects.
    # No email addresses, photos or results are logged.
    logging.basicConfig(level=settings.log_level.upper(), format="%(levelname)s %(name)s: %(message)s")

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        engine = make_engine(settings.database_url)
        Base.metadata.create_all(engine)
        added = add_missing_columns(engine)          # e.g. the consent columns, on a database made before them
        if added:
            logging.getLogger("lumis").info("database updated, columns added: %s", ", ".join(added))
        app.state.settings = settings
        app.state.session_factory = sessionmaker(engine, expire_on_commit=False)
        seed_conditions(app.state.session_factory)
        app.state.clinics = Directory.load()          # checked here, so a bad edit stops the start
        app.state.predictor = predictor or LumisPredictor.from_dir(
            settings.model_dir, settings.model_config_file, settings.photo_check_file, threads=settings.onnx_threads)
        app.state.storage = make_storage(settings)
        check_cfg = ClaudeCheckConfig.load(settings.model_dir / "claude_check.json")
        app.state.claude_checker = claude_checker or (
            ClaudeChecker(settings.anthropic_api_key, check_cfg.model, skin_gate=check_cfg.skin_gate,
                          full=check_cfg.enabled)
            if check_cfg.any and settings.anthropic_api_key else None)
        missing = set(app.state.predictor.config.classes) - {r["id"] for r in json.loads(CONDITIONS_FILE.read_text())}
        if missing:
            raise RuntimeError(f"conditions.json has no entry for model classes: {sorted(missing)}")
        logging.getLogger("lumis").info(
            "started: %s, model %s, photos in %s, Claude check %s, %d clinics", settings.environment,
            app.state.predictor.config.model_version,
            f"bucket {settings.image_bucket}" if settings.image_bucket else "local folder",
            "on" if app.state.claude_checker else "off", len(app.state.clinics.clinics))
        yield
        engine.dispose()

    app = FastAPI(title="Lumis API", version="0.1.0", lifespan=lifespan,
                  description="Skin condition screening aid. Results are screening indications, not diagnoses.")
    app.include_router(info.router)
    app.include_router(auth.router)
    app.include_router(screenings.router)
    app.include_router(clinics.router)
    return app


app = create_app()
