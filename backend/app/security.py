"""Passwords (Argon2id, salted: FR11) and login tokens (JWT)."""
from datetime import datetime, timedelta, timezone

import jwt
from pwdlib import PasswordHash

_hasher = PasswordHash.recommended()        # Argon2id with a random salt per password
ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return _hasher.verify(password, password_hash)


def create_token(user_id: int, secret: str, expire_days: int) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub": str(user_id), "iat": now, "exp": now + timedelta(days=expire_days)},
                      secret, algorithm=ALGORITHM)


def read_token(token: str, secret: str) -> int | None:
    try:
        return int(jwt.decode(token, secret, algorithms=[ALGORITHM])["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        return None
