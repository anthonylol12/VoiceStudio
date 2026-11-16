"""Password hashing (stdlib scrypt) and JWT bearer tokens."""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .config import get_settings
from .db import User, get_db

_N, _R, _P = 2**14, 8, 1


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=32)
    return f"scrypt${_N}${_R}${_P}${base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _, n, r, p, salt, digest = stored.split("$")
        calc = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p), dklen=32)
        return hmac.compare_digest(calc, base64.b64decode(digest))
    except Exception:
        return False


def create_token(user_id: str) -> str:
    s = get_settings()
    payload = {"sub": user_id, "exp": datetime.now(UTC) + timedelta(minutes=s.token_minutes), "iat": datetime.now(UTC)}
    return jwt.encode(payload, s.secret_key, algorithm="HS256")


def decode_token(token: str) -> str:
    try:
        return jwt.decode(token, get_settings().secret_key, algorithms=["HS256"])["sub"]
    except jwt.PyJWTError as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token no válido o caducado") from e


_bearer = HTTPBearer(auto_error=False)


def ai_guard(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> None:
    """Optional authentication for AI endpoints (VS_REQUIRE_AUTH_FOR_AI)."""
    if not get_settings().require_auth_for_ai:
        return
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Autenticación requerida")
    decode_token(creds.credentials)


def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer), db: Session = Depends(get_db)
) -> User:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Autenticación requerida")
    user = db.get(User, decode_token(creds.credentials))
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Usuario no encontrado")
    return user
