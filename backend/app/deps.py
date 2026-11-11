"""Shared FastAPI dependencies."""
from collections.abc import Iterator

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from .config import Settings
from .models import User
from .security import read_token
from .storage import LocalImageStorage

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_db(request: Request) -> Iterator[Session]:
    with request.app.state.session_factory() as session:
        yield session


def get_predictor(request: Request):
    return request.app.state.predictor


def get_claude_checker(request: Request):
    return getattr(request.app.state, "claude_checker", None)


def get_storage(request: Request) -> LocalImageStorage:
    return request.app.state.storage


def current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db),
                 settings: Settings = Depends(get_settings)) -> User:
    user_id = read_token(token, settings.jwt_secret)
    user = db.get(User, user_id) if user_id is not None else None
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Please log in again.",
                            headers={"WWW-Authenticate": "Bearer"})
    return user
