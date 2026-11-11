"""Accounts: register, log in, consent settings, delete account (FR11, NFR4)."""
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import Settings
from ..deps import current_user, get_db, get_settings, get_storage
from ..models import User, as_utc, utcnow
from ..schemas import ConsentIn, RegisterIn, TokenOut, UserOut
from ..security import create_token, hash_password, verify_password
from ..storage import LocalImageStorage

router = APIRouter(tags=["account"])


def _user_out(user: User) -> UserOut:
    return UserOut(id=user.id, email=user.email, consent_storage=user.consent_storage,
                   consent_location=user.consent_location, created_at=as_utc(user.created_at))


@router.post("/auth/register", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
def register(body: RegisterIn, db: Session = Depends(get_db), settings: Settings = Depends(get_settings)):
    email = body.email.lower()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(status.HTTP_409_CONFLICT, "An account with this email already exists.")
    user = User(email=email, password_hash=hash_password(body.password), consent_storage=body.consent_storage,
                consent_storage_at=utcnow() if body.consent_storage else None)
    db.add(user)
    db.commit()
    return TokenOut(access_token=create_token(user.id, settings.jwt_secret, settings.jwt_expire_days))


@router.post("/auth/login", response_model=TokenOut)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db),
          settings: Settings = Depends(get_settings)):
    """Form fields `username` (the email) and `password`, the standard OAuth2 shape."""
    user = db.scalar(select(User).where(User.email == form.username.lower()))
    if user is None or not verify_password(form.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Wrong email or password.")
    return TokenOut(access_token=create_token(user.id, settings.jwt_secret, settings.jwt_expire_days))


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(current_user)):
    return _user_out(user)


@router.patch("/me/consent", response_model=UserOut)
def update_consent(body: ConsentIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Each change is time-stamped, so consent is logged before location is used (NFR4).
    Turning storage off does not delete past images; the user deletes screenings for that (FR10)."""
    if body.consent_storage is not None and body.consent_storage != user.consent_storage:
        user.consent_storage, user.consent_storage_at = body.consent_storage, utcnow()
    if body.consent_location is not None and body.consent_location != user.consent_location:
        user.consent_location, user.consent_location_at = body.consent_location, utcnow()
    db.commit()
    return _user_out(user)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(user: User = Depends(current_user), db: Session = Depends(get_db),
                   storage: LocalImageStorage = Depends(get_storage)):
    """Deletes the account, every screening and every stored image."""
    for s in user.screenings:
        if s.image_reference:
            storage.delete(s.image_reference)
    db.delete(user)
    db.commit()
