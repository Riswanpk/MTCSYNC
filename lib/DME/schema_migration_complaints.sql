-- ============================================================
-- DME Complaints Table Migration
-- Run this in Supabase SQL Editor to create complaints table
-- ============================================================

-- Create complaints table
CREATE TABLE IF NOT EXISTS dme_complaints (
  id SERIAL PRIMARY KEY,
  customer_id INT REFERENCES dme_customers(id) ON DELETE CASCADE,
  branch_id INT REFERENCES dme_branches(id),
  complaint_text TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('OPEN', 'CLOSED')) DEFAULT 'OPEN',
  created_by UUID REFERENCES dme_users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  closed_by UUID REFERENCES dme_users(id),
  closed_at TIMESTAMPTZ,
  UNIQUE(id)
);

-- Create indexes for faster querying
CREATE INDEX IF NOT EXISTS idx_dme_complaints_branch ON dme_complaints(branch_id);
CREATE INDEX IF NOT EXISTS idx_dme_complaints_status ON dme_complaints(status);
CREATE INDEX IF NOT EXISTS idx_dme_complaints_customer ON dme_complaints(customer_id);
CREATE INDEX IF NOT EXISTS idx_dme_complaints_created_at ON dme_complaints(created_at DESC);
