-- -----------------------------
-- RRFC Inventory Schema (Postgres)
-- Designed for Supabase / PostgreSQL
-- Option C: Simple roles now (Admin / Manager / User).
-- -----------------------------

-- 0. Extensions (optional, useful)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- for UUID generation

-- 1. Users & Roles (simple role model)
CREATE TABLE app_users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email text NOT NULL UNIQUE,
  display_name text,
  role text NOT NULL DEFAULT 'user', -- allowed: admin, manager, user
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  disabled boolean NOT NULL DEFAULT false
);

CREATE INDEX idx_app_users_email ON app_users (email);

-- 2. Lookup lists (Categories, Colors, Sizes, Materials, Item Types, Transaction Types)
CREATE TABLE lookup_list (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  list_key text NOT NULL,          -- e.g., 'category', 'color', 'item_type', 'transaction_type'
  value text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  applicable_to text,              -- comma separated item types (optional)
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_lookup_list_key_value ON lookup_list (list_key, value);

-- 3. Vendors
CREATE TABLE vendors (
  id text PRIMARY KEY, -- keep vendor IDs like 'VEN-001' if you want readable IDs; or use uuid
  vendor_name text NOT NULL,
  contact_person text,
  email text,
  phone text,
  address text,
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_vendors_name ON vendors (vendor_name);

-- 4. Items (master list)
CREATE TABLE items (
  item_id text PRIMARY KEY, -- preserve existing ITEM-0001 style IDs
  item_type text NOT NULL,  -- replicate item type strings from Lists
  category text,
  name text NOT NULL,
  description text,
  color text,
  size text,
  material text,
  active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_items_name ON items (name);
CREATE INDEX idx_items_type ON items (item_type);
CREATE INDEX idx_items_category ON items (category);

-- 5. Inventory batches (each purchase creates a batch record)
CREATE TABLE inventory_batches (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  batch_code text NOT NULL,       -- e.g., 'BATCH-20250101-123456'
  vendor_id text REFERENCES vendors(id),
  transaction_date date NOT NULL,
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  notes text
);

CREATE INDEX idx_batches_batch_code ON inventory_batches (batch_code);
CREATE INDEX idx_batches_vendor_date ON inventory_batches (vendor_id, transaction_date);

-- 6. Transactions (line-level entries stored here; includes purchases, returns, corrections)
CREATE TABLE transactions (
  id text PRIMARY KEY,            -- preserve transaction id format (PUR..., RET..., COR...)
  transaction_date timestamptz NOT NULL,
  transaction_type text NOT NULL, -- e.g., Purchase, Return, Correction, Transfer, Waste, Damage, Loss
  vendor_id text REFERENCES vendors(id),
  batch_id uuid REFERENCES inventory_batches(id),
  item_id text REFERENCES items(item_id),
  item_type text,
  category text,
  item_name text,
  color text,
  size text,
  material text,
  quantity numeric NOT NULL,      -- positive for purchase, negative for reduction (returns/corrections)
  unit_price numeric DEFAULT 0,   -- base unit price (no shipping)
  shipping numeric DEFAULT 0,     -- shipping portion for this line (could be negative for return)
  total_cost numeric DEFAULT 0,   -- item line total (qty * unit_price + shipping)
  notes text,
  related_txn_id text,            -- for returns/corrections: store original transaction id
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_txn_item ON transactions (item_id);
CREATE INDEX idx_txn_vendor ON transactions (vendor_id);
CREATE INDEX idx_txn_date ON transactions (transaction_date);
CREATE INDEX idx_txn_type_date ON transactions (transaction_type, transaction_date);

-- 7. MAC ledger (moving average cost per item, snapshot form)
CREATE TABLE mac_ledger (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_id text REFERENCES items(item_id),
  snapshot_date timestamptz NOT NULL DEFAULT now(),
  quantity_on_hand numeric NOT NULL DEFAULT 0,
  mac numeric NOT NULL DEFAULT 0,       -- moving average cost per unit
  total_value numeric NOT NULL DEFAULT 0,
  last_updated_by uuid REFERENCES app_users(id),
  note text
);

CREATE INDEX idx_mac_item ON mac_ledger (item_id);
-- Optionally keep only latest per item by an application-level rule.

-- 8. Return details (optional normalized table if you prefer)
CREATE TABLE returns (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  return_txn_id text REFERENCES transactions(id),
  original_txn_id text,
  returned_quantity numeric,
  refund_amount numeric,
  restocking_fee numeric,
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 9. Corrections log (to record correction metadata)
CREATE TABLE corrections (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  original_txn_id text,
  reversal_txn_id text,
  corrected_txn_id text,
  reason text,
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 10. Audit/log table for key events
CREATE TABLE system_logs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor uuid REFERENCES app_users(id),
  action text NOT NULL,
  entity_type text,
  entity_id text,
  details jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_logs_actor_time ON system_logs (actor, created_at);

-- 11. Optional: sequencers table to emulate numeric sequences for IDs (if desired)
CREATE TABLE id_counters (
  name text PRIMARY KEY,
  last_value bigint NOT NULL DEFAULT 0
);
-- We'll use this only if you want to auto-generate readable sequential IDs (ITEM-0001 style) server-side.

-- 12. Helpful Views (example: latest MAC per item)
CREATE VIEW current_mac AS
SELECT DISTINCT ON (item_id)
  item_id, quantity_on_hand, mac, total_value, last_updated_by, snapshot_date
FROM mac_ledger
ORDER BY item_id, snapshot_date DESC;
