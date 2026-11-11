"""Public information: health check, model version (NFR7), condition reference (FR8)."""
import json

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..deps import get_db
from ..models import Condition
from ..schemas import ConditionOut, ModelInfoOut

router = APIRouter(tags=["info"])


@router.get("/health")
def health(request: Request):
    return {"status": "ok", "model_version": request.app.state.predictor.config.model_version}


@router.get("/model", response_model=ModelInfoOut)
def model_info(request: Request):
    cfg = request.app.state.predictor.config
    test_results = None
    config_path = request.app.state.settings.model_dir / "lumis_model_config.json"
    if config_path.exists():
        test_results = json.loads(config_path.read_text()).get("test_results")
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
