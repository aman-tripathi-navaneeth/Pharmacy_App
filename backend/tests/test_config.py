import asyncio

import pytest
from pydantic import ValidationError

from app.core.config import Settings
from scripts import seed_demo


def test_jwt_secret_requires_at_least_32_bytes() -> None:
    with pytest.raises(ValidationError, match="at least 32 bytes"):
        Settings(_env_file=None, jwt_access_secret="short")


def test_production_rejects_the_development_jwt_secret() -> None:
    with pytest.raises(ValidationError, match="unique JWT_ACCESS_SECRET"):
        Settings(
            _env_file=None,
            app_env="production",
            jwt_access_secret="development-only-change-this-secret-before-deploy",
        )


def test_demo_seed_passwords_must_be_configured_explicitly() -> None:
    settings = Settings(_env_file=None)

    assert settings.seed_superadmin_password == ""
    assert settings.seed_owner_password == ""


def test_demo_seed_fails_before_connecting_without_passwords(monkeypatch) -> None:
    settings = Settings(
        _env_file=None,
        DATABASE_URL="postgresql://localhost/medishop_dev",
    )
    monkeypatch.setattr(seed_demo, "get_settings", lambda: settings)

    with pytest.raises(RuntimeError, match="SEED_SUPERADMIN_PASSWORD"):
        asyncio.run(seed_demo.seed_demo_data())
