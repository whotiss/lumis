"""Screenings: submit a photo (FR1, FR3, FR4, FR9), history (FR7), delete (FR10)."""
import logging
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import Settings
from ..deps import current_user, get_claude_checker, get_db, get_predictor, get_settings, get_storage
from ..consent import CONSENT_VERSION
from ..ml.claude_check import ClaudeVerdict, gate, late
from .auth import has_current_consent
from ..ml.predictor import UnsupportedImageError, decode_image
from ..models import Condition, Screening, User, as_utc
from ..schemas import ConditionRef, ExplanationOut, ScreeningOut, SymptomDetails
from ..storage import ImageStorage
from ..wording import BAND_LABELS, DISCLAIMER, PHOTO_CHECK_TEXT, explanation, photo_fit, result_text

router = APIRouter(prefix="/screenings", tags=["screenings"])
log = logging.getLogger("lumis.screenings")
# Claude's call runs here while the model runs in the request thread. A late call finishes in the background and
# is ignored. Cloud Run sends at most 4 requests at once to one instance (deploy step 8), so 8 workers is plenty.
_claude_pool = ThreadPoolExecutor(max_workers=8, thread_name_prefix="claude")


def to_out(s: Screening) -> ScreeningOut:
    text = result_text(s.band, s.condition.name, s.condition.urgency_default, photo_fit(s.condition.id, s.claude_check))
    exp = explanation(s.band, s.condition, s.claude_check)
    return ScreeningOut(
        id=s.id, created_at=as_utc(s.created_at), band=s.band, band_label=BAND_LABELS[s.band],
        condition=ConditionRef(id=s.condition.id, name=s.condition.name) if text.show_condition else None,
        confidence=round(s.confidence_value, 2) if text.show_condition else None,
        headline=text.headline, advice=text.advice, recommended_action=text.recommended_action,
        show_clinics=text.show_clinics, disclaimer=DISCLAIMER,
        symptom_details=SymptomDetails(**s.symptom_details) if s.symptom_details else None,
        image_available=s.image_reference is not None, model_version=s.model_version,
        explanation=ExplanationOut(**exp.__dict__) if exp else None)


def _own_screening(screening_id: int, user: User, db: Session) -> Screening:
    s = db.get(Screening, screening_id)
    if s is None or s.user_id != user.id:              # someone else's screening looks the same as a missing one
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Screening not found.")
    return s


@router.post("", response_model=ScreeningOut, status_code=status.HTTP_201_CREATED,
             responses={422: {"description": "Photo check failed: detail.code is 'no_skin', 'poor_photo' or 'nothing_detected', "
                                             "with headline and advice to show"}})
