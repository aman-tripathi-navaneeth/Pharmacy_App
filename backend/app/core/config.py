from functools import lru_cache
from pathlib import Path

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    app_name: str = "Pharmacy Store Application API"
    app_env: str = "development"
    api_prefix: str = "/api"
    api_v1_prefix: str = "/api/v1"

    DATABASE_URL: str = ""
    cors_origins: str = "*"

    jwt_access_secret: str = "development-only-change-this-secret-before-deploy"
    jwt_access_ttl_seconds: int = 900
    jwt_refresh_ttl_days: int = 7

    otp_ttl_minutes: int = 10
    otp_max_attempts: int = 5
    tmp_password_ttl_hours: int = 24

    seed_superadmin_identifier: str = "superadmin@medishop.local"
    seed_superadmin_password: str = ""
    seed_owner_identifier: str = "+919876512345"
    seed_owner_password: str = ""

    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from_email: str = ""
    smtp_from_name: str = "MediShop"
    smtp_use_tls: bool = True
    smtp_use_ssl: bool = False
    smtp_timeout_seconds: int = 15
    email_enabled: bool = True
    app_base_url: str = "http://127.0.0.1:8000"
    support_email: str = ""

    @property
    def database_url(self) -> str:
        return self.DATABASE_URL

    @property
    def asyncpg_url(self) -> str:
        url = self.DATABASE_URL.strip()
        if url.startswith("postgresql+asyncpg://"):
            return "postgresql://" + url[len("postgresql+asyncpg://"):]
        return url

    @property
    def sqlalchemy_database_url(self) -> str:
        url = self.DATABASE_URL.strip()
        if url.startswith("postgresql://"):
            return "postgresql+asyncpg://" + url[len("postgresql://"):]
        if url.startswith("postgres://"):
            return "postgresql+asyncpg://" + url[len("postgres://"):]
        return url

    @model_validator(mode="after")
    def validate_jwt_secret(self) -> "Settings":
        if len(self.jwt_access_secret.encode("utf-8")) < 32:
            raise ValueError("JWT_ACCESS_SECRET must be at least 32 bytes.")
        if self.app_env.strip().lower() in {"prod", "production"} and (
            self.jwt_access_secret
            in {
                "development-only-change-this-secret-before-deploy",
                "replace-with-a-long-random-secret",
            }
        ):
            raise ValueError("Set a unique JWT_ACCESS_SECRET before production.")
        return self

    model_config = SettingsConfigDict(
        env_file=str(BACKEND_DIR / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    @property
    def parsed_cors_origins(self) -> list[str]:
        origins = [
            origin.strip()
            for origin in self.cors_origins.split(",")
            if origin.strip()
        ]
        return origins or ["*"]

    @property
    def is_development(self) -> bool:
        return self.app_env.strip().lower() == "development"

    @property
    def uses_postgresql(self) -> bool:
        return self.DATABASE_URL.strip().lower().startswith(
            ("postgresql://", "postgres://", "postgresql+asyncpg://")
        )

    @property
    def smtp_configured(self) -> bool:
        return bool(self.smtp_host.strip() and self.smtp_from_email.strip())

    @property
    def mail_enabled(self) -> bool:
        return bool(self.email_enabled and self.smtp_configured)


@lru_cache
def get_settings() -> Settings:
    return Settings()
