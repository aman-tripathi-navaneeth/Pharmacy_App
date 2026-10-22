from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    app_name: str = "Pharmacy Store Application API"
    app_env: str = "development"
    api_prefix: str = "/api"

    # Database configuration - PostgreSQL only
    DATABASE_URL: str = "postgresql://postgres:postgres@localhost:5432/medishop_dev"
    cors_origins: str = "*"

    jwt_access_secret: str = "dev_secret"
    jwt_access_ttl_seconds: int = 900
    jwt_refresh_ttl_days: int = 7

    otp_ttl_minutes: int = 10
    otp_max_attempts: int = 5
    tmp_password_ttl_hours: int = 24

    seed_superadmin_identifier: str = "superadmin@medishop.local"
    seed_superadmin_password: str = "SuperAdmin#2026"
    seed_owner_identifier: str = "+919876512345"
    seed_owner_password: str = "OwnerTemp#8821"

    # Email delivery (SMTP). Credentials, first-login, action-required and
    # issue updates are only sent when SMTP_HOST and SMTP_FROM_EMAIL are set.
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
    # Public base URL used for "open the app" links inside emails.
    app_base_url: str = "http://127.0.0.1:8000"
    support_email: str = ""

    model_config = SettingsConfigDict(
        env_file=str(BACKEND_DIR / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    @property
    def parsed_cors_origins(self) -> list[str]:
        origins = [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]
        return origins or ["*"]

    @property
    def is_development(self) -> bool:
        return self.app_env.strip().lower() == "development"

    @property
    def uses_postgresql(self) -> bool:
        """Check if the app is configured to use PostgreSQL."""
        return self.DATABASE_URL and self.DATABASE_URL.startswith("postgresql")

    @property
    def smtp_configured(self) -> bool:
        """True when there is enough SMTP configuration to attempt a send."""
        return bool(self.smtp_host.strip() and self.smtp_from_email.strip())

    @property
    def mail_enabled(self) -> bool:
        """True when emails should actually leave the application."""
        return bool(self.email_enabled and self.smtp_configured)

@lru_cache
def get_settings() -> Settings:
    return Settings()