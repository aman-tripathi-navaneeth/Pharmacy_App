from pydantic import BaseModel, Field, field_validator

from app.common.identity import normalize_phone


class CreateCustomerIn(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    phone: str | None = Field(default=None, max_length=20)
    notes: str | None = Field(default=None, max_length=500)

    @field_validator("phone")
    @classmethod
    def _phone(cls, value: str | None) -> str | None:
        if value is None or value.strip() == "":
            return None
        digits = "".join(ch for ch in value if ch.isdigit())
        if len(digits) < 10 or len(digits) > 13:
            raise ValueError("Enter a valid 10-digit mobile number")
        return normalize_phone(value)


class UpdateCustomerIn(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    phone: str | None = Field(default=None, max_length=20)
    notes: str | None = Field(default=None, max_length=500)

    @field_validator("phone")
    @classmethod
    def _phone(cls, value: str | None) -> str | None:
        if value is None or value.strip() == "":
            return None
        digits = "".join(ch for ch in value if ch.isdigit())
        if len(digits) < 10 or len(digits) > 13:
            raise ValueError("Enter a valid 10-digit mobile number")
        return normalize_phone(value)


class PaymentIn(BaseModel):
    amount: float = Field(gt=0)
    note: str | None = Field(default=None, max_length=300)
