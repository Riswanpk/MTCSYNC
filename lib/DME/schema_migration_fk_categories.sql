-- ════════════════════════════════════════════════════════════════════════════
-- MIGRATION: Add Foreign Keys for Customer Category and Type
-- ════════════════════════════════════════════════════════════════════════════
-- Purpose: Create proper referential integrity between lookup tables and customers
-- Status: Fixes data normalization and integrity issues
-- Date: April 8, 2026
-- ════════════════════════════════════════════════════════════════════════════

-- STEP 1: Add new columns with integer foreign keys to existing dme_customers table
ALTER TABLE dme_customers 
ADD COLUMN category_id INT REFERENCES dme_categories(id),
ADD COLUMN customer_type_id INT REFERENCES dme_customer_types(id);

-- STEP 2: Populate new columns from existing text values (data migration)
-- This maps existing category TEXT values to their IDs
UPDATE dme_customers 
SET category_id = dme_categories.id
FROM dme_categories
WHERE dme_customers.category = dme_categories.name
  AND dme_customers.category IS NOT NULL;

-- This maps existing customer_type TEXT values to their IDs
UPDATE dme_customers 
SET customer_type_id = dme_customer_types.id
FROM dme_customer_types
WHERE dme_customers.customer_type = dme_customer_types.name
  AND dme_customers.customer_type IS NOT NULL;

-- STEP 3: Drop old TEXT columns (after verifying data migration)
-- ⚠️  IMPORTANT: Only run this AFTER confirming all data migrated correctly
-- Verify: SELECT * FROM dme_customers WHERE category_id IS NULL AND category IS NOT NULL;
-- If the above returns rows, it means some categories couldn't be matched
-- ALTER TABLE dme_customers DROP COLUMN category;
-- ALTER TABLE dme_customers DROP COLUMN customer_type;

-- STEP 4: Create indices for performance
CREATE INDEX IF NOT EXISTS idx_dme_customers_category_id ON dme_customers(category_id);
CREATE INDEX IF NOT EXISTS idx_dme_customers_type_id ON dme_customers(customer_type_id);

-- STEP 5: Update dme_sales table similarly (same structure)
ALTER TABLE dme_sales 
ADD COLUMN category_id INT REFERENCES dme_categories(id),
ADD COLUMN customer_type_id INT REFERENCES dme_customer_types(id);

-- Migrate existing data in dme_sales
UPDATE dme_sales 
SET category_id = dme_categories.id
FROM dme_categories
WHERE dme_sales.category = dme_categories.name
  AND dme_sales.category IS NOT NULL;

UPDATE dme_sales 
SET customer_type_id = dme_customer_types.id
FROM dme_customer_types
WHERE dme_sales.customer_type = dme_customer_types.name
  AND dme_sales.customer_type IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_dme_sales_category_id ON dme_sales(category_id);
CREATE INDEX IF NOT EXISTS idx_dme_sales_type_id ON dme_sales(customer_type_id);

-- ════════════════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (Run BEFORE dropping old columns)
-- ════════════════════════════════════════════════════════════════════════════

-- Check for unmapped categories
SELECT COUNT(*) as unmapped_categories
FROM dme_customers 
WHERE category IS NOT NULL AND category_id IS NULL;

-- Check for unmapped types
SELECT COUNT(*) as unmapped_types
FROM dme_customers 
WHERE customer_type IS NOT NULL AND customer_type_id IS NULL;

-- View distribution of categories
SELECT dc.name as category, COUNT(c.id) as customer_count
FROM dme_customers c
LEFT JOIN dme_categories dc ON c.category_id = dc.id
GROUP BY dc.name
ORDER BY customer_count DESC;

-- View distribution of types
SELECT dct.name as type, COUNT(c.id) as customer_count
FROM dme_customers c
LEFT JOIN dme_customer_types dct ON c.customer_type_id = dct.id
GROUP BY dct.name
ORDER BY customer_count DESC;

-- ════════════════════════════════════════════════════════════════════════════
-- FINAL CLEANUP (Run ONLY after verifying data migration)
-- ════════════════════════════════════════════════════════════════════════════

-- Once you confirm no unmapped records:
-- ALTER TABLE dme_customers DROP COLUMN category;
-- ALTER TABLE dme_customers DROP COLUMN customer_type;
-- ALTER TABLE dme_sales DROP COLUMN category;
-- ALTER TABLE dme_sales DROP COLUMN customer_type;

-- ════════════════════════════════════════════════════════════════════════════
-- ROLLBACK (if something goes wrong)
-- ════════════════════════════════════════════════════════════════════════════

-- DROP INDEX IF EXISTS idx_dme_customers_category_id;
-- DROP INDEX IF EXISTS idx_dme_customers_type_id;
-- ALTER TABLE dme_customers DROP COLUMN IF EXISTS category_id;
-- ALTER TABLE dme_customers DROP COLUMN IF EXISTS customer_type_id;
-- ALTER TABLE dme_sales DROP COLUMN IF EXISTS category_id;
-- ALTER TABLE dme_sales DROP COLUMN IF EXISTS customer_type_id;
