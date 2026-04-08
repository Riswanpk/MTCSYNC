-- ============================================================
-- DME Complaints Migration — Supabase PostgreSQL Schema
-- Run this in Supabase SQL Editor to create the complaints table
-- This is a separate migration file for the dme_complaints table
-- ============================================================

-- 1. DROP OLD TABLE (if migrating from previous schema)
DROP TABLE IF EXISTS dme_complaints CASCADE;

-- 2. CREATE COMPLAINTS TABLE
-- Stores complaint records raised by DME users
-- Has multiple FK to dme_users (created_by, resolved_by, closed_by)
-- These are explicitly named in PostgREST queries to avoid ambiguity
CREATE TABLE IF NOT EXISTS dme_complaints (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  branch_name TEXT NOT NULL,
  complaint_text TEXT NOT NULL,
  status TEXT DEFAULT 'raised' CHECK (status IN ('raised', 'case_resolved', 'verified_closed')),
  created_by UUID NOT NULL REFERENCES dme_users(id) ON DELETE CASCADE,
  resolved_by UUID REFERENCES dme_users(id) ON DELETE SET NULL,
  closed_by UUID REFERENCES dme_users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. CREATE INDEXES for better query performance
CREATE INDEX IF NOT EXISTS idx_dme_complaints_status ON dme_complaints(status);
CREATE INDEX IF NOT EXISTS idx_dme_complaints_created_by ON dme_complaints(created_by);
CREATE INDEX IF NOT EXISTS idx_dme_complaints_branch ON dme_complaints(branch_name);
CREATE INDEX IF NOT EXISTS idx_dme_complaints_created_at ON dme_complaints(created_at DESC);

-- 4. ENABLE ROW LEVEL SECURITY
ALTER TABLE dme_complaints ENABLE ROW LEVEL SECURITY;

-- 5. CREATE RLS POLICY
-- Allow all operations for authenticated users (app handles role-based access control)
DROP POLICY IF EXISTS "Allow all for authenticated" ON dme_complaints;
CREATE POLICY "Allow all for authenticated" ON dme_complaints FOR ALL USING (true) WITH CHECK (true);

-- ============================================================
-- NOTES FOR POST-MIGRATION DEPLOYMENT
-- ============================================================
-- Key Changes:
-- 1. Multiple FK to dme_users are now supported via explicit relationship naming
-- 2. Use explicit select syntax in PostgREST queries:
--    - created_by_user:dme_users!created_by(*)
--    - resolved_by_user:dme_users!resolved_by(*)
--    - closed_by_user:dme_users!closed_by(*)
-- 3. Status workflow: 'raised' → 'case_resolved' → 'verified_closed'
-- 4. old_by_key_* constraints removed to avoid PostgREST ambiguity
-- 5. All three FK relationships can coexist when explicitly named in queries
