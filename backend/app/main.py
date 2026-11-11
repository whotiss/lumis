"""Lumis API. Run locally from the backend folder:  uvicorn app.main:app --reload
Interactive docs at http://127.0.0.1:8000/docs"""
import json
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from sqlalchemy.orm import sessionmaker

from .config import Settings, get_settings
from .db import Base, make_engine
from .ml.predictor import LumisPredictor
from .models import Condition
from .routers import auth, info, screenings
from .storage import LocalImageStorage

CONDITIONS_FILE = Path(__file__).parent / "data" / "conditions.json"


def seed_conditions(session_factory) -> None:
    """Insert or update the condition reference rows from data/conditions.json."""
    with session_factory() as db:
        for row in json.loads(CONDITIONS_FILE.read_text(encoding="utf-8")):
            db.merge(Condition(**row))
        db.commit()


def create_app(settings: Settings | None = None, predictor=None) -> FastAPI:
    settings = settings or get_settings()
    settings.check()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        engine = make_engine(settings.database_url)
        Base.metadata.create_all(engine)
        app.state.settings = settings
        app.state.session_factory = sessionmaker(engine, expire_on_commit=False)
        seed_conditions(app.state.session_factory)
        app.state.predictor = predictor or LumisPredictor.from_dir(settings.model_dir)
        app.state.storage = LocalImageStorage(settings.image_dir)
        missing = set(app.state.predictor.config.classes) - {r["id"] for r in json.loads(CONDITIONS_FILE.read_text())}
        if missing:
            raise RuntimeError(f"conditions.json has no entry for model classes: {sorted(missing)}")
        yield
        engine.dispose()

    app = FastAPI(title="Lumis API", version="0.1.0", lifespan=lifespan,
                  description="Skin condition screening aid. Results are screening indications, not diagnoses.")
    app.include_router(info.router)
    app.include_router(auth.router)
    app.include_router(screenings.router)
    return app


app = create_app()
