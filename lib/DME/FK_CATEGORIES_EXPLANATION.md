## Why Customer Category & Type Need Foreign Keys

### Current Problem

**Current Schema:**
```sql
-- Lookup tables (master data)
dme_categories (id, name)
dme_customer_types (id, name)

-- Customer table stores TEXT values directly
dme_customers (
  ...
  category TEXT,            ← Not linked to dme_categories!
  customer_type TEXT,       ← Not linked to dme_customer_types!
)
```

### Why This Is a Problem

#### 1. **No Referential Integrity**
```sql
-- Currently you CAN do this:
INSERT INTO dme_customers (name, phone, category, customer_type)
VALUES ('ABC Traders', '9876543210', 'Invalid Category', 'Invalid Type');

-- Database doesn't validate if these values exist in lookup tables
-- Result: Garbage data with no way to trace it
```

#### 2. **Data Duplication & Wasted Storage**
```sql
-- If you have 50,000 customers with category='Event'
-- TEXT 'Event' is stored 50,000 times (50KB+ wasted)

-- With foreign key:
-- ID 1 stored 50,000 times (200KB saved!)
```

#### 3. **Consistency Problems**
```sql
-- Different ways to enter same category:
'Event'
'event'
'EVENT'
'Event '  (with space)
' EVENT'  (leading space)

-- Query becomes unreliable:
WHERE category = 'Event'  ← Misses 'EVENT', 'event', etc.
```

#### 4. **Data Migration Nightmare**
```sql
-- Want to rename category from "Hotel" to "Hotel & Resort"?

-- Without FK (current):
UPDATE dme_customers SET category = 'Hotel & Resort' 
WHERE category = 'Hotel';  -- 10,000+ rows updated

-- With FK (proposed):
UPDATE dme_categories SET name = 'Hotel & Resort' 
WHERE id = 5;  -- 1 row updated, 10,000 customers auto-reflect change
```

#### 5. **Query Performance**
```sql
-- Current (text matching):
SELECT c.* FROM dme_customers c
WHERE c.category = 'Event'  -- Full text scan

-- Proposed (integer matching):
SELECT c.* FROM dme_customers c
WHERE c.category_id = 1  -- Index lookup (10-100x faster)
```

#### 6. **Bad Analytics**
```sql
-- Current: Category names could be slightly different
SELECT category, COUNT(*) FROM dme_customers GROUP BY category;
-- Result: Event (15203), EVENT (1), event (2), Event (18)  ← 4 different entries!

-- Proposed: Only valid categories
SELECT c.name, COUNT(*) FROM dme_customers cu
JOIN dme_categories c ON cu.category_id = c.id
GROUP BY c.id, c.name;
-- Result: Event (15224)  ← Correct total
```

---

## Solution: Foreign Key Relationships

### Proposed Schema

```sql
-- Lookup tables (unchanged)
CREATE TABLE dme_categories (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL
);

CREATE TABLE dme_customer_types (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL
);

-- Customer table with proper foreign keys
CREATE TABLE dme_customers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT UNIQUE NOT NULL,
  address TEXT,
  branch_id INT REFERENCES dme_branches(id),
  
  -- ✅ NEW: Foreign keys to lookup tables
  category_id INT REFERENCES dme_categories(id),
  customer_type_id INT REFERENCES dme_customer_types(id),
  
  -- ❌ OLD: Still kept for backward compatibility during migration
  category TEXT,
  customer_type TEXT,
  
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_customers_category_id ON dme_customers(category_id);
CREATE INDEX idx_customers_type_id ON dme_customers(customer_type_id);
```

### Benefits

| Aspect | Before (Text) | After (FK) |
|--------|---------------|-----------|
| **Data Integrity** | ❌ Any text allowed | ✅ Only valid IDs |
| **Storage** | ❌ Duplicated text | ✅ Single integer |
| **Query Speed** | ❌ Text scan (slow) | ✅ Integer index (fast) |
| **Updates** | ❌ Bulk updates | ✅ Single master row |
| **Analytics** | ❌ Inconsistent grouping | ✅ Accurate totals |
| **Validation** | ❌ App-level only | ✅ Database enforced |

