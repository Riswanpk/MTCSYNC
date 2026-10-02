import 'package:flutter/foundation.dart';
import '../../Misc/dme_config.dart';

class CustomerMergeStats {
  final int totalReminders;
  final int pendingReminders;
  final int completedReminders;
  final int totalSales;
  final List<int> branchIds;
  final Map<String, dynamic>? activeReminder;

  CustomerMergeStats({
    required this.totalReminders,
    required this.pendingReminders,
    required this.completedReminders,
    required this.totalSales,
    required this.branchIds,
    this.activeReminder,
  });
}

class CustomerMergeResult {
  final bool success;
  final String message;
  final int remindersTransferred;
  final int salesTransferred;
  final int branchesTransferred;
  final int targetCustomerId;
  final String targetCustomerName;

  CustomerMergeResult({
    required this.success,
    required this.message,
    required this.remindersTransferred,
    required this.salesTransferred,
    required this.branchesTransferred,
    required this.targetCustomerId,
    required this.targetCustomerName,
  });
}

class DmeCustomerMergeService {
  /// Search customers by name, phone, address or salesman
  static Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      final response = await client
          .from('dme_customers')
          .select(
              'id, name, phone, address, salesman, preference, last_purchase_date, created_at, primary_branch, dme_customer_branches(branch_id, category_id, customer_type_id)')
          .or('name.ilike.%$q%,phone.ilike.%$q%,salesman.ilike.%$q%,address.ilike.%$q%')
          .order('last_purchase_date', ascending: false, nullsFirst: false)
          .limit(30);

