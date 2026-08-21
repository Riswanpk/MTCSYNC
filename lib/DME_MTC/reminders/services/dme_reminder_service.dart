import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/dme_reminder_model.dart';
import '../../core/services/dme_supabase_service.dart';
import '../../../Misc/firebase_storage_helper.dart';

class DmeReminderService {
  static final DmeReminderService instance = DmeReminderService._internal();
  DmeReminderService._internal();

  SupabaseClient get _client => DmeMtcSupabaseService.instance.client;

  Future<bool> scheduleReminder({
    required int customerId,
    required DateTime purchaseDate,
    required int purchaseForBranchId,
    String? purchaseForBranchName,
    String? assignedTo,
    Map<String, dynamic>? purchaseDetails,
  }) async {
    try {
      final reminderDate = purchaseDate.add(const Duration(days: 28));
      final purchaseDateStr = purchaseDate.toIso8601String().split('T')[0];
      final reminderDateStr = reminderDate.toIso8601String().split('T')[0];

      final existing = await _client
          .from('dme_reminders')
          .select()
          .eq('customer_id', customerId)
          .maybeSingle();

      final basePayload = <String, dynamic>{
        'customer_id': customerId,
        'reminder_date': reminderDateStr,
        'last_purchase_date': purchaseDateStr,
        'status': 'pending',
      };

      if (existing == null) {
        await _insertReminderWithBranchFallback(
          basePayload: basePayload,
          branchId: purchaseForBranchId,
          branchName: purchaseForBranchName,
        );
        return true;
      } else {
        final currentStatus = existing['status'] as String? ?? 'pending';

        if (currentStatus == 'completed' || currentStatus == 'dismissed') {
          await _insertReminderWithBranchFallback(
            basePayload: basePayload,
            branchId: purchaseForBranchId,
            branchName: purchaseForBranchName,
          );
          return true;
        } else {
          final lastPurchaseDateStr = existing['last_purchase_date'] as String?;
          final lastPurchaseDate = lastPurchaseDateStr != null
              ? DateTime.tryParse(lastPurchaseDateStr)
              : null;

          if (lastPurchaseDate == null || purchaseDate.isAfter(lastPurchaseDate)) {
            final updatePayload = <String, dynamic>{
              'reminder_date': reminderDateStr,
              'last_purchase_date': purchaseDateStr,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            };
            await _updateReminderWithBranchFallback(
              customerId: customerId,
              basePayload: updatePayload,
              branchId: purchaseForBranchId,
              branchName: purchaseForBranchName,
            );
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error scheduling reminder for customer $customerId: $e');
      return false;
    }
  }

  Future<bool> recordPurchaseWithBranch({
    required int customerId,
    required DateTime purchaseDate,
    required int purchaseForBranchId,
    required String? purchaseForBranchName,
    Map<String, dynamic>? purchaseDetails,
  }) async {
    try {
      await DmeMtcSupabaseService.instance.ensureInitialized();
      final purchaseDateStr = purchaseDate.toIso8601String().split('T')[0];

      final existing = await _client
          .from('dme_customer_purchases')
          .select()
          .eq('customer_id', customerId)
          .eq('purchase_date', purchaseDateStr)
          .eq('purchase_for_branch_id', purchaseForBranchId)
          .maybeSingle();

      if (existing != null) {
        return false;
      }

      await _client.from('dme_customer_purchases').insert({
        'customer_id': customerId,
        'purchase_date': purchaseDateStr,
        'purchase_for_branch_id': purchaseForBranchId,
        'purchase_for_branch_name': purchaseForBranchName,
        'purchase_details': purchaseDetails,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error recording purchase with branch: $e');
      rethrow;
    }
  }

  Future<bool> upsertReminder({
    required int customerId,
    required DateTime purchaseDate,
    required int purchaseForBranchId,
    String? purchaseForBranchName,
    String? assignedTo,
    Map<String, dynamic>? purchaseDetails,
  }) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final purchaseIsNew = await recordPurchaseWithBranch(
      customerId: customerId,
      purchaseDate: purchaseDate,
      purchaseForBranchId: purchaseForBranchId,
      purchaseForBranchName: purchaseForBranchName,
      purchaseDetails: purchaseDetails,
    );

    if (!purchaseIsNew) {
      return false;
    }

    final existing = await _client
        .from('dme_reminders')
        .select()
        .eq('customer_id', customerId)
        .maybeSingle();

    final reminderDate = purchaseDate.add(const Duration(days: 28));
    final purchaseDateStr = purchaseDate.toIso8601String().split('T')[0];
    final reminderDateStr = reminderDate.toIso8601String().split('T')[0];

    final basePayload = <String, dynamic>{
      'customer_id': customerId,
      'reminder_date': reminderDateStr,
      'last_purchase_date': purchaseDateStr,
      'status': 'pending',
    };

    if (existing == null) {
      await _insertReminderWithBranchFallback(
        basePayload: basePayload,
        branchId: purchaseForBranchId,
        branchName: purchaseForBranchName,
      );
      return true;
    } else {
      final currentStatus = existing['status'] as String? ?? 'pending';

      if (currentStatus == 'completed' || currentStatus == 'dismissed') {
        await _insertReminderWithBranchFallback(
          basePayload: basePayload,
          branchId: purchaseForBranchId,
          branchName: purchaseForBranchName,
        );
        return true;
      } else {
        final lastPurchaseDateStr = existing['last_purchase_date'] as String?;
        final lastPurchaseDate = lastPurchaseDateStr != null
            ? DateTime.tryParse(lastPurchaseDateStr)
            : null;

        if (lastPurchaseDate == null ||
            purchaseDate.isAfter(lastPurchaseDate)) {
          final updatePayload = <String, dynamic>{
            'reminder_date': reminderDateStr,
            'last_purchase_date': purchaseDateStr,
          };
          await _updateReminderWithBranchFallback(
            customerId: customerId,
            basePayload: updatePayload,
            branchId: purchaseForBranchId,
            branchName: purchaseForBranchName,
          );
          return true;
        }
        return true;
      }
    }
  }

  Future<List<DmeReminderModel>> getReminders({
    List<int>? branchIds,
    String? status,
    List<String>? statuses,
    DateTime? from,
    DateTime? to,
    DateTime? updatedFrom,
    DateTime? updatedTo,
    int limit = 500,
  }) async {
    try {
      var query = _client
          .from('dme_reminders')
          .select('*, dme_customers(name, phone, address, salesman)');

      if (statuses != null && statuses.isNotEmpty) {
        query = query.inFilter('status', statuses);
      } else if (status != null) {
        query = query.eq('status', status);
      }

      if (from != null) {
        query = query.gte('reminder_date', from.toIso8601String().split('T')[0]);
      }
      if (to != null) {
        query = query.lte('reminder_date', to.toIso8601String().split('T')[0]);
      }

      if (branchIds != null && branchIds.isNotEmpty) {
        query = query.or('purchased_for_branch_id.in.(${branchIds.join(',')}),last_purchase_branch.in.(${branchIds.join(',')})');
      }

      final res = await query.order('reminder_date', ascending: true).limit(limit);
      return (res as List)
          .map((row) => DmeReminderModel.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching reminders: $e');
      return [];
    }
  }

  Future<List<DmeReminderModel>> getRemindersForToday(List<int> branchIds) async {
    final today = DateTime.now();
    final todayStr = today.toIso8601String().split('T')[0];

    var query = _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, salesman)')
        .eq('reminder_date', todayStr)
        .eq('status', 'pending');

    if (branchIds.isNotEmpty) {
      query = query.or('purchased_for_branch_id.in.(${branchIds.join(',')}),last_purchase_branch.in.(${branchIds.join(',')})');
    }

    final res = await query
        .order('reminder_date', ascending: true)
        .limit(500);
    return (res as List).map((e) => DmeReminderModel.fromMap(e)).toList();
  }

  Future<List<DmeReminderModel>> getPendingFromPreviousDays(
      List<int> branchIds) async {
    final today = DateTime.now();
    final todayStr = today.toIso8601String().split('T')[0];

    var query = _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, salesman)')
        .lt('reminder_date', todayStr)
        .eq('status', 'pending');

    if (branchIds.isNotEmpty) {
      query = query.or('purchased_for_branch_id.in.(${branchIds.join(',')}),last_purchase_branch.in.(${branchIds.join(',')})');
    }

    final res = await query
        .order('reminder_date', ascending: true)
        .limit(500);
    return (res as List).map((e) => DmeReminderModel.fromMap(e)).toList();
  }

  Future<DmeReminderModel?> getReminderDetail(int reminderId) async {
    final res = await _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, salesman)')
        .eq('id', reminderId)
        .maybeSingle();

    debugPrint('getReminderDetail result: $res');
    return res != null ? DmeReminderModel.fromMap(res) : null;
  }

  Future<DmeReminderModel?> getReminderById(int id) => getReminderDetail(id);

  Future<bool> updateStatus(int id, String status, {String? notes}) async {
    try {
      final map = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (notes != null) map['notes'] = notes;
      await _client.from('dme_reminders').update(map).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Error updating reminder status ($id): $e');
      return false;
    }
  }

  Future<void> updateReminderStatus(int id, String status, {String? notes}) async {
    await updateStatus(id, status, notes: notes);
  }

  Future<void> completeReminder(int reminderId, {String? notes}) async {
    await updateStatus(reminderId, 'completed', notes: notes);
  }

  Future<bool> deleteReminder(int id) async {
    try {
      await _client.from('dme_reminders').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Error deleting reminder ($id): $e');
      return false;
    }
  }

  /// Sync/generate reminders for all customers who have a last_purchase_date
  /// but do not have an active reminder set up yet.
  Future<int> syncRemindersFromCustomers() async {
    int createdCount = 0;
    try {
      await DmeMtcSupabaseService.instance.ensureInitialized();
      
      final excludedCategories = {
        'TRUST',
        'INSTITUTION',
        'VEHICLE SHOWROOM',
        'GENERAL & OTHERS',
      };

      // 1. Fetch customers with last_purchase_date
      final customersWithPurchase = await _client
          .from('dme_customers')
          .select('id, last_purchase_date')
          .not('last_purchase_date', 'is', null);

      if ((customersWithPurchase as List).isEmpty) return 0;

      final customerIds = (customersWithPurchase as List)
          .map((c) => c['id'] as int?)
          .whereType<int>()
          .toList();

      // 2. Fetch category mapping from dme_customer_branches
      final customerCategories = <int, Set<String>>{};

      try {
        for (int i = 0; i < customerIds.length; i += 500) {
          final batch = customerIds.sublist(
              i, i + 500 > customerIds.length ? customerIds.length : i + 500);
          final branchesRes = await _client
              .from('dme_customer_branches')
              .select('customer_id, category_id, dme_categories(name)')
              .inFilter('customer_id', batch);

          for (final row in branchesRes as List) {
            final custId = row['customer_id'] as int?;
            if (custId == null) continue;
            String? catName;
            if (row['dme_categories'] is Map) {
              catName = (row['dme_categories'] as Map)['name'] as String?;
            }
            if (catName != null && catName.isNotEmpty) {
              customerCategories
                  .putIfAbsent(custId, () => {})
                  .add(catName.trim().toUpperCase());
            }
          }
        }
      } catch (e) {
        debugPrint('FK join dme_customer_branches with dme_categories failed ($e), trying separate lookup fallback.');
        try {
          final catRes = await _client.from('dme_categories').select('id, name');
          final catMap = <int, String>{};
          for (final c in catRes as List) {
            final id = c['id'] as int?;
            final name = c['name'] as String?;
            if (id != null && name != null) {
              catMap[id] = name.trim().toUpperCase();
            }
          }

          for (int i = 0; i < customerIds.length; i += 500) {
            final batch = customerIds.sublist(
                i, i + 500 > customerIds.length ? customerIds.length : i + 500);
            final branchesRes = await _client
                .from('dme_customer_branches')
                .select('customer_id, category_id')
                .inFilter('customer_id', batch);

            for (final row in branchesRes as List) {
              final custId = row['customer_id'] as int?;
              final catId = row['category_id'] as int?;
              if (custId != null && catId != null && catMap.containsKey(catId)) {
                customerCategories
                    .putIfAbsent(custId, () => {})
                    .add(catMap[catId]!);
              }
            }
          }
        } catch (fallbackErr) {
          debugPrint('Category lookup fallback failed: $fallbackErr');
        }
      }

      for (final cust in customersWithPurchase) {
        final custId = cust['id'] as int?;
        final dateStr = cust['last_purchase_date'] as String?;
        const branchId = 1;

        if (custId == null || dateStr == null || dateStr.isEmpty) continue;

        // Apply category exclusion rule (check if any category assigned to customer branch is excluded)
        final categories = customerCategories[custId] ?? {};
        final isExcluded = categories.any((cat) => excludedCategories.contains(cat));
        if (isExcluded) {
          continue; // Skip reminder creation for excluded categories
        }

        final purchaseDate = DateTime.tryParse(dateStr);
        if (purchaseDate == null) continue;

        final reminderDate = purchaseDate.add(const Duration(days: 28));
        final reminderDateStr = reminderDate.toIso8601String().split('T')[0];
        final purchaseDateStr = purchaseDate.toIso8601String().split('T')[0];

        // Check if reminder already exists for this customer
        final existing = await _client
            .from('dme_reminders')
            .select('id')
            .eq('customer_id', custId)
            .maybeSingle();

        if (existing == null) {
          final payload = <String, dynamic>{
            'customer_id': custId,
            'reminder_date': reminderDateStr,
            'last_purchase_date': purchaseDateStr,
            'status': 'pending',
          };

          try {
            await _insertReminderWithBranchFallback(
              basePayload: payload,
              branchId: branchId,
            );
            createdCount++;
          } catch (e) {
            debugPrint('Error creating sync reminder for customer $custId: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error syncing reminders from customer purchases: $e');
    }
    return createdCount;
  }

  Future<bool> rescheduleReminderIfNeeded(
      int customerId, DateTime newPurchaseDate) async {
    final existing = await _client
        .from('dme_reminders')
        .select('reminder_date, status')
        .eq('customer_id', customerId)
        .maybeSingle();

    if (existing == null) {
      return false;
    }

    final currentReminderDate =
        DateTime.parse(existing['reminder_date'] as String);
    if (newPurchaseDate.isAfter(currentReminderDate)) {
      final newReminderDate = newPurchaseDate.add(const Duration(days: 28));
      await _client.from('dme_reminders').update({
        'reminder_date': newReminderDate.toIso8601String().split('T')[0],
        'last_purchase_date': newPurchaseDate.toIso8601String().split('T')[0],
        'status': 'pending',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('customer_id', customerId);
      return true;
    }

    return false;
  }

  Future<String?> uploadWhatsAppProof({
    required int reminderId,
    required int customerId,
    required Uint8List compressedImageBytes,
    required String remarks,
  }) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'whatsapp_proof_${customerId}_$timestamp.jpg';
      final path = 'dme_reminders/$reminderId/$filename';

      final uploadResult = await _uploadProofWithFallback(
        path: path,
        bytes: compressedImageBytes,
      );

      await _insertWhatsAppProofRecord(
        reminderId: reminderId,
        customerId: customerId,
        uploadPath: uploadResult.path,
        uploadUrl: uploadResult.publicUrl,
        remarks: remarks,
      );

      return uploadResult.path;
    } catch (e) {
      debugPrint('Error uploading WhatsApp proof: $e');
      rethrow;
    }
  }

  Future<_ProofUploadResult> _uploadProofWithFallback({
    required String path,
    required Uint8List bytes,
  }) async {
    const supabaseBuckets = ['dme-proofs', 'dme_proofs', 'proofs'];
    Object? lastBucketError;

    for (final bucket in supabaseBuckets) {
      try {
        final uploadedPath = await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
        if (uploadedPath.isEmpty) continue;
        return _ProofUploadResult(
          path: uploadedPath,
          publicUrl: _client.storage.from(bucket).getPublicUrl(path),
        );
      } catch (e) {
        final message = e.toString().toLowerCase();
        final isBucketMissing =
            message.contains('bucket not found') || message.contains('bucket_not_found');
        if (!isBucketMissing) rethrow;
        lastBucketError = e;
      }
    }

    for (final storage in FirebaseStorageHelper.storageCandidates()) {
      try {
        final ref = storage.ref().child('dme_whatsapp_proofs').child(path);
        await ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final url = await ref.getDownloadURL();
        return _ProofUploadResult(
          path: ref.fullPath,
          publicUrl: url,
        );
      } catch (e) {
        lastBucketError = e;
      }
    }

    throw Exception(
      'Proof upload failed. Supabase proof bucket is missing and Firebase upload fallback also failed. '
      'Original error: ${lastBucketError ?? 'unknown'}',
    );
  }

  Future<void> _insertWhatsAppProofRecord({
    required int reminderId,
    required int customerId,
    required String uploadPath,
    required String uploadUrl,
    required String remarks,
  }) async {
    final uploadedAt = DateTime.now().toUtc().toIso8601String();

    final base = <String, dynamic>{
      'reminder_id': reminderId,
      'customer_id': customerId,
    };

    final metaVariants = <Map<String, dynamic>>[
      {'remarks': remarks, 'uploaded_at': uploadedAt},
      {'notes': remarks, 'uploaded_at': uploadedAt},
      {'remarks': remarks},
      {'notes': remarks},
      {'uploaded_at': uploadedAt},
      {},
    ];

    final locationVariants = <Map<String, dynamic>>[
      {'image_path': uploadPath, 'image_url': uploadUrl},
      {'proof_path': uploadPath, 'proof_url': uploadUrl},
      {'file_path': uploadPath, 'file_url': uploadUrl},
      {'path': uploadPath, 'url': uploadUrl},
      {'image_url': uploadUrl},
      {'proof_url': uploadUrl},
      {'file_url': uploadUrl},
      {'url': uploadUrl},
      {'image_path': uploadPath},
      {'proof_path': uploadPath},
      {'file_path': uploadPath},
      {'path': uploadPath},
      {},
    ];

    Object? lastError;
    for (final meta in metaVariants) {
      for (final location in locationVariants) {
        final payload = <String, dynamic>{
          ...base,
          ...meta,
          ...location,
        };
        try {
          await _client.from('dme_whatsapp_proofs').insert(payload);
          return;
        } catch (e) {
          lastError = e;
          if (_isSchemaMismatchError(e) || _isNotNullConstraintError(e)) {
            continue;
          }
          rethrow;
        }
      }
    }

    throw Exception(
      'Upload succeeded but saving proof record failed due to table schema mismatch in dme_whatsapp_proofs. '
      'Last error: ${lastError ?? 'unknown'}',
    );
  }

  bool _isSchemaMismatchError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('pgrst204') ||
        (msg.contains('could not find') && msg.contains('column')) ||
        msg.contains('column of') && msg.contains('in the schema cache');
  }

  bool _isNotNullConstraintError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains("null value in column") ||
        msg.contains('violates not-null constraint') ||
        msg.contains("code: 23502");
  }

  Future<void> logCall({
    required int reminderId,
    required String calledBy,
    required DateTime callDate,
    String? remarks,
  }) async {}

  Future<List<Map<String, dynamic>>> getCallLogs(int customerId) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final res = await _client
        .from('dme_reminders')
        .select()
        .eq('customer_id', customerId)
        .eq('status', 'completed')
        .order('reminder_date', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> _insertReminderWithBranchFallback({
    required Map<String, dynamic> basePayload,
    required int branchId,
    String? branchName,
  }) async {
    final payloadVariants = <Map<String, dynamic>>[
      {
        ...basePayload,
        'purchased_for_branch_id': branchId,
        'purchased_for_branch_name': branchName ?? '',
      },
      {
        ...basePayload,
        'purchased_for_branch_id': branchId,
      },
      {
        ...basePayload,
        'last_purchase_branch': branchId,
      },
      basePayload,
    ];

    Object? lastError;
    for (final payload in payloadVariants) {
      try {
        await _client.from('dme_reminders').insert(payload);
        return;
      } catch (e) {
        lastError = e;
        if (_isSchemaMismatchError(e)) {
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Failed to insert reminder: $lastError');
  }

  Future<void> _updateReminderWithBranchFallback({
    required int customerId,
    required Map<String, dynamic> basePayload,
    required int branchId,
    String? branchName,
  }) async {
    final payloadVariants = <Map<String, dynamic>>[
      {
        ...basePayload,
        'purchased_for_branch_id': branchId,
        'purchased_for_branch_name': branchName ?? '',
      },
      {
        ...basePayload,
        'purchased_for_branch_id': branchId,
      },
      {
        ...basePayload,
        'last_purchase_branch': branchId,
      },
      basePayload,
    ];

    Object? lastError;
    for (final payload in payloadVariants) {
      try {
        await _client.from('dme_reminders').update(payload).eq('customer_id', customerId);
        return;
      } catch (e) {
        lastError = e;
        if (_isSchemaMismatchError(e)) {
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Failed to update reminder: $lastError');
  }
}

class _ProofUploadResult {
  final String path;
  final String publicUrl;

  const _ProofUploadResult({required this.path, required this.publicUrl});
}
