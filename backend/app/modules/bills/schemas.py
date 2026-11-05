import re
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.common.identity import normalize_phone


class BillItemIn(BaseModel):
    inventoryItemId: str | None = None
    medicineName: str | None = Field(default=None, max_length=160)
    batchNumber: str | None = Field(default=None, max_length=80)
    quantity: int = Field(ge=1)
    unitPrice: float = Field(ge=0)


class CreateBillIn(BaseModel):
    customerId: str | None = None
    customerName: str | None = Field(default=None, max_length=120)
    customerPhone: str | None = Field(default=None, max_length=20)

    @field_validator("customerPhone")
    @classmethod
    def _phone(cls, value: str | None) -> str | None:
        if value is None or value.strip() == "":
            return None
        digits = re.sub(r"\D", "", value)
        if len(digits) < 10 or len(digits) > 13:
            raise ValueError("Enter a valid 10-digit mobile number")
        return normalize_phone(value)
    items: list[BillItemIn] = Field(min_length=1)
    discount: float = Field(default=0, ge=0)
    taxPercent: float = Field(default=0, ge=0, le=100)
    paymentStatus: Literal["PAID", "PARTIAL", "CREDIT"] = "PAID"
    paymentMethod: Literal["CASH", "ONLINE"] = "CASH"
    paidAmount: float | None = Field(default=None, ge=0)
    notes: str | None = Field(default=None, max_length=500)
    storeId: str | None = None