def create_screening(
    response: Response,
    image: UploadFile = File(..., description="JPEG, PNG or WebP photo of the skin"),
    duration: str | None = Form(None, description="under_1_week | 1_to_4_weeks | over_1_month"),
    itchy: bool | None = Form(None),
    changing: bool | None = Form(None),
    user: User = Depends(current_user), db: Session = Depends(get_db), predictor=Depends(get_predictor),
    storage: ImageStorage = Depends(get_storage), settings: Settings = Depends(get_settings),
    claude=Depends(get_claude_checker),
):
    if not has_current_consent(user):
        # Nothing is analyzed or sent anywhere until the person has agreed to the current consent text
        raise HTTPException(status.HTTP_403_FORBIDDEN, {"code": "consent_required", "current_version": CONSENT_VERSION,
                                                        "message": "Please read and agree to the consent text first."})
    data = image.file.read(settings.max_upload_bytes + 1)
    if not data:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "The photo is empty.")
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(413,
                            f"The photo is larger than {settings.max_upload_mb} MB.")
    try:
        details = SymptomDetails(duration=duration, itchy=itchy, changing=changing)
    except ValueError:
        raise HTTPException(422, "Unknown duration value.")
    started = time.perf_counter()
    # Claude's part starts now, in parallel with the model (Phase 5 rule 2), so both finish at about the same time
    claude_job = None
    if claude is not None:
        names = {c.id: c.name for c in db.scalars(select(Condition).where(Condition.id.in_(predictor.config.classes)))}
        claude_job = _claude_pool.submit(lambda: claude.check(decode_image(data), names))
    try:
        prediction = predictor.predict(data)
    except UnsupportedImageError as exc:
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, str(exc))
    # speed of each step, for measurements and the app's network log (no health data in it)
    timing = getattr(prediction, "timing_ms", None)
    timing_header = {"Server-Timing": ", ".join(f"{k};dur={v}" for k, v in timing.items())} if timing else {}
    response.headers.update(timing_header)
    if prediction.status != "ok":
        # Photo check failed: nothing is saved, and the app shows this message instead of a result
        raise HTTPException(422, {"code": prediction.status, **PHOTO_CHECK_TEXT[prediction.status],
                                  "disclaimer": DISCLAIMER}, headers=timing_header or None)

    condition = db.get(Condition, prediction.condition)
    if condition is None:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Condition reference data is missing.")

    # Claude's part (only if switched on): wait for it until CLAUDE_WAIT_SECONDS after the upload, then go without it.
    # It can stop a photo with no skin in it; it never changes the condition or the band (Phase 5 rule 1).
    band, verdict = prediction.band, None
    if claude_job is not None:
        remaining = max(0.0, settings.claude_wait_seconds - (time.perf_counter() - started))
        try:
            verdict = claude_job.result(timeout=remaining)
        except FutureTimeout:
            verdict = late(claude.model, (time.perf_counter() - started) * 1000)
        except Exception as exc:                        # e.g. the photo could not be decoded for Claude
            verdict = ClaudeVerdict(ok=False, error=f"error: {type(exc).__name__}", model=claude.model)
        # Whether Claude's part ran is visible in the logs and the timing header: a skipped part is not an error for
        # the user (the result is shown without it), so without this a wrong key or an outage would go unnoticed.
        (log.info if verdict.ok and not verdict.filtered else log.warning)(
            "Claude check %s in %.0f ms", verdict.outcome, verdict.ms or 0)
        timing_header = {"Server-Timing": ", ".join(filter(None, [timing_header.get("Server-Timing"),
                                                                 f'claude;dur={verdict.ms or 0};desc="{verdict.outcome}"']))}
        response.headers.update(timing_header)
        if gate(verdict, claude.skin_gate) != "ok":
            raise HTTPException(422, {"code": "no_skin", **PHOTO_CHECK_TEXT["no_skin"], "disclaimer": DISCLAIMER},
                                headers=timing_header or None)

    claude_record = verdict.to_dict() if verdict else None
    text = result_text(band, condition.name, condition.urgency_default, photo_fit(condition.id, claude_record))
    reference = storage.save(user.id, data) if user.consent_storage else None
    s = Screening(user_id=user.id, image_reference=reference,
                  symptom_details=details.model_dump(exclude_none=True) or None,
                  predicted_condition_id=condition.id, confidence_value=prediction.confidence,
                  band=band, capped=prediction.capped, recommended_action=text.recommended_action,
                  probabilities=prediction.probabilities, model_version=prediction.model_version,
                  model_band=prediction.band, claude_check=claude_record)
    db.add(s)
    try:
        db.commit()
    except Exception:
        if reference:
            storage.delete(reference)
        raise
    db.refresh(s)
    total_ms = round((time.perf_counter() - started) * 1000, 1)
    response.headers["Server-Timing"] = ", ".join(filter(None, [timing_header.get("Server-Timing"),
                                                               f"screening;dur={total_ms}"]))
    return to_out(s)


@router.get("", response_model=list[ScreeningOut])
def history(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(Screening).where(Screening.user_id == user.id)
                      .order_by(Screening.created_at.desc(), Screening.id.desc()))
    return [to_out(s) for s in rows]


@router.get("/{screening_id}", response_model=ScreeningOut)
def get_screening(screening_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return to_out(_own_screening(screening_id, user, db))


@router.get("/{screening_id}/image", responses={200: {"content": {"image/jpeg": {}}}})
def get_image(screening_id: int, user: User = Depends(current_user), db: Session = Depends(get_db),
              storage: ImageStorage = Depends(get_storage)):
    s = _own_screening(screening_id, user, db)
    if not s.image_reference:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No photo was stored for this screening.")
    try:
        data = storage.load(s.image_reference)
    except FileNotFoundError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "The stored photo could not be found.")
    return Response(data, media_type=storage.media_type(s.image_reference))


@router.delete("/{screening_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_screening(screening_id: int, user: User = Depends(current_user), db: Session = Depends(get_db),
                     storage: ImageStorage = Depends(get_storage)):
    s = _own_screening(screening_id, user, db)
    if s.image_reference:
        storage.delete(s.image_reference)
    db.delete(s)
    db.commit()