---

## Migration Path

### Phase 1: Add New Columns (Safe)
```sql
ALTER TABLE dme_customers 
ADD COLUMN category_id INT REFERENCES dme_categories(id),
ADD COLUMN customer_type_id INT REFERENCES dme_customer_types(id);

-- Code can now write to BOTH old (TEXT) and new (FK) columns
```

### Phase 2: Populate New Columns
```sql
UPDATE dme_customers c
SET category_id = cat.id
FROM dme_categories cat
WHERE c.category = cat.name;
```

### Phase 3: Update Code
```dart
// Before
await db.update('dme_customers', {
  'category': categoryName,
});

// After
await db.update('dme_customers', {
  'category_id': categoryId,  // Use ID
});
```

### Phase 4: Verify & Cleanup
```sql
-- Verify ALL records migrated
SELECT COUNT(*) FROM dme_customers 
WHERE category IS NOT NULL AND category_id IS NULL;
-- Should return: 0

-- Then drop old columns
ALTER TABLE dme_customers DROP COLUMN category;
ALTER TABLE dme_customers DROP COLUMN customer_type;
```

---

## Impact on Code

### Dart Code Changes

**Before (Text storage):**
```dart
// Storing text
await _db.from('dme_customers').update({
  'category': 'Event',
  'customer_type': 'PREMIUM CUSTOMER',
});

// Querying
final results = await _db
  .from('dme_customers')
  .select()
  .eq('category', 'Event');
```

**After (Foreign key):**
```dart
// Storing ID
await _db.from('dme_customers').update({
  'category_id': 1,  // ID from dme_categories
  'customer_type_id': 3,  // ID from dme_customer_types
});

// Querying with join (get category name)
final results = await _db
  .from('dme_customers')
  .select('*, dme_categories(name), dme_customer_types(name)')
  .eq('category_id', 1);
```

---

## Real-World Example: Cross-Branch Purchase

**Scenario:**
- Customer "ABC Traders" from BGR branch
- Purchases from TSR branch (different category)
- Want to track both

**Without proper FK:**
```
dme_customers:
  id=123, name='ABC Traders', category='Event' (no way to distinguish branches)

dme_customer_purchases:
  customer_id=123, purchase_from_branch=TSR, category='Catering' (text duplication)
```

**With proper FK:**
```
dme_categories: id=1:'Event', id=5:'Catering'

dme_customers:
  id=123, name='ABC Traders', category_id=1 (Category tracked)

dme_customer_purchases:
  customer_id=123, branch_id=TSR, category_id=5 (Linked properly)
```

---

## Timeline

- **Immediate**: Run migration to add FK columns (backward compatible)
- **Week 1**: Update all code to use new FK columns
- **Week 2**: Verify all data migrated correctly
- **Week 3**: Remove old TEXT columns after code fully transitioned

---

## Migration SQL

See: `schema_migration_fk_categories.sql`

**Key Steps:**
1. ✅ Add new INT FK columns
2. ✅ Migrate existing data
3. ✅ Create indices
4. ✅ Verify mapping (CHECK for NULL)
5. ✅ Drop old TEXT columns

---

## Why It Wasn't Done Initially

The schema was likely optimized for **quick initial development** rather than **long-term data quality**:
- Text columns are simpler to write initially
- No need to manage ID mappings
- Works fine for small datasets

But at 50,000+ customers and cross-branch operations, **proper normalization is critical** for:
- Data accuracy
- Query performance  
- Maintenance ease
- Analytics reliability

---

## Next Steps

1. **Review** this migration plan
2. **Backup** production database
3. **Run** migration in staging
4. **Test** queries and code changes
5. **Deploy** updated code
6. **Verify** data integrity
7. **Cleanup** old TEXT columns

**Status:** Ready to implement  
**Breaking Changes:** None (backward compatible during transition)
