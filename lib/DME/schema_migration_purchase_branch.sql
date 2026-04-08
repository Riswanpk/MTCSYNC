-- ════════════════════════════════════════════════════════════════════════════
-- MIGRATION: Add Purchase Branch Tracking
-- ════════════════════════════════════════════════════════════════════════════
-- Purpose: Track which branch purchased items for each customer
--          Decouple purchase branch from initial customer branch
--          Enable automatic reminder reassignment when purchase branch changes
--
-- Date: April 8, 2026
-- ════════════════════════════════════════════════════════════════════════════

-- 1. Create dme_customer_purchases table to track purchases by branch
--    This separates purchase information from customer master data
CREATE TABLE IF NOT EXISTS dme_customer_purchases (
  id SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES dme_customers(id) ON DELETE CASCADE,
  purchase_date DATE NOT NULL,
  purchase_for_branch_id INT NOT NULL REFERENCES dme_branches(id),
  purchase_for_branch_name TEXT,
  purchase_details JSONB, -- Stores: {salesman, category, customer_type, items_count, ...}
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(customer_id, purchase_date, purchase_for_branch_id)
);

CREATE INDEX IF NOT EXISTS idx_customer_purchases_customer_id 
  ON dme_customer_purchases(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_purchases_branch_id 
  ON dme_customer_purchases(purchase_for_branch_id);
CREATE INDEX IF NOT EXISTS idx_customer_purchases_date 
  ON dme_customer_purchases(purchase_date DESC);


-- 2. Add new columns to dme_reminders table for branch tracking
--    These track which branch the CURRENT active purchase is from
ALTER TABLE dme_reminders 
ADD COLUMN IF NOT EXISTS purchased_for_branch_id INT REFERENCES dme_branches(id),
ADD COLUMN IF NOT EXISTS purchased_for_branch_name TEXT;

-- Create index on branch for query filtering
CREATE INDEX IF NOT EXISTS idx_reminders_branch_id 
  ON dme_reminders(purchased_for_branch_id);


-- 3. Update dme_customers table comment to clarify branch_id is initial assignment
COMMENT ON COLUMN dme_customers.branch_id IS 
  'Initial branch where customer was created. Not updated when purchases come from different branches. See dme_customer_purchases for actual purchase branch.';

COMMENT ON COLUMN dme_reminders.purchased_for_branch_id IS 
  'Branch of the most recent purchase. Used to assign reminder to appropriate DME user.';

COMMENT ON TABLE dme_customer_purchases IS 
  'Tracks all purchases for a customer with their source branch. Enables cross-branch purchases and reminder reassignment.';


-- ════════════════════════════════════════════════════════════════════════════
-- SCENARIO EXAMPLE:
-- ════════════════════════════════════════════════════════════════════════════
-- 1. Customer created in BGR branch (dme_customers.branch_id = BGR_ID)
-- 2. Upload 8th Mar: Customer purchases from BGR → reminder created for BGRreminderDate = 8th Apr
-- 3. Upload 15th Mar: Same customer purchases from TSR → 
--    - New record in dme_customer_purchases (customer_id, 15th Mar, TSR_ID)
--    - Reminder updated: purchased_for_branch_id = TSR_ID, assigned_to = TSR_DME_USER
--    - reminderDate updated to 15th Apr (1 month from latest purchase)
-- 4. BGRs DME user no longer sees this reminder since assigned_to changed to TSR user
-- ════════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════════
-- ROLLBACK INSTRUCTIONS (if needed):
-- ════════════════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS dme_customer_purchases;
-- ALTER TABLE dme_reminders DROP COLUMN IF EXISTS purchased_for_branch_id;
-- ALTER TABLE dme_reminders DROP COLUMN IF EXISTS purchased_for_branch_name;
-- ════════════════════════════════════════════════════════════════════════════
