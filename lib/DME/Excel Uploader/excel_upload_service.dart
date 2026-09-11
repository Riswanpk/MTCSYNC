import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'excel_uploader_models.dart';

class ExcelUploadService {
  /// Check if the exact Excel file has already been uploaded by its SHA-256 hash
  static Future<Map<String, dynamic>?> checkDuplicateFile({
    required SupabaseClient client,
    required String fileHash,
  }) async {
    try {
      final res = await client
          .from('dme_excel_uploads')
          .select('id, file_name, file_hash, uploaded_by, uploaded_at, sales_count, rows_count')
          .eq('file_hash', fileHash)
          .maybeSingle();
      if (res != null) {
        debugPrint('Duplicate file detected in dme_excel_uploads with hash: $fileHash');
      }
      return res != null ? Map<String, dynamic>.from(res) : null;
    } catch (e) {
      debugPrint('Error/Notice checking duplicate file upload in dme_excel_uploads: $e');
      return null;
    }
  }

  /// Records an uploaded file metadata and hash to prevent duplicate uploads in future
  static Future<void> recordUpload({
    required SupabaseClient client,
    required String fileName,
    required String fileHash,
    required String uploadedBy,
    required int salesCount,
    required int rowsCount,
  }) async {
    try {
      debugPrint('Recording upload into dme_excel_uploads: $fileName (hash: $fileHash)');
      await client.from('dme_excel_uploads').insert({
        'file_name': fileName,
        'file_hash': fileHash,
        'uploaded_by': uploadedBy,
        'uploaded_at': DateTime.now().toIso8601String(),
        'sales_count': salesCount,
        'rows_count': rowsCount,
      });
      debugPrint('✓ Recorded upload $fileName in dme_excel_uploads successfully');
    } catch (e) {
      debugPrint('Error recording file upload hash in dme_excel_uploads: $e');
      rethrow;
    }
  }

