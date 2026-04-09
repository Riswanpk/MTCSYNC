-- ============================================================
-- DME Complaints Migration — Supabase PostgreSQL Schema
-- Run this in Supabase SQL Editor to create the complaints table
-- This is a separate migration file for the dme_complaints table
-- ============================================================

-- 1. DROP OLD TABLE (if migrating from previous schema)
DROP TABLE IF EXISTS dme_complaints CASCADE;

-- 2. CREATE COMPLAINTS TABLE
-- Stores complaint records raised by DME users
-- FK references use TEXT for Firebase UIDs (not auth.users UUIDs)
CREATE TABLE dme_complaints (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  branch_id INTEGER NOT NULL REFERENCES dme_branches(id) ON DELETE CASCADE,
  complaint_text TEXT NOT NULL,
  status TEXT DEFAULT 'raised' CHECK (status IN ('raised', 'case_resolved', 'verified_closed')),
  created_by TEXT NOT NULL,
  assigned_to TEXT NOT NULL,
  resolved_by TEXT,
  closed_by TEXT,
  remarks TEXT,
  remarked_by TEXT,
  has_new_remarks BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  remarked_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. CREATE INDEXES for better query performance
CREATE INDEX IF NOT EXISTS idx_dme_complaints_status ON dme_complaints(status);
CREATE INDEX IF NOT EXISTS idx_dme_complaints_created_by ON dme_complaints(created_by);
CREATE INDEX IF NOT EXISTS idx_dme_complaints_assigned_to ON dme_complaints(assigned_to);
CREATE INDEX IF NOT EXISTS idx_dme_complaints_branch_id ON dme_complaints(branch_id);
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
-- 1. User ID fields (created_by, assigned_to, resolved_by, closed_by, remarked_by) store Firebase UIDs as TEXT
--    (NOT auth.users UUID - these are separate)
-- 2. assigned_to is MANDATORY (NOT NULL) - every complaint must be assigned
-- 3. branch_id references dme_branches(id) 
-- 4. has_new_remarks and remarks fields for tracking feedback
-- 5. remarked_by and remarked_at track who made remarks and when
-- 6. Status workflow: 'raised' → 'case_resolved' → 'verified_closed'
-- 7. All user fields use TEXT type to store Firebase UIDs (base64 encoded strings)
-- 8. assigned_to is mandatory to ensure complaints are always assigned
-- 9. The DROP TABLE IF EXISTS CASCADE at the start ensures clean state
-- 
-- Firebase UID Format: Base64 encoded strings like "KSB3CEH9wzcHVYIuYHbkg31ciMM2"
-- This is different from Supabase auth.users.id which are standard UUIDs
