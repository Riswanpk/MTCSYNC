-- ============================================================
-- DME Module — Supabase PostgreSQL Schema
-- Run this in Supabase SQL Editor to create all tables
-- ============================================================

-- 1. DME Users — maps Firebase UID to DME role
CREATE TABLE IF NOT EXISTS dme_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid TEXT UNIQUE NOT NULL,
  email TEXT NOT NULL,
  username TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('dme_admin', 'dme_user')),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Branches
CREATE TABLE IF NOT EXISTS dme_branches (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL
);

-- 3. User ↔ Branch assignments (many-to-many)
CREATE TABLE IF NOT EXISTS dme_user_branches (
  user_id UUID REFERENCES dme_users(id) ON DELETE CASCADE,
  branch_id INT REFERENCES dme_branches(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, branch_id)
);

-- 4. Product master (one-time upload)
CREATE TABLE IF NOT EXISTS dme_products (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  unit TEXT NOT NULL,               -- PCS, MTR, SET, NOS, etc.
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Customer master (100k+ records)
CREATE TABLE IF NOT EXISTS dme_customers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT UNIQUE NOT NULL,       -- unique key for matching
  address TEXT,
  branch_id INT REFERENCES dme_branches(id),
  category TEXT,
  customer_type TEXT,
  salesman TEXT,
  last_purchase_date DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fast phone lookups
CREATE INDEX IF NOT EXISTS idx_dme_customers_phone ON dme_customers(phone);
CREATE INDEX IF NOT EXISTS idx_dme_customers_branch ON dme_customers(branch_id);

-- 6. Daily sales (header per customer per date)
CREATE TABLE IF NOT EXISTS dme_sales (
  id SERIAL PRIMARY KEY,
  date DATE NOT NULL,
  customer_id INT REFERENCES dme_customers(id),
  salesman TEXT,
  category TEXT,
  customer_type TEXT,
  total_quantity NUMERIC,
  uploaded_by UUID REFERENCES dme_users(id),
  uploaded_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(date, customer_id)
);

-- 7. Sale line items
CREATE TABLE IF NOT EXISTS dme_sale_items (
  id SERIAL PRIMARY KEY,
  sale_id INT REFERENCES dme_sales(id) ON DELETE CASCADE,
  product_name TEXT NOT NULL,
  quantity NUMERIC NOT NULL,
  unit TEXT
);

-- 8. Reminders (one active per customer, upserted on each purchase)
CREATE TABLE IF NOT EXISTS dme_reminders (
  id SERIAL PRIMARY KEY,
  customer_id INT REFERENCES dme_customers(id) ON DELETE CASCADE,
  reminder_date DATE NOT NULL,
  last_purchase_date DATE NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'dismissed')),
  assigned_to UUID REFERENCES dme_users(id),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(customer_id)
);

CREATE INDEX IF NOT EXISTS idx_dme_reminders_date ON dme_reminders(reminder_date);
CREATE INDEX IF NOT EXISTS idx_dme_reminders_status ON dme_reminders(status);

-- 9. Call logs
CREATE TABLE IF NOT EXISTS dme_call_logs (
  id SERIAL PRIMARY KEY,
  customer_id INT REFERENCES dme_customers(id) ON DELETE CASCADE,
  called_by UUID REFERENCES dme_users(id),
  call_date DATE NOT NULL,
  duration_seconds INT,
  remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- Row Level Security (RLS)
-- ============================================================

ALTER TABLE dme_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE dme_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE dme_user_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE dme_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE dme_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE dme_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE dme_sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE dme_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE dme_call_logs ENABLE ROW LEVEL SECURITY;

-- Allow all operations for authenticated users (app handles role checks)
CREATE POLICY "Allow all for authenticated" ON dme_users FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for authenticated" ON dme_branches FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for authenticated" ON dme_user_branches FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for authenticated" ON dme_products FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for authenticated" ON dme_customers FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for authenticated" ON dme_sales FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for authenticated" ON dme_sale_items FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for authenticated" ON dme_reminders FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for authenticated" ON dme_call_logs FOR ALL USING (true) WITH CHECK (true);
