import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'excel_uploader_models.dart';

class ExcelUploadService {
  /// Uploads all processed data to Supabase in fast batch operations
  static Future<int> uploadSales({
    required SupabaseClient client,
    required List<GroupedSale> groupedSales,
    required List<CustomerConflict> conflicts,
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

    // Upsert customers in bulk
    final upsertedCustRes = await client
        .from('dme_customers')
        .upsert(
          customersToUpsert.values.toList(),
          onConflict: 'phone',
        )
        .select('id, phone');

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

    // 2. Batch Upsert Sales (Handles re-uploads and multiple sales per customer cleanly)
    final List<Map<String, dynamic>> salesToInsert = [];
    final Map<String, int> saleGroupToIdx = {};

    for (int i = 0; i < groupedSales.length; i++) {
      final sale = groupedSales[i];
      final activePhone = activePhoneBySale['${sale.party}_${sale.phone}_${sale.date.millisecondsSinceEpoch}'] ?? sale.phone;
      final custId = phoneToCustomerId[activePhone];
      final dateStr = DateFormat('yyyy-MM-dd').format(sale.date);
      final saleKey = '${custId}_${dateStr}_${sale.branchId}';

      if (!saleGroupToIdx.containsKey(saleKey)) {
        saleGroupToIdx[saleKey] = salesToInsert.length;
        salesToInsert.add({
          'date': dateStr,
          'customer_id': custId,
          'purchased_branch': sale.branchId,
          'salesman': sale.salesman.isNotEmpty ? sale.salesman : null,
          'category_id': sale.categoryId,
          'customer_type_id': sale.typeId,
          'uploaded_by': uploadedBy,
        });
      }
    }

    dynamic insertedSalesRes;
    try {
      // Try upserting with date,customer_id,purchased_branch or onConflict date,customer_id
      insertedSalesRes = await client
          .from('dme_sales')
          .upsert(
            salesToInsert,
            onConflict: 'date,customer_id,purchased_branch',
          )
          .select('id, date, customer_id, purchased_branch');
    } catch (upsertErr) {
      debugPrint('Upsert onConflict date,customer_id,purchased_branch note: $upsertErr');
      try {
        insertedSalesRes = await client
            .from('dme_sales')
            .upsert(
              salesToInsert,
              onConflict: 'date,customer_id',
            )
            .select('id, date, customer_id, purchased_branch');
      } catch (_) {
        // If constraint is custom named, fallback to plain upsert without explicit onConflict
        insertedSalesRes = await client
            .from('dme_sales')
            .upsert(salesToInsert)
            .select('id, date, customer_id, purchased_branch');
      }
    }

    final List insertedSalesList = insertedSalesRes as List;
    final Map<String, int> saleKeyToSaleId = {};
    for (var row in insertedSalesList) {
      final id = row['id'] as int?;
      final dt = row['date']?.toString();
      final cId = row['customer_id']?.toString();
      final bId = row['purchased_branch']?.toString();
      if (id != null && dt != null && cId != null) {
        saleKeyToSaleId['${cId}_${dt}_$bId'] = id;
        saleKeyToSaleId['${cId}_$dt'] = id;
      }
    }

    onLog('✓ Synchronized ${insertedSalesList.length} sales records in database');

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
        // Excluded: TRUST (7), INSTITUTION (8), VEHICLE SHOWROOM (11), GENERAL & OTHERS (13)
        final catId = sale.categoryId;
        final catName = sale.categoryName.toUpperCase().trim();
        final isExcludedCategory = catId == 7 ||
            catId == 8 ||
            catId == 11 ||
            catId == 13 ||
            catName.contains('TRUST') ||
            catName.contains('INSTITUTION') ||
            catName.contains('VEHICLE') ||
            catName.contains('GENERAL');

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

    // Check existing reminders in database to ensure we advance due dates for existing customers
    final List<int> customerIdsWithNewReminders = remindersByCustomer.keys.toList();
    if (customerIdsWithNewReminders.isNotEmpty) {
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
            if (cId != null && remindersByCustomer.containsKey(cId)) {
              final dbLastPurchaseStr = dbRow['last_purchase_date']?.toString();
              final dbLastPurchase = dbLastPurchaseStr != null ? DateTime.tryParse(dbLastPurchaseStr) : null;

              final currentObj = remindersByCustomer[cId]!;
              final newLastPurchaseStr = currentObj['last_purchase_date']?.toString();
              final newLastPurchase = newLastPurchaseStr != null ? DateTime.tryParse(newLastPurchaseStr) : null;

              // If existing DB last purchase is newer than Excel, preserve the DB one
              if (dbLastPurchase != null && newLastPurchase != null && dbLastPurchase.isAfter(newLastPurchase)) {
                remindersByCustomer[cId] = {
                  'customer_id': cId,
                  'reminder_date': dbRow['reminder_date'],
                  'last_purchase_date': dbRow['last_purchase_date'],
                  'last_purchase_branch': currentObj['last_purchase_branch'],
                  'status': dbRow['status'],
                  'updated_at': DateTime.now().toIso8601String(),
                };
              } else {
                // The newly uploaded invoice is newer: Reset status to 'pending' and advance reminder_date forward!
                currentObj['status'] = 'pending';
                currentObj['updated_at'] = DateTime.now().toIso8601String();
              }
            }
          }
        }
      } catch (checkErr) {
        debugPrint('Notice checking existing reminders: $checkErr');
      }
    }

    final remindersToUpsert = remindersByCustomer.values.toList();
    final customerBranchesToInsert = branchesByCustBranch.values.toList();

    // Execute batch inserts concurrently for maximum speed
    await Future.wait([
      if (detailsToInsert.isNotEmpty)
        client.from('dme_sales_detail').insert(detailsToInsert),
      if (remindersToUpsert.isNotEmpty)
        client.from('dme_reminders').upsert(remindersToUpsert, onConflict: 'customer_id'),
      if (customerBranchesToInsert.isNotEmpty)
        client.from('dme_customer_branches').insert(customerBranchesToInsert),
    ]);

    onLog('✓ Saved ${detailsToInsert.length} sale detail batches & ${remindersToUpsert.length} reminders');

    return insertedSalesList.length;
  }
}
