"""Public information: health check, model version (NFR7), condition reference (FR8)."""
import json

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..consent import LANGUAGES, consent_document
from ..deps import get_db, get_settings
from ..models import Condition
from ..schemas import ConditionOut, ConsentOut, ModelInfoOut

router = APIRouter(tags=["info"])


@router.get("/health")
def health(request: Request):
    return {"status": "ok", "model_version": request.app.state.predictor.config.model_version}


@router.get("/model", response_model=ModelInfoOut)
def model_info(request: Request):
    cfg = request.app.state.predictor.config
    test_results = None
    settings = request.app.state.settings
    config_path = settings.model_dir / settings.model_config_file
    if config_path.exists():
        c = json.loads(config_path.read_text())
        test_results = c.get("test_results") or c.get("test")          # v1 key, v3 key
    return ModelInfoOut(model_version=cfg.model_version, classes=cfg.classes,
                        bands={"high_from": cfg.high_from, "refer_below": cfg.refer_below,
                               "never_high": cfg.cap_at_moderate,
                               "claude_check": request.app.state.claude_checker is not None,
                               "claude_full_check": getattr(request.app.state.claude_checker, "full", False)},
                        test_results=test_results)


@router.get("/conditions", response_model=list[ConditionOut])
def conditions(db: Session = Depends(get_db)):
    return [ConditionOut.model_validate(c, from_attributes=True)
            for c in db.scalars(select(Condition).order_by(Condition.name))]


@router.get("/consent", response_model=ConsentOut)
def consent(lang: str = "en", settings=Depends(get_settings)):
    """The consent screen (NFR4, PDPA): shown before registering, and again whenever its version changes.
    `lang` is "en" or "ms" (Bahasa Malaysia); both must be offered."""
    if lang not in LANGUAGES:
        raise HTTPException(422, f"lang must be one of {list(LANGUAGES)}")
    return consent_document(lang, settings.contact_email or "the Lumis project team")
