-- Pharmacy store backend schema (PostgreSQL 13+).
-- Run with: python scripts/init_db.py

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL DEFAULT '',
    email_normalized TEXT UNIQUE,
    phone_e164 TEXT UNIQUE,
    password_hash TEXT,
    role TEXT NOT NULL DEFAULT 'SHOP_OWNER',
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    must_change_password BOOLEAN NOT NULL DEFAULT FALSE,
    owner_store_id UUID,
    language TEXT,
    plan TEXT,
    plan_started_at TIMESTAMPTZ,
    plan_expires_at TIMESTAMPTZ,
    plan_payment_status TEXT,
    profile_image TEXT,
    phone_verified_at TIMESTAMPTZ,
    email_verified_at TIMESTAMPTZ,
    profile_completed_at TIMESTAMPTZ,
    onboarding_completed_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id UUID,
    refresh_token_hash TEXT NOT NULL UNIQUE,
    token_family_id TEXT NOT NULL,
    device_label TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions (user_id);

CREATE TABLE IF NOT EXISTS shops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_name TEXT NOT NULL,
    owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    address JSONB NOT NULL DEFAULT '{}'::jsonb,
    phone_e164 TEXT,
    email_normalized TEXT,
    licence_details JSONB,
    payment_settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS shops_owner_idx ON shops (owner_user_id);

CREATE TABLE IF NOT EXISTS inventory_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    medicine_name TEXT NOT NULL,
    barcode TEXT NOT NULL,
    batch_number TEXT NOT NULL,
    expiry_date TIMESTAMPTZ,
    quantity INTEGER NOT NULL DEFAULT 0,
    selling_price DOUBLE PRECISION NOT NULL DEFAULT 0,
    reorder_level INTEGER NOT NULL DEFAULT 10,
    created_by UUID,
    archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS inventory_store_barcode_batch_idx
    ON inventory_items (store_id, barcode, batch_number);
CREATE INDEX IF NOT EXISTS inventory_store_idx ON inventory_items (store_id);

CREATE TABLE IF NOT EXISTS stock_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
    movement_type TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    reason TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    balance DOUBLE PRECISION NOT NULL DEFAULT 0,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS customers_store_idx ON customers (store_id);

CREATE TABLE IF NOT EXISTS customer_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    amount DOUBLE PRECISION NOT NULL,
    note TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS bills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    invoice_number TEXT NOT NULL UNIQUE,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    customer_name TEXT,
    customer_phone TEXT,
    items JSONB NOT NULL DEFAULT '[]'::jsonb,
    subtotal DOUBLE PRECISION NOT NULL DEFAULT 0,
    discount DOUBLE PRECISION NOT NULL DEFAULT 0,
    tax_percent DOUBLE PRECISION NOT NULL DEFAULT 0,
    tax DOUBLE PRECISION NOT NULL DEFAULT 0,
    total DOUBLE PRECISION NOT NULL DEFAULT 0,
    paid_amount DOUBLE PRECISION NOT NULL DEFAULT 0,
    due_amount DOUBLE PRECISION NOT NULL DEFAULT 0,
    payment_status TEXT NOT NULL DEFAULT 'PAID',
    payment_method TEXT NOT NULL DEFAULT 'CASH',
    notes TEXT,
    batch_number TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS bills_store_created_idx ON bills (store_id, created_at DESC);

CREATE TABLE IF NOT EXISTS prescriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    patient_name TEXT NOT NULL,
    patient_phone TEXT,
    medicine_name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'pending',
    notes TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id UUID,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'SYSTEM',
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS notifications_user_idx ON notifications (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS issues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID,
    created_by UUID NOT NULL,
    created_by_role TEXT,
    created_by_name TEXT,
    category TEXT NOT NULL DEFAULT 'OTHER',
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'OPEN',
    admin_notes TEXT,
    resolution_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS email_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template TEXT NOT NULL,
    recipient_email TEXT NOT NULL DEFAULT '',
    recipient_name TEXT,
    recipient_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    store_id UUID,
    subject TEXT NOT NULL DEFAULT '',
    body_preview TEXT,
    body_text TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING',
    error_message TEXT,
    provider TEXT NOT NULL DEFAULT 'smtp',
    is_action_required BOOLEAN NOT NULL DEFAULT FALSE,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS email_logs_recipient_idx ON email_logs (recipient_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS email_logs_store_idx ON email_logs (store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS email_logs_status_idx ON email_logs (status, created_at DESC);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID,
    actor_role TEXT,
    action TEXT NOT NULL,
    target_type TEXT,
    target_id TEXT,
    store_id UUID,
    result TEXT NOT NULL DEFAULT 'SUCCESS',
    ip_address TEXT,
    request_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS audit_actor_idx ON audit_logs (actor_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID,
    email_normalized TEXT,
    phone_e164 TEXT,
    token_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'SHOP_OWNER',
    attempts INTEGER NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ,
    used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    contact_name TEXT,
    phone TEXT,
    email TEXT,
    gstin TEXT,
    address JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS suppliers_store_idx ON suppliers (store_id);

CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    po_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ORDERED',
    expected_date TEXT,
    notes TEXT,
    total DOUBLE PRECISION NOT NULL DEFAULT 0,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS purchase_orders_store_idx ON purchase_orders (store_id);

CREATE TABLE IF NOT EXISTS purchase_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    medicine_name TEXT NOT NULL,
    barcode TEXT,
    batch_number TEXT,
    quantity INTEGER NOT NULL DEFAULT 0,
    unit_cost DOUBLE PRECISION NOT NULL DEFAULT 0,
    expiry_date TEXT
);

ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS client_ref TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS stock_movements_client_ref_idx
    ON stock_movements (store_id, client_ref) WHERE client_ref IS NOT NULL;

-- Existing inventory predates the stock ledger; record its current quantity once
-- as the opening balance so movement history reconciles with on-hand stock.
INSERT INTO stock_movements
    (store_id, item_id, movement_type, quantity, reason, created_by, client_ref, created_at)
SELECT
    item.store_id,
    item.id,
    'IN',
    item.quantity,
    'Opening stock baseline reconciled from existing inventory',
    item.created_by,
    'opening-stock:' || item.id::text,
    item.created_at
FROM inventory_items AS item
WHERE item.quantity > 0
  AND NOT EXISTS (
      SELECT 1
      FROM stock_movements AS movement
      WHERE movement.item_id = item.id
  );