  /// Uploads all processed data to Supabase in fast batch operations
  static Future<int> uploadSales({
    required SupabaseClient client,
    required List<GroupedSale> groupedSales,
    required List<CustomerConflict> conflicts,
    String? fileName,
    String? fileHash,
    int? rowsCount,
    required Function(double progress, String status) onProgress,
    required Function(String log) onLog,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uploadedBy = currentUser?.email ?? currentUser?.uid ?? 'manual_upload';

    onLog('Starting fast batch upload for ${groupedSales.length} sale(s)...');

    // 1. Prepare unique customer records
    final Map<String, Map<String, dynamic>> customersToUpsert = {};
    final Map<String, String> activePhoneBySale = {};

    for (var sale in groupedSales) {
      String activePhone = sale.phone;

      final conflict = conflicts
          .where((c) => c.originalPhone == sale.phone && (c.newName == sale.party || c.existingName == sale.party))
          .firstOrNull;

      if (conflict != null && conflict.userChoice == ConflictResolution.assignNewPhone && conflict.newName == sale.party) {
        activePhone = conflict.customNewPhone.isNotEmpty ? conflict.customNewPhone : '${sale.phone}_alt';
      }

      activePhoneBySale['${sale.party}_${sale.phone}_${sale.date.millisecondsSinceEpoch}'] = activePhone;

      if (activePhone.isNotEmpty) {
        customersToUpsert[activePhone] = {
          'name': sale.party.isNotEmpty ? sale.party : 'Unnamed Customer',
          'phone': activePhone,
          'address': sale.address.isNotEmpty ? sale.address : null,
          'salesman': sale.salesman.isNotEmpty ? sale.salesman : null,
          'last_purchase_date': DateFormat('yyyy-MM-dd').format(sale.date),
          'updated_at': DateTime.now().toIso8601String(),
        };
      }
    }

    onProgress(0.3, 'Syncing ${customersToUpsert.length} customer(s)...');

    // Determine which customers already exist in dme_customers and check their primary_branch
    final activePhones = customersToUpsert.keys.toList();
    final Map<String, int?> existingCustomerPrimaryBranches = {};
    for (int i = 0; i < activePhones.length; i += 500) {
      final chunk = activePhones.sublist(
        i,
        (i + 500 > activePhones.length) ? activePhones.length : i + 500,
      );
      try {
        final existingRows = await client
            .from('dme_customers')
            .select('phone, primary_branch')
            .inFilter('phone', chunk);
        for (var row in (existingRows as List)) {
          final p = row['phone']?.toString();
          if (p != null) {
            existingCustomerPrimaryBranches[p] = row['primary_branch'] as int?;
          }
        }
      } catch (e) {
        debugPrint('Notice checking existing customers for primary branch: $e');
      }
    }

    // Determine the earliest purchase branch for each customer in this batch
    final Map<String, Map<String, dynamic>> earliestSaleByPhone = {};
    for (var sale in groupedSales) {
      final activePhone = activePhoneBySale['${sale.party}_${sale.phone}_${sale.date.millisecondsSinceEpoch}'] ?? sale.phone;
      if (activePhone.isEmpty || sale.branchId == null) continue;

      final current = earliestSaleByPhone[activePhone];
      if (current == null) {
        earliestSaleByPhone[activePhone] = {
          'date': sale.date,
          'branchId': sale.branchId,
        };
      } else {
        final currentDate = current['date'] as DateTime;
        if (sale.date.isBefore(currentDate)) {
          earliestSaleByPhone[activePhone] = {
            'date': sale.date,
            'branchId': sale.branchId,
          };
        }
      }
    }

    // Assign primary_branch:
    // 1. For newly registered customers (not in existingCustomerPrimaryBranches)
    // 2. For existing customers who currently have primary_branch == null
    // If an existing customer already has a primary_branch, DO NOT overwrite it.
    for (var entry in customersToUpsert.entries) {
      final phone = entry.key;
      final isExisting = existingCustomerPrimaryBranches.containsKey(phone);
      final existingPrimary = existingCustomerPrimaryBranches[phone];

      if (!isExisting || existingPrimary == null) {
        final earliest = earliestSaleByPhone[phone];
        if (earliest != null && earliest['branchId'] != null) {
          entry.value['primary_branch'] = earliest['branchId'];
        }
      } else {
        // Retain existing primary branch during upsert
        entry.value['primary_branch'] = existingPrimary;
      }
    }

    // Upsert customers in bulk
    dynamic upsertedCustRes;
    try {
      upsertedCustRes = await client
          .from('dme_customers')
          .upsert(
            customersToUpsert.values.toList(),
            onConflict: 'phone',
          )
          .select('id, phone');
    } catch (upsertErr) {
      // If primary_branch column has not been added to DB yet, fallback without it
      debugPrint('Customers upsert with primary_branch failed: $upsertErr. Falling back without primary_branch.');
      for (var map in customersToUpsert.values) {
        map.remove('primary_branch');
      }
      upsertedCustRes = await client
          .from('dme_customers')
          .upsert(
            customersToUpsert.values.toList(),
            onConflict: 'phone',
          )
          .select('id, phone');
    }

    final Map<String, int> phoneToCustomerId = {};
    for (var row in (upsertedCustRes as List)) {
      final ph = row['phone']?.toString();
      final id = row['id'] as int?;
      if (ph != null && id != null) {
        phoneToCustomerId[ph] = id;
      }
    }

    onLog('✓ Synchronized ${phoneToCustomerId.length} customer records in Supabase');

    onProgress(0.5, 'Inserting sales...');

    // 2. Fetch any existing sales in the database for these customers to obtain their IDs
    final List<int> customerIds = phoneToCustomerId.values.toSet().toList();
    final Map<String, int> existingSaleIdsByKey = {}; // '${custId}_$dateStr' -> id

    if (customerIds.isNotEmpty) {
      try {
        for (int i = 0; i < customerIds.length; i += 500) {
          final chunk = customerIds.sublist(
            i,
            (i + 500 > customerIds.length) ? customerIds.length : i + 500,
          );
          final existingSales = await client
              .from('dme_sales')
              .select('id, date, customer_id')
              .inFilter('customer_id', chunk);

          for (var row in (existingSales as List)) {
            final cId = row['customer_id']?.toString();
            final dt = row['date']?.toString();
            final id = row['id'] as int?;
            if (cId != null && dt != null && id != null) {
              existingSaleIdsByKey['${cId}_$dt'] = id;
            }
          }
        }
      } catch (e) {
        debugPrint('Notice pre-fetching existing sales: $e');
      }
    }

    // Prepare sales strictly deduplicated by (customer_id, date) to satisfy uq_sale_date_customer
    final List<Map<String, dynamic>> salesToInsert = [];
    final Map<String, int> saleGroupToIdx = {};

    for (int i = 0; i < groupedSales.length; i++) {
      final sale = groupedSales[i];
      final activePhone = activePhoneBySale['${sale.party}_${sale.phone}_${sale.date.millisecondsSinceEpoch}'] ?? sale.phone;
      final custId = phoneToCustomerId[activePhone];
      if (custId == null) continue;

      final dateStr = DateFormat('yyyy-MM-dd').format(sale.date);
      final saleKey = '${custId}_$dateStr';

      if (!saleGroupToIdx.containsKey(saleKey)) {
        saleGroupToIdx[saleKey] = salesToInsert.length;
        final salePayload = <String, dynamic>{
          'date': dateStr,
          'customer_id': custId,
          'purchased_branch': sale.branchId,
          'salesman': sale.salesman.isNotEmpty ? sale.salesman : null,
          'category_id': sale.categoryId,
          'customer_type_id': sale.typeId,
          'uploaded_by': uploadedBy,
        };

        salesToInsert.add(salePayload);
      } else {
        // If multiple invoices exist on the same date for this customer, update branch if previously null
        final existingIdx = saleGroupToIdx[saleKey]!;
        if (salesToInsert[existingIdx]['purchased_branch'] == null && sale.branchId != null) {
          salesToInsert[existingIdx]['purchased_branch'] = sale.branchId;
        }
      }
    }

    final Map<String, int> saleKeyToSaleId = Map.from(existingSaleIdsByKey);
    final List insertedSalesList = [];

    if (salesToInsert.isNotEmpty) {
      dynamic insertedSalesRes;
      try {
        insertedSalesRes = await client
            .from('dme_sales')
            .upsert(
              salesToInsert,
              onConflict: 'customer_id,date',
            )
            .select('id, date, customer_id, purchased_branch');
      } catch (upsertErr) {
        debugPrint('Upsert onConflict customer_id,date failed: $upsertErr, attempting onConflict date,customer_id');
        try {
          insertedSalesRes = await client
              .from('dme_sales')
              .upsert(
                salesToInsert,
                onConflict: 'date,customer_id',
              )
              .select('id, date, customer_id, purchased_branch');
        } catch (cErr2) {
          debugPrint('Upsert onConflict date,customer_id failed: $cErr2, attempting standard insert');
          insertedSalesRes = await client
              .from('dme_sales')
              .insert(salesToInsert)
              .select('id, date, customer_id, purchased_branch');
        }
      }

      if (insertedSalesRes is List) {
        for (var row in insertedSalesRes) {
          final id = row['id'] as int?;
          final dt = row['date']?.toString();
          final cId = row['customer_id']?.toString();
          final bId = row['purchased_branch']?.toString();
          if (id != null && dt != null && cId != null) {
            saleKeyToSaleId['${cId}_${dt}_$bId'] = id;
            saleKeyToSaleId['${cId}_$dt'] = id;
            insertedSalesList.add(row);
          }
        }
      }

      // Query database to ensure 100% of sales have their generated/updated IDs in saleKeyToSaleId
      if (customerIds.isNotEmpty) {
        try {
          for (int i = 0; i < customerIds.length; i += 500) {
            final chunk = customerIds.sublist(
              i,
              (i + 500 > customerIds.length) ? customerIds.length : i + 500,
            );
            final fetched = await client
                .from('dme_sales')
                .select('id, date, customer_id, purchased_branch')
                .inFilter('customer_id', chunk);

            for (var row in (fetched as List)) {
              final id = row['id'] as int?;
              final dt = row['date']?.toString();
              final cId = row['customer_id']?.toString();
              final bId = row['purchased_branch']?.toString();
              if (id != null && dt != null && cId != null) {
                saleKeyToSaleId['${cId}_${dt}_$bId'] = id;
                saleKeyToSaleId['${cId}_$dt'] = id;
              }
            }
          }
        } catch (e) {
          debugPrint('Notice post-fetching sale IDs: $e');
        }
      }
    }

    onLog('✓ Synchronized ${saleKeyToSaleId.length} sales records in database');

    onProgress(0.7, 'Saving sale details, reminders, and branches...');

    // 3. Prepare Batch Sale Details, Reminders (deduplicated by customer_id), and Customer Branches (deduplicated by customer_id + branch_id)
    final List<Map<String, dynamic>> detailsToInsert = [];
    final Map<int, Map<String, dynamic>> remindersByCustomer = {};
    final Map<String, Map<String, dynamic>> branchesByCustBranch = {};

    for (int i = 0; i < groupedSales.length; i++) {
      final sale = groupedSales[i];
      final activePhone = activePhoneBySale['${sale.party}_${sale.phone}_${sale.date.millisecondsSinceEpoch}'] ?? sale.phone;
      final custId = phoneToCustomerId[activePhone];
      final dateStr = DateFormat('yyyy-MM-dd').format(sale.date);
      final saleKeyWithBranch = '${custId}_${dateStr}_${sale.branchId}';
      final saleKeyWithoutBranch = '${custId}_$dateStr';
      final saleId = saleKeyToSaleId[saleKeyWithBranch] ?? saleKeyToSaleId[saleKeyWithoutBranch];

      if (saleId != null && sale.products.isNotEmpty) {
        detailsToInsert.add({
          'sale_id': saleId,
          'products': sale.products,
        });
      }

      if (custId != null) {
        // Check if this sale's category is excluded from reminders
        // Excluded: AUDITORIUM (6), TRUST (7), INSTITUTION (8), VEHICLE SHOWROOM (11), GENERAL & OTHERS (13)
        final catId = sale.categoryId;
        final catName = sale.categoryName.toUpperCase().trim();
        final typeName = sale.typeName.toUpperCase().trim();
        final isExcludedCategory = catId == 6 ||
            catId == 7 ||
            catId == 8 ||
            catId == 11 ||
            catId == 13 ||
            catName.contains('AUDITORIUM') ||
            catName.contains('VEHICLE SHOWROOM') ||
            catName.contains('VEHICE SHOWROOM') ||
            catName.contains('TRUST') ||
            catName.contains('INSTITUTION') ||
            catName.contains('GENERAL') ||
            typeName.contains('AUDITORIUM') ||
            typeName.contains('VEHICLE SHOWROOM') ||
            typeName.contains('VEHICE SHOWROOM');

        // If this branch/sale is an eligible category, set/update reminder specifically for this branch
        if (!isExcludedCategory) {
          final reminderDate = sale.date.add(const Duration(days: 28));
          final existingReminderForCust = remindersByCustomer[custId];

          // If customer has no reminder yet, or if this eligible sale is newer than any previously considered sale
          if (existingReminderForCust == null) {
            remindersByCustomer[custId] = {
              'customer_id': custId,
              'reminder_date': DateFormat('yyyy-MM-dd').format(reminderDate),
              'last_purchase_date': DateFormat('yyyy-MM-dd').format(sale.date),
              'last_purchase_branch': sale.branchId,
              'status': 'pending', // Fresh/reset reminder date for new purchase
              'updated_at': DateTime.now().toIso8601String(),
            };
          } else {
            // Update with the latest eligible branch sale date
            final prevDateStr = existingReminderForCust['last_purchase_date']?.toString();
            final prevDate = prevDateStr != null ? DateTime.tryParse(prevDateStr) : null;
            if (prevDate == null || sale.date.isAfter(prevDate)) {
              remindersByCustomer[custId] = {
                'customer_id': custId,
                'reminder_date': DateFormat('yyyy-MM-dd').format(reminderDate),
                'last_purchase_date': DateFormat('yyyy-MM-dd').format(sale.date),
                'last_purchase_branch': sale.branchId,
                'status': 'pending',
                'updated_at': DateTime.now().toIso8601String(),
              };
            }
          }
        }

        // Branch junction (recorded for all branches)
        if (sale.branchId != null) {
          final branchKey = '${custId}_${sale.branchId}';
          branchesByCustBranch[branchKey] = {
            'customer_id': custId,
            'branch_id': sale.branchId,
            'category_id': sale.categoryId,
            'customer_type_id': sale.typeId,
          };
        }
      }
    }

    final List<Map<String, dynamic>> remindersToInsert = [];
    final List<Map<String, dynamic>> remindersToUpdate = [];

    // Check existing reminders in database to ensure we advance due dates for existing customers
    final List<int> customerIdsWithNewReminders = remindersByCustomer.keys.toList();
    if (customerIdsWithNewReminders.isNotEmpty) {
      final Map<int, List<Map<String, dynamic>>> existingRemindersByCustomer = {};
      try {
        // Fetch existing database reminders in chunks of 500
        for (int i = 0; i < customerIdsWithNewReminders.length; i += 500) {
          final chunk = customerIdsWithNewReminders.sublist(
            i,
            (i + 500 > customerIdsWithNewReminders.length) ? customerIdsWithNewReminders.length : i + 500,
          );
          final existingDbReminders = await client
              .from('dme_reminders')
              .select('id, customer_id, last_purchase_date, reminder_date, status')
              .inFilter('customer_id', chunk);

          for (var dbRow in (existingDbReminders as List)) {
            final cId = dbRow['customer_id'] as int?;
            if (cId != null) {
              existingRemindersByCustomer.putIfAbsent(cId, () => []).add(Map<String, dynamic>.from(dbRow));
            }
          }
        }
      } catch (checkErr) {
        debugPrint('Notice checking existing reminders: $checkErr');
      }

      for (var entry in remindersByCustomer.entries) {
        final cId = entry.key;
        final newObj = entry.value;
        final existingList = existingRemindersByCustomer[cId] ?? [];

        // Check if there is an active pending reminder that hasn't been called yet
        final pendingList = existingList.where((r) {
          final st = (r['status'] ?? '').toString().toLowerCase();
          return st == 'pending';
        }).toList();

        if (pendingList.isNotEmpty) {
          // An active pending reminder exists: update it if new invoice is newer
          final activePending = pendingList.first;
          final dbLastPurchaseStr = activePending['last_purchase_date']?.toString();
          final dbLastPurchase = dbLastPurchaseStr != null ? DateTime.tryParse(dbLastPurchaseStr) : null;

          final newLastPurchaseStr = newObj['last_purchase_date']?.toString();
          final newLastPurchase = newLastPurchaseStr != null ? DateTime.tryParse(newLastPurchaseStr) : null;

          if (dbLastPurchase != null && newLastPurchase != null && dbLastPurchase.isAfter(newLastPurchase)) {
            // DB invoice is newer, preserve existing reminder date
            remindersToUpdate.add({
              'id': activePending['id'],
              'customer_id': cId,
              'reminder_date': activePending['reminder_date'],
              'last_purchase_date': activePending['last_purchase_date'],
              'last_purchase_branch': newObj['last_purchase_branch'],
              'status': 'pending',
              'updated_at': DateTime.now().toIso8601String(),
            });
          } else {
            // Excel invoice is newer: update existing pending reminder with new dates
            remindersToUpdate.add({
              'id': activePending['id'],
              'customer_id': cId,
              'reminder_date': newObj['reminder_date'],
              'last_purchase_date': newObj['last_purchase_date'],
              'last_purchase_branch': newObj['last_purchase_branch'],
              'status': 'pending',
              'updated_at': DateTime.now().toIso8601String(),
            });
          }
        } else {
          // No pending reminder exists! (Customer is new, or previous reminders are completed/called)
          // Preserves old completed reminders as history, and inserts a brand new reminder!
          remindersToInsert.add(newObj);
        }
      }
    } else {
      // Empty remindersByCustomer
    }

    final customerBranchesToInsert = branchesByCustBranch.values.toList();

    // Execute batch operations concurrently for maximum speed
    final List<Future<dynamic>> parallelTasks = [];
    if (detailsToInsert.isNotEmpty) {
      parallelTasks.add(() async {
        try {
          await client.from('dme_sales_detail').insert(detailsToInsert);
        } catch (insertErr) {
          // Re-upload scenario: details may already exist; log and continue
          debugPrint('Sale details insert failed (possible re-upload): $insertErr');
          onLog('⚠ Sale details: some may already exist (re-upload detected)');
        }
      }());
    }
    if (remindersToUpdate.isNotEmpty) {
      parallelTasks.add(() async {
        try {
          await client.from('dme_reminders').upsert(remindersToUpdate, onConflict: 'id');
        } catch (updateErr) {
          debugPrint('Reminders update error: $updateErr');
          onLog('⚠ Reminders update error: $updateErr');
        }
      }());
    }
    if (remindersToInsert.isNotEmpty) {
      parallelTasks.add(() async {
        try {
          await client.from('dme_reminders').insert(remindersToInsert);
        } catch (insertErr) {
          debugPrint('Reminders insert notice: $insertErr');
          // If unique constraint on customer_id still exists in Supabase, fallback to upsert on customer_id
          try {
            await client.from('dme_reminders').upsert(remindersToInsert, onConflict: 'customer_id');
            onLog('⚠ Note: Reminder updated (To preserve history, drop customer_id unique constraint in Supabase)');
          } catch (fallbackErr) {
            onLog('⚠ Reminders insert error: $fallbackErr');
          }
        }
      }());
    }
    if (customerBranchesToInsert.isNotEmpty) {
      parallelTasks.add(() async {
        try {
          await client
              .from('dme_customer_branches')
              .upsert(customerBranchesToInsert, onConflict: 'customer_id,branch_id');
        } catch (_) {
          try {
            await client.from('dme_customer_branches').insert(customerBranchesToInsert);
          } catch (branchErr) {
            debugPrint('Customer branches insert failed: $branchErr');
            onLog('⚠ Customer branches save error: $branchErr');
          }
        }
      }());
    }

    await Future.wait(parallelTasks);

    final totalRemindersSaved = remindersToInsert.length + remindersToUpdate.length;
    onLog('✓ Saved ${detailsToInsert.length} sale detail batches & $totalRemindersSaved reminders');

    // If fileName and fileHash are provided, record to dme_excel_uploads to disallow duplicate uploads
    if (fileName != null && fileHash != null) {
      try {
        await recordUpload(
          client: client,
          fileName: fileName,
          fileHash: fileHash,
          uploadedBy: uploadedBy,
          salesCount: insertedSalesList.length,
          rowsCount: rowsCount ?? 0,
        );
        onLog('✓ Recorded file hash in upload history');
      } catch (recordErr) {
        onLog('⚠ Could not record file upload hash: $recordErr');
      }
    }

    return insertedSalesList.length;
  }
}