      final List list = response as List;
      return list.map((item) {
        final cust = Map<String, dynamic>.from(item);
        final branchList = cust['dme_customer_branches'] as List?;
        List<int> branchIds = [];
        if (branchList != null) {
          for (var b in branchList) {
            final bId = int.tryParse(b['branch_id']?.toString() ?? '');
            if (bId != null && !branchIds.contains(bId)) {
              branchIds.add(bId);
            }
          }
        }
        cust['branch_ids'] = branchIds;
        return cust;
      }).toList();
    } catch (e) {
      debugPrint('Error searching customers for merge: $e');
      return [];
    }
  }

  /// Fetch stats for a customer (reminders, sales, branches)
  static Future<CustomerMergeStats> fetchCustomerStats(int customerId) async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      return CustomerMergeStats(
        totalReminders: 0,
        pendingReminders: 0,
        completedReminders: 0,
        totalSales: 0,
        branchIds: [],
      );
    }

    try {
      final results = await Future.wait([
        // 1. Reminders
        client
            .from('dme_reminders')
            .select('id, status, reminder_date, remarks')
            .eq('customer_id', customerId),

        // 2. Sales count
        client
            .from('dme_sales')
            .select('id')
            .eq('customer_id', customerId),

        // 3. Branches
        client
            .from('dme_customer_branches')
            .select('branch_id')
            .eq('customer_id', customerId),
      ]);

      final remindersList = results[0] as List;
      final salesList = results[1] as List;
      final branchesList = results[2] as List;

      int pendingCount = 0;
      int completedCount = 0;
      Map<String, dynamic>? activeRem;

      for (var r in remindersList) {
        final st = (r['status'] ?? '').toString().trim().toLowerCase();
        if (st == 'completed') {
          completedCount++;
        } else {
          pendingCount++;
          activeRem ??= Map<String, dynamic>.from(r);
        }
      }

      final branchIds = <int>{};
      for (var b in branchesList) {
        final bId = int.tryParse(b['branch_id']?.toString() ?? '');
        if (bId != null) branchIds.add(bId);
      }

      return CustomerMergeStats(
        totalReminders: remindersList.length,
        pendingReminders: pendingCount,
        completedReminders: completedCount,
        totalSales: salesList.length,
        branchIds: branchIds.toList(),
        activeReminder: activeRem,
      );
    } catch (e) {
      debugPrint('Error fetching customer stats: $e');
      return CustomerMergeStats(
        totalReminders: 0,
        pendingReminders: 0,
        completedReminders: 0,
        totalSales: 0,
        branchIds: [],
      );
    }
  }

  /// Execute the customer merge
  static Future<CustomerMergeResult> mergeCustomers({
    required int targetCustomerId,
    required int sourceCustomerId,
    required String resolvedName,
    required String resolvedPhone,
    String? resolvedAddress,
    String? resolvedSalesman,
    String? resolvedPreference,
    int? resolvedPrimaryBranch,
    DateTime? resolvedLastPurchaseDate,
    required String activeReminderStrategy, // 'keep_target', 'keep_source', 'keep_both'
    void Function(String message)? onProgress,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      return CustomerMergeResult(
        success: false,
        message: 'Database client not available',
        remindersTransferred: 0,
        salesTransferred: 0,
        branchesTransferred: 0,
        targetCustomerId: targetCustomerId,
        targetCustomerName: resolvedName,
      );
    }

    try {
      onProgress?.call('Fetching customer reminder records...');

      // 1. Fetch reminders for both customers
      final sourceReminders = await client
          .from('dme_reminders')
          .select('id, status, reminder_date, remarks')
          .eq('customer_id', sourceCustomerId);

      final targetReminders = await client
          .from('dme_reminders')
          .select('id, status, reminder_date, remarks')
          .eq('customer_id', targetCustomerId);

      final sourceRemList = List<Map<String, dynamic>>.from(sourceReminders as List);
      final targetRemList = List<Map<String, dynamic>>.from(targetReminders as List);

      onProgress?.call('Migrating reminder history to master customer...');

      // Handle active reminder resolution
      final sourceActiveReminders = sourceRemList.where((r) {
        final st = (r['status'] ?? '').toString().trim().toLowerCase();
        return st != 'completed';
      }).toList();

      final targetActiveReminders = targetRemList.where((r) {
        final st = (r['status'] ?? '').toString().trim().toLowerCase();
        return st != 'completed';
      }).toList();

      int remindersMovedCount = 0;

      if (sourceActiveReminders.isNotEmpty && targetActiveReminders.isNotEmpty) {
        if (activeReminderStrategy == 'keep_target') {
          // Complete source active reminders with audit note and transfer
          for (var sAct in sourceActiveReminders) {
            final oldRemarks = (sAct['remarks'] ?? '').toString().trim();
            final updatedRemarks = oldRemarks.isEmpty
                ? '[Merged from Customer #$sourceCustomerId]'
                : '$oldRemarks • [Merged from Customer #$sourceCustomerId]';
            await client.from('dme_reminders').update({
              'customer_id': targetCustomerId,
              'status': 'completed',
              'remarks': updatedRemarks,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', sAct['id']);
            remindersMovedCount++;
          }
        } else if (activeReminderStrategy == 'keep_source') {
          // Complete target active reminders with audit note
          for (var tAct in targetActiveReminders) {
            final oldRemarks = (tAct['remarks'] ?? '').toString().trim();
            final updatedRemarks = oldRemarks.isEmpty
                ? '[Archived due to merge with Customer #$sourceCustomerId]'
                : '$oldRemarks • [Archived due to merge with Customer #$sourceCustomerId]';
            await client.from('dme_reminders').update({
              'status': 'completed',
              'remarks': updatedRemarks,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', tAct['id']);
          }
          // Transfer source active reminder as active for target
          for (var sAct in sourceActiveReminders) {
            await client.from('dme_reminders').update({
              'customer_id': targetCustomerId,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', sAct['id']);
            remindersMovedCount++;
          }
        } else {
          // keep_both: reassign all to target
          for (var sAct in sourceActiveReminders) {
            await client.from('dme_reminders').update({
              'customer_id': targetCustomerId,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', sAct['id']);
            remindersMovedCount++;
          }
        }
      } else {
        // Only one or neither has an active reminder: simply transfer any source active reminder
        for (var sAct in sourceActiveReminders) {
          await client.from('dme_reminders').update({
            'customer_id': targetCustomerId,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', sAct['id']);
          remindersMovedCount++;
        }
      }

      // Reassign all completed reminders from source to target so history is unified
      final sourceCompletedReminders = sourceRemList.where((r) {
        final st = (r['status'] ?? '').toString().trim().toLowerCase();
        return st == 'completed';
      }).toList();

      for (var compRem in sourceCompletedReminders) {
        await client.from('dme_reminders').update({
          'customer_id': targetCustomerId,
        }).eq('id', compRem['id']);
        remindersMovedCount++;
      }

      onProgress?.call('Migrating sales transactions...');

      // 2. Transfer sales
      int salesMovedCount = 0;
      try {
        final sourceSales = await client
            .from('dme_sales')
            .select('id')
            .eq('customer_id', sourceCustomerId);
        salesMovedCount = (sourceSales as List).length;

        if (salesMovedCount > 0) {
          await client.from('dme_sales').update({
            'customer_id': targetCustomerId,
          }).eq('customer_id', sourceCustomerId);
        }
      } catch (e) {
        debugPrint('Notice updating dme_sales during merge: $e');
      }

      onProgress?.call('Consolidating customer branches...');

      // 3. Consolidate customer branches
      int branchesMovedCount = 0;
      try {
        final targetBranchesRes = await client
            .from('dme_customer_branches')
            .select('id, branch_id')
            .eq('customer_id', targetCustomerId);
        final sourceBranchesRes = await client
            .from('dme_customer_branches')
            .select('id, branch_id, category_id, customer_type_id')
            .eq('customer_id', sourceCustomerId);

        final targetBranchIds = (targetBranchesRes as List)
            .map((b) => int.tryParse(b['branch_id']?.toString() ?? ''))
            .whereType<int>()
            .toSet();

        for (var sb in (sourceBranchesRes as List)) {
          final bId = int.tryParse(sb['branch_id']?.toString() ?? '');
          final rowId = sb['id'];
          if (bId != null) {
            if (targetBranchIds.contains(bId)) {
              // Duplicate branch already in target: remove source row
              if (rowId != null) {
                await client.from('dme_customer_branches').delete().eq('id', rowId);
              } else {
                await client
                    .from('dme_customer_branches')
                    .delete()
                    .eq('customer_id', sourceCustomerId)
                    .eq('branch_id', bId);
              }
            } else {
              // Branch only in source: re-assign to target
              if (rowId != null) {
                await client
                    .from('dme_customer_branches')
                    .update({'customer_id': targetCustomerId})
                    .eq('id', rowId);
              } else {
                await client
                    .from('dme_customer_branches')
                    .update({'customer_id': targetCustomerId})
                    .eq('customer_id', sourceCustomerId)
                    .eq('branch_id', bId);
              }
              targetBranchIds.add(bId);
              branchesMovedCount++;
            }
          }
        }
      } catch (e) {
        debugPrint('Notice updating dme_customer_branches during merge: $e');
      }

      onProgress?.call('Migrating call logs and auxiliary records...');

      // 4. Migrate auxiliary tables
      try {
        await client.from('dme_call_logs').update({
          'customer_id': targetCustomerId,
        }).eq('customer_id', sourceCustomerId);
      } catch (e) {
        debugPrint('Notice updating dme_call_logs: $e');
      }

      try {
        await client.from('dme_complaints').update({
          'customer_id': targetCustomerId,
          'customer_name': resolvedName,
          'customer_phone': resolvedPhone,
        }).eq('customer_id', sourceCustomerId);
      } catch (e) {
        debugPrint('Notice updating dme_complaints: $e');
      }

      try {
        await client.from('dme_whatsapp_proofs').update({
          'customer_id': targetCustomerId,
        }).eq('customer_id', sourceCustomerId);
      } catch (e) {
        debugPrint('Notice updating dme_whatsapp_proofs: $e');
      }

      try {
        await client.from('dme_change_requests').update({
          'customer_id': targetCustomerId,
        }).eq('customer_id', sourceCustomerId);
      } catch (e) {
        debugPrint('Notice updating dme_change_requests: $e');
      }

      onProgress?.call('Updating master customer profile...');

      // 5. Update target customer record with resolved information
      final targetUpdatePayload = <String, dynamic>{
        'name': resolvedName,
        'phone': resolvedPhone,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (resolvedAddress != null && resolvedAddress.trim().isNotEmpty) {
        targetUpdatePayload['address'] = resolvedAddress.trim();
      }
      if (resolvedSalesman != null && resolvedSalesman.trim().isNotEmpty) {
        targetUpdatePayload['salesman'] = resolvedSalesman.trim();
      }
      if (resolvedPreference != null && resolvedPreference.trim().isNotEmpty) {
        targetUpdatePayload['preference'] = resolvedPreference.trim();
      }
      if (resolvedPrimaryBranch != null) {
        targetUpdatePayload['primary_branch'] = resolvedPrimaryBranch;
      }
      if (resolvedLastPurchaseDate != null) {
        targetUpdatePayload['last_purchase_date'] = resolvedLastPurchaseDate.toIso8601String();
      }

      await client
          .from('dme_customers')
          .update(targetUpdatePayload)
          .eq('id', targetCustomerId);

      onProgress?.call('Removing duplicate customer record...');

      // 6. Delete source customer
      bool sourceDeleted = false;
      try {
        await client.from('dme_customers').delete().eq('id', sourceCustomerId);
        sourceDeleted = true;
      } catch (deleteErr) {
        debugPrint('Notice deleting source customer $sourceCustomerId: $deleteErr');
        // If deletion is blocked by any remaining constraint, mark name as MERGED
        try {
          await client.from('dme_customers').update({
            'name': '[MERGED] Customer #$sourceCustomerId',
            'phone': 'merged_$sourceCustomerId',
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', sourceCustomerId);
        } catch (_) {}
      }

      return CustomerMergeResult(
        success: true,
        message: sourceDeleted
            ? 'Customer #$sourceCustomerId was successfully merged into Customer #$targetCustomerId ($resolvedName).'
            : 'Customer #$sourceCustomerId history transferred into Customer #$targetCustomerId ($resolvedName).',
        remindersTransferred: remindersMovedCount,
        salesTransferred: salesMovedCount,
        branchesTransferred: branchesMovedCount,
        targetCustomerId: targetCustomerId,
        targetCustomerName: resolvedName,
      );
    } catch (e) {
      debugPrint('Error merging customers: $e');
      return CustomerMergeResult(
        success: false,
        message: 'Merge failed: $e',
        remindersTransferred: 0,
        salesTransferred: 0,
        branchesTransferred: 0,
        targetCustomerId: targetCustomerId,
        targetCustomerName: resolvedName,
      );
    }
  }
}
