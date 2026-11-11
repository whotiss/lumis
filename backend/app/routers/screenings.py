"""Screenings: submit a photo (FR1, FR3, FR4, FR9), history (FR7), delete (FR10)."""
from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import Settings
from ..deps import current_user, get_db, get_predictor, get_settings, get_storage
from ..ml.predictor import UnsupportedImageError
from ..models import Condition, Screening, User, as_utc
from ..schemas import ConditionRef, ScreeningOut, SymptomDetails
from ..storage import LocalImageStorage
from ..wording import BAND_LABELS, DISCLAIMER, PHOTO_CHECK_TEXT, result_text

router = APIRouter(prefix="/screenings", tags=["screenings"])


def to_out(s: Screening) -> ScreeningOut:
    text = result_text(s.band, s.condition.name, s.condition.urgency_default)
    return ScreeningOut(
        id=s.id, created_at=as_utc(s.created_at), band=s.band, band_label=BAND_LABELS[s.band],
        condition=ConditionRef(id=s.condition.id, name=s.condition.name) if text.show_condition else None,
        confidence=round(s.confidence_value, 2) if text.show_condition else None,
        headline=text.headline, advice=text.advice, recommended_action=text.recommended_action,
        show_clinics=text.show_clinics, disclaimer=DISCLAIMER,
        symptom_details=SymptomDetails(**s.symptom_details) if s.symptom_details else None,
        image_available=s.image_reference is not None, model_version=s.model_version)


def _own_screening(screening_id: int, user: User, db: Session) -> Screening:
    s = db.get(Screening, screening_id)
    if s is None or s.user_id != user.id:              # someone else's screening looks the same as a missing one
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Screening not found.")
    return s


@router.post("", response_model=ScreeningOut, status_code=status.HTTP_201_CREATED,
             responses={422: {"description": "Photo check failed: detail.code is 'no_skin' or 'nothing_detected', "
                                             "with headline and advice to show"}})
def create_screening(
    image: UploadFile = File(..., description="JPEG, PNG or WebP photo of the skin"),
    duration: str | None = Form(None, description="under_1_week | 1_to_4_weeks | over_1_month"),
    itchy: bool | None = Form(None),
    changing: bool | None = Form(None),
    user: User = Depends(current_user), db: Session = Depends(get_db), predictor=Depends(get_predictor),
    storage: LocalImageStorage = Depends(get_storage), settings: Settings = Depends(get_settings),
):
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
    try:
        prediction = predictor.predict(data)
    except UnsupportedImageError as exc:
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, str(exc))
    if prediction.status != "ok":
        # Photo check failed: nothing is saved, and the app shows this message instead of a result
        raise HTTPException(422, {"code": prediction.status, **PHOTO_CHECK_TEXT[prediction.status],
                                  "disclaimer": DISCLAIMER})

    condition = db.get(Condition, prediction.condition)
    if condition is None:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Condition reference data is missing.")
    text = result_text(prediction.band, condition.name, condition.urgency_default)
    reference = storage.save(user.id, data) if user.consent_storage else None
    s = Screening(user_id=user.id, image_reference=reference,
                  symptom_details=details.model_dump(exclude_none=True) or None,
                  predicted_condition_id=condition.id, confidence_value=prediction.confidence,
                  band=prediction.band, capped=prediction.capped, recommended_action=text.recommended_action,
                  probabilities=prediction.probabilities, model_version=prediction.model_version)
    db.add(s)
    try:
        db.commit()
    except Exception:
        if reference:
            storage.delete(reference)
        raise
    db.refresh(s)
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
              storage: LocalImageStorage = Depends(get_storage)):
    s = _own_screening(screening_id, user, db)
    if not s.image_reference:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No photo was stored for this screening.")
    return Response(storage.load(s.image_reference), media_type=storage.media_type(s.image_reference))


@router.delete("/{screening_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_screening(screening_id: int, user: User = Depends(current_user), db: Session = Depends(get_db),
                     storage: LocalImageStorage = Depends(get_storage)):
    s = _own_screening(screening_id, user, db)
    if s.image_reference:
        storage.delete(s.image_reference)
    db.delete(s)
    db.commit()
