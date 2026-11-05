import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from app.core.config import get_settings

# Same parameters as the Node backend so existing argon2id hashes keep working.
_hasher = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1, hash_len=32, salt_len=16)


def hash_password(plain: str) -> str:
    return _hasher.hash(plain)


def verify_password(password_hash: str, plain: str) -> bool:
    try:
        return _hasher.verify(password_hash, plain)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def random_token() -> str:
    return secrets.token_urlsafe(48)


def generate_temp_password() -> str:
    # 12+ chars, letters + numbers, single-use temporary credential.
    return f"Rx-{secrets.token_hex(5)}{secrets.token_hex(2)}A7"


def encode_access_token(payload: dict[str, Any], ttl_seconds: int | None = None) -> str:
    settings = get_settings()
    now = datetime.now(timezone.utc)
    body = dict(payload)
    body["iat"] = now
    body["exp"] = now + timedelta(seconds=ttl_seconds or settings.jwt_access_ttl_seconds)
    return jwt.encode(body, settings.jwt_access_secret, algorithm="HS256")


def decode_access_token(token: str) -> dict[str, Any]:
    settings = get_settings()
    return jwt.decode(token, settings.jwt_access_secret, algorithms=["HS256"])
