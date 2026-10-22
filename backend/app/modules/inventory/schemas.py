from datetime import datetime, timezone

from pydantic import BaseModel, Field


class CreateInventoryItemIn(BaseModel):
    medicineName: str = Field(min_length=2, max_length=160)
    barcode: str = Field(min_length=1, max_length=80)
    batchNumber: str = Field(min_length=1, max_length=80)
    expiryDate: str
    quantity: int = Field(ge=0)
    sellingPrice: float = Field(ge=0)
    reorderLevel: int | None = Field(default=None, ge=0)
    storeId: str | None = None


class BulkInventoryIn(BaseModel):
    items: list[CreateInventoryItemIn] = Field(min_length=1, max_length=500)


class UpdateInventoryItemIn(BaseModel):
    medicineName: str | None = Field(default=None, min_length=2, max_length=160)
    barcode: str | None = Field(default=None, min_length=1, max_length=80)
    batchNumber: str | None = Field(default=None, min_length=1, max_length=80)
    expiryDate: str | None = None
    quantity: int | None = Field(default=None, ge=0)
    sellingPrice: float | None = Field(default=None, ge=0)
    reorderLevel: int | None = Field(default=None, ge=0)


class ImportTemplateIn(BaseModel):
    """Body for POST /api/inventory/import-template."""

    templateId: str = Field(min_length=2, max_length=64)
    storeId: str | None = None
    # Owner overrides; anything left out falls back to the template default.
    sellingPrice: float | None = Field(default=None, ge=0)
    batchNumber: str | None = Field(default=None, min_length=1, max_length=80)
    quantity: int = Field(default=0, ge=0)
    expiryMonthsAhead: int = Field(default=12, ge=1, le=60)
    # Owner tick-list: import only these template barcodes. Empty/omitted
    # means import every item of the template.
    selectedBarcodes: list[str] | None = Field(default=None, max_length=100)
    # Optional per-line barcode remap {templateBarcode: editedBarcode} so a
    # shop can keep its scanner stock codes.
    itemBarcodes: dict[str, str] | None = None


class AdjustStockIn(BaseModel):
    """Body for POST /api/inventory/items/{id}/adjust (inward / outward)."""

    type: str = Field(min_length=2, max_length=8)  # IN or OUT
    quantity: int = Field(ge=1)
    reason: str | None = Field(default=None, max_length=200)


def parse_datetime(value: str) -> datetime:
    raw = value.strip()
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        parsed = datetime.strptime(value.strip(), "%Y-%m-%d")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed
