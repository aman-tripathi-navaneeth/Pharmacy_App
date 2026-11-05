import re
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.common.identity import is_valid_contact

PASSWORD_MESSAGE = "Use at least 12 characters with letters and numbers"
_CONTACT_MESSAGE = "Enter a valid email or 10-digit mobile number"
_POSTAL_RE = re.compile(r"^[0-9]{5,10}$")
_OTP_RE = re.compile(r"^[0-9a-f]{8}$")


def _contact(value: str) -> str:
    if not is_valid_contact(value):
        raise ValueError(_CONTACT_MESSAGE)
    return value.strip()


def _strong_password(value: str) -> str:
    if len(value) < 12 or not re.search(r"[A-Za-z]", value) or not re.search(r"[0-9]", value):
        raise ValueError(PASSWORD_MESSAGE)
    return value


class LoginIn(BaseModel):
    identifier: str
    password: str = Field(min_length=1, max_length=128)

    _validate_identifier = field_validator("identifier")(_contact)


class RefreshIn(BaseModel):
    refreshToken: str = Field(min_length=10, max_length=256)


class ChangeTemporaryPasswordIn(BaseModel):
    newPassword: str
    confirmPassword: str = Field(min_length=1, max_length=128)

    _validate_password = field_validator("newPassword")(_strong_password)


class ChangePasswordIn(BaseModel):
    currentPassword: str = Field(min_length=1, max_length=128)
    newPassword: str
    confirmPassword: str = Field(min_length=1, max_length=128)

    _validate_password = field_validator("newPassword")(_strong_password)


class ContactVerificationRequestIn(BaseModel):
    email: bool | None = None


class ContactVerificationVerifyIn(BaseModel):
    code: str

    @field_validator("code")
    @classmethod
    def _validate_code(cls, value: str) -> str:
        if not _OTP_RE.match(value):
            raise ValueError("Enter the 8-character code")
        return value


class CompleteProfileIn(BaseModel):
    fullName: str = Field(min_length=2, max_length=120)
    shopName: str = Field(min_length=2, max_length=120)
    addressLine1: str = Field(min_length=4, max_length=200)
    addressLine2: str | None = Field(default=None, max_length=200)
    city: str = Field(min_length=2, max_length=80)
    state: str = Field(min_length=2, max_length=80)
    postalCode: str
    shopContactNumber: str

    @field_validator("postalCode")
    @classmethod
    def _validate_postal(cls, value: str) -> str:
        if not _POSTAL_RE.match(value):
            raise ValueError("Enter a valid postal code")
        return value

    @field_validator("shopContactNumber")
    @classmethod
    def _validate_contact(cls, value: str) -> str:
        return _contact(value)


class CompleteProfileLiteIn(BaseModel):
    """Payload sent by the mobile onboarding screen."""

    fullName: str | None = None
    shopName: str = Field(min_length=2, max_length=120)
    addressLine1: str | None = None
    addressLine2: str | None = None
    shopAddress: str | None = None
    city: str | None = None
    state: str | None = None
    postalCode: str | None = None
    shopContactNumber: str | None = None


class UpdateMeIn(BaseModel):
    fullName: str | None = Field(default=None, min_length=2, max_length=120)
    language: str | None = Field(default=None, max_length=8)
    plan: str | None = Field(default=None, max_length=32)
    # Small avatar stored as a data URL (base64) so no file server is needed.
    profileImage: str | None = Field(default=None, max_length=1_500_000)

    @field_validator("profileImage")
    @classmethod
    def _validate_profile_image(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if value.strip() == "":
            return ""
        if not re.match(r"^data:image/(png|jpe?g|webp);base64,[A-Za-z0-9+/=]+$", value):
            raise ValueError("Profile photo must be a PNG, JPG or WEBP image")
        return value


class PaymentSettingsIn(BaseModel):
    """Owner payment details used on bills and the customer-facing QR."""

    upiId: str | None = Field(default=None, max_length=120)
    payeeName: str | None = Field(default=None, max_length=120)
    qrImage: str | None = Field(default=None, max_length=1_500_000)
    cashEnabled: bool = True
    onlineEnabled: bool = True

    @field_validator("upiId")
    @classmethod
    def _validate_upi(cls, value: str | None) -> str | None:
        if value is None or value.strip() == "":
            return None
        cleaned = value.strip()
        if not re.match(r"^[A-Za-z0-9._-]{2,}@[A-Za-z]{2,}$", cleaned):
            raise ValueError("Enter a valid UPI ID, for example shop@okhdfcbank")
        return cleaned

    @field_validator("payeeName")
    @classmethod
    def _validate_payee(cls, value: str | None) -> str | None:
        return value.strip() if value and value.strip() else None

    @field_validator("qrImage")
    @classmethod
    def _validate_qr_image(cls, value: str | None) -> str | None:
        if value is None or value.strip() == "":
            return None
        if not re.match(r"^data:image/(png|jpe?g|webp);base64,[A-Za-z0-9+/=]+$", value):
            raise ValueError("QR code must be a PNG, JPG or WEBP image")
        return value


class CreateShopIn(BaseModel):
    shopName: str = Field(min_length=2, max_length=120)
    addressLine1: str = Field(min_length=4, max_length=200)
    addressLine2: str | None = Field(default=None, max_length=200)
    city: str = Field(min_length=2, max_length=80)
    state: str = Field(min_length=2, max_length=80)
    postalCode: str
    shopPhone: str
    shopEmail: str | None = None
    ownerFullName: str = Field(min_length=2, max_length=120)
    ownerContact: str
    licenceNumber: str | None = Field(default=None, min_length=2, max_length=120)
    licenceAuthority: str | None = Field(default=None, min_length=2, max_length=120)

    @field_validator("postalCode")
    @classmethod
    def _validate_postal(cls, value: str) -> str:
        if not _POSTAL_RE.match(value):
            raise ValueError("Enter a valid postal code")
        return value

    @field_validator("shopPhone", "ownerContact")
    @classmethod
    def _validate_contact(cls, value: str) -> str:
        return _contact(value)

    @field_validator("shopEmail")
    @classmethod
    def _validate_optional_email(cls, value: str | None) -> str | None:
        if value is None or value.strip() == "":
            return None
        return _contact(value)


class UpdateShopIn(BaseModel):
    shopName: str | None = Field(default=None, min_length=2, max_length=120)
    addressLine1: str | None = Field(default=None, min_length=4, max_length=200)
    addressLine2: str | None = Field(default=None, max_length=200)
    city: str | None = Field(default=None, min_length=2, max_length=80)
    state: str | None = Field(default=None, min_length=2, max_length=80)
    postalCode: str | None = None
    phone: str | None = None
    email: str | None = None
    paymentSettings: PaymentSettingsIn | None = None

    @field_validator("postalCode")
    @classmethod
    def _validate_optional_postal(cls, value: str | None) -> str | None:
        if value is None or value == "":
            return None
        if not _POSTAL_RE.match(value):
            raise ValueError("Enter a valid postal code")
        return value

    @field_validator("phone", "email")
    @classmethod
    def _validate_optional_contact(cls, value: str | None) -> str | None:
        if value is None or value.strip() == "":
            return None
        return _contact(value)


class ShopStatusIn(BaseModel):
    status: Literal["ACTIVE", "SUSPENDED"]


class RecoveryIn(BaseModel):
    newTempPassword: str | None = Field(default=None, min_length=10, max_length=20)
