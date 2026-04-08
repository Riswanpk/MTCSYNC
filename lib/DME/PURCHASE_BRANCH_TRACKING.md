## Purchase Branch Tracking - Implementation Guide

### Overview
This update enables the DME system to track which branch a customer purchased from, allowing automatic reminder reassignment when purchases come from different branches.

### Problem Solved
Previously:
- Customer created in BGR branch
- Excel uploaded 8th Mar → reminder for 8th Apr in BGR user's queue  
- Excel uploaded 15th Mar from **TSR branch** for same customer → reminder stayed with BGR user

Now:
- Reminder automatically reassigns to TSR DME user
- Purchase branch tracked separately from initial customer branch
- Support for multi-branch customer purchases

### Database Schema Changes

#### 1. New Table: `dme_customer_purchases`
Stores all purchases with branch tracking. This separates purchase information from customer master data.

```sql
CREATE TABLE dme_customer_purchases (
  id SERIAL PRIMARY KEY,
  customer_id INT REFERENCES dme_customers(id),
  purchase_date DATE,
  purchase_for_branch_id INT REFERENCES dme_branches(id),
  purchase_for_branch_name TEXT,
  purchase_details JSONB, -- {salesman, category, customer_type, items_count}
  created_at TIMESTAMPTZ,
  UNIQUE(customer_id, purchase_date, purchase_for_branch_id)
);
```

**Indices:**
- `customer_id` - Quick lookup of all purchases for a customer
- `purchase_for_branch_id` - Filter purchases by branch
- `purchase_date` - Sort by purchase date

#### 2. Updated Table: `dme_reminders`
New columns to track current purchase branch:

```sql
ALTER TABLE dme_reminders ADD COLUMN purchased_for_branch_id INT;
ALTER TABLE dme_reminders ADD COLUMN purchased_for_branch_name TEXT;
```

### Code Changes

#### Supabase Service (`dme_supabase_service.dart`)

**New Methods:**
- `recordPurchaseWithBranch()` - Records purchase with branch info
- `getDmeUserForBranch(branchId)` - Finds DME user assigned to branch

**Updated Method:**
- `upsertReminder()` - Now accepts branch parameters and handles reassignment

#### Sales Upload (`dme_sales_upload.dart`)
Updated to pass branch information:
```dart
await _svc.upsertReminder(
  customerId: customerId,
  purchaseDate: record.date,
  purchaseForBranchId: branchId,        // ← NEW
  purchaseForBranchName: branchName,    // ← NEW
  assignedTo: dmeUser?.id,
  purchaseDetails: {...},               // ← NEW
);
```

#### Reminders Page (`dme_reminders_and_calls.dart`)
**Fix: Branch dropdown now shows only assigned branches**
- Before: Showed all branches
- Now: Filtered to user's assigned branches only
- Auto-selects single branch if user has only one

### Operation Flow

#### Scenario: Multi-Branch Purchase

**Step 1: Initial Upload (8th Mar, BGR)**
```
Customer: ABC Traders, Phone: 9876543210
Branch: BGR
Purchase Date: 8th Mar
↓
dme_customers created: branch_id = BGR_ID
dme_customer_purchases created: purchase_for_branch_id = BGR_ID
dme_reminders created: 
  - reminder_date = 8th Apr
  - purchased_for_branch_id = BGR_ID
  - assigned_to = BGR_DME_USER
```

**Step 2: Later Upload (15th Mar, TSR - Same Customer)**
```
Customer: ABC Traders (matched by phone)
Branch: TSR
Purchase Date: 15th Mar
↓
Check existing reminder:
  - Status: pending (not completed/dismissed)
  - Last purchase: 8th Mar
  - New purchase: 15th Mar (AFTER last purchase) ✓
↓
dme_customer_purchases created: purchase_for_branch_id = TSR_ID
dme_reminders UPDATED:
  - reminder_date = 15th Apr (1 month from new purchase)
  - purchased_for_branch_id = TSR_ID (CHANGED!)
  - assigned_to = TSR_DME_USER (REASSIGNED!)
  - last_purchase_date = 15th Mar
```

**Result:**
- Reminder removes from BGR user's queue
- Reminder appears in TSR user's queue
- Updated to 1 month from latest purchase date

#### Scenario: Completed Reminder + New Purchase

**Step 1: BGR user completed reminder on 10th Apr**
```
Reminder status: completed
```

**Step 2: New upload (20th Apr, TSR)**
```
Existing reminder: completed (old cycle)
↓
CREATE NEW REMINDER:
  - customer_id = same
  - reminder_date = 20th May
  - purchased_for_branch_id = TSR_ID
  - assigned_to = TSR_DME_USER
  - status = pending
```

**Result:**
- New reminder created (fresh cycle)
- Assigned to TSR user
- BGR user's completed reminder remains as historical record

### Real-World Benefits

1. **Workload Distribution**
   - Reminders automatically go to the right user
   - No manual reassignment needed

2. **Data Accuracy**
   - Purchase branch tracked independently
   - Can analyze cross-branch purchases
   - Revenue attribution clearer

3. **Audit Trail**
   - All purchases stored with branch info
   - Can trace reminder history
   - Know which branch handled final call

### Migration Instructions

1. **Run SQL migration:**
   ```bash
   # Execute schema_migration_purchase_branch.sql in Supabase console
   ```

2. **Verify tables created:**
   ```sql
   \d dme_customer_purchases
   \d dme_reminders
   ```

3. **Deploy code:**
   - Update to latest branch
   - Flutter clean
   - Flutter run

4. **Test flows:**
   - Upload sales from multiple branches
   - Verify reminder reassignment
   - Check branch dropdown shows only assigned branches

### Troubleshooting

**Issue: Branch dropdown showing all branches**
- Ensure `dme_users.branch_ids` is properly populated
- Verify branch assignment in Supabase

**Issue: Reminders not reassigning**
- Check `purchased_for_branch_id` column exists on dme_reminders
- Verify `getDmeUserForBranch()` finds correct user
- Check Firebase `users` collection has proper `branch` field

**Issue: getDmeUserForBranch returns null**
- Verify DME user has branch_ids array: `[branchId]`
- Confirm branch exists in dme_branches table

### Performance Notes

- `dme_customer_purchases` can grow large - has appropriate indices
- Queries filter by branch_id for performance
- Consider archiving old purchases after 1+ years

### Future Enhancements
- Purchase history report grouped by branch
- Cross-branch analysis dashboard  
- Automatic user availability balancing
- Branch-wise performance metrics

---

**Created:** April 8, 2026  
**Status:** Ready for Migration  
**Breaking Changes:** None (backward compatible)
