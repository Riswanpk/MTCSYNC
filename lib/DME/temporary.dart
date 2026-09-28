import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LeadDuplicateRemover {
  /// Cleans duplicate leads from the Firestore `follow_ups` collection.
  /// Duplicates are identified when customer name, phone, and date match.
  /// If duplicates exist:
  /// - Only 1 lead is retained.
  /// - Priority is given to leads with status 'Sale' (or 'Sold') or 'Cancelled'.
  /// - If none is sold or cancelled (e.g., all are 'In Progress'), one is kept and others deleted.
  static Future<Map<String, dynamic>> removeDuplicateLeads({
    required Function(String log) onLog,
    required Function(double progress, String status) onProgress,
  }) async {
    final firestore = FirebaseFirestore.instance;

    onLog('Starting duplicate leads cleanup...');
    onProgress(0.05, 'Fetching all leads from follow_ups collection...');

    // 1. Fetch all documents in follow_ups
    final QuerySnapshot querySnapshot =
        await firestore.collection('follow_ups').get();
    final allDocs = querySnapshot.docs;

    onLog('✓ Fetched ${allDocs.length} total lead documents.');
    if (allDocs.isEmpty) {
      onProgress(1.0, 'No leads found.');
      return {
        'total_leads': 0,
        'duplicate_groups': 0,
        'deleted_count': 0,
      };
    }

    onProgress(0.3, 'Analyzing leads for duplicates (Name, Phone, Date)...');

    // Helper functions for normalization
    String normalizeName(String? name) {
      if (name == null) return '';
      return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    }

    String normalizePhone(String? phone) {
      if (phone == null) return '';
      // Keep only digits
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 10) {
        return digits.substring(digits.length - 10);
      }
      return digits;
    }

    String formatDate(dynamic dateVal) {
      DateTime? parsed;
      if (dateVal is Timestamp) {
        parsed = dateVal.toDate();
      } else if (dateVal is DateTime) {
        parsed = dateVal;
      } else if (dateVal is String && dateVal.trim().isNotEmpty) {
        final str = dateVal.trim();
        try {
          parsed = DateTime.parse(str);
        } catch (_) {
          try {
            parsed = DateFormat('dd-MM-yyyy').parse(str);
          } catch (_) {
            try {
              parsed = DateFormat('dd/MM/yyyy').parse(str);
            } catch (_) {
              parsed = null;
            }
          }
        }
      }

      if (parsed != null) {
        return DateFormat('dd-MM-yyyy').format(parsed);
      }
      return 'NO_DATE';
    }

    // Status rank: Sale/Sold and Cancelled get priority (rank 1), others (In Progress, etc.) get rank 2
    int getStatusPriorityRank(String? status) {
      if (status == null) return 2;
      final st = status.trim().toLowerCase();
      if (st == 'sale' || st == 'sold' || st == 'cancelled' || st == 'canceled') {
        return 1;
      }
      return 2;
    }

    // 2. Group documents by "name_phone_date"
    final Map<String, List<QueryDocumentSnapshot>> groups = {};

    for (final doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final normName = normalizeName(data['name']?.toString());
      final normPhone = normalizePhone(data['phone']?.toString());
      final formattedDate = formatDate(data['date']);

      // Only consider if name or phone is non-empty to avoid grouping blank documents improperly
      if (normName.isEmpty && normPhone.isEmpty) continue;

      final key = '${normName}_${normPhone}_$formattedDate';
      groups.putIfAbsent(key, () => []).add(doc);
    }

    final List<String> docIdsToDelete = [];
    int duplicateGroupsCount = 0;

    for (final entry in groups.entries) {
      final docsInGroup = entry.value;
      if (docsInGroup.length > 1) {
        duplicateGroupsCount++;

        // Sort: Priority rank ascending (1 before 2)
        // Secondary sort: Keep document with created_at or earliest/latest if available
        docsInGroup.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;

          final rankA = getStatusPriorityRank(dataA['status']?.toString());
          final rankB = getStatusPriorityRank(dataB['status']?.toString());

          if (rankA != rankB) {
            return rankA.compareTo(rankB);
          }

          // If ranks are equal, prefer the one that has comments or reminder info
          final commentsA = (dataA['comments']?.toString() ?? '').trim().length;
          final commentsB = (dataB['comments']?.toString() ?? '').trim().length;
          return commentsB.compareTo(commentsA);
        });

        final keptDoc = docsInGroup.first;
        final keptData = keptDoc.data() as Map<String, dynamic>;
        final keptName = keptData['name'] ?? 'Unknown';
        final keptPhone = keptData['phone'] ?? 'Unknown';
        final keptStatus = keptData['status'] ?? 'Unknown';

        onLog('Duplicate group for "$keptName" ($keptPhone): Keeping 1 (${keptDoc.id}, Status: $keptStatus), Deleting ${docsInGroup.length - 1} duplicates');

        // All subsequent docs are marked for deletion
        for (int i = 1; i < docsInGroup.length; i++) {
          docIdsToDelete.add(docsInGroup[i].id);
        }
      }
    }

    onLog('Found $duplicateGroupsCount duplicate group(s) with ${docIdsToDelete.length} total duplicate document(s) to delete.');

    if (docIdsToDelete.isEmpty) {
      onProgress(1.0, 'No duplicate leads found. All clean!');
      return {
        'total_leads': allDocs.length,
        'duplicate_groups': 0,
        'deleted_count': 0,
      };
    }

    onProgress(0.6, 'Deleting ${docIdsToDelete.length} duplicate lead(s)...');

    // 3. Batch delete duplicate documents in chunks of 450 (Firestore limit is 500 operations per batch)
    int deletedCount = 0;
    const int batchSize = 450;

    for (int i = 0; i < docIdsToDelete.length; i += batchSize) {
      final end = (i + batchSize > docIdsToDelete.length)
          ? docIdsToDelete.length
          : i + batchSize;
      final chunk = docIdsToDelete.sublist(i, end);

      final batch = firestore.batch();
      for (final docId in chunk) {
        batch.delete(firestore.collection('follow_ups').doc(docId));
      }

      await batch.commit();
      deletedCount += chunk.length;

      final progressVal = 0.6 + (0.38 * (deletedCount / docIdsToDelete.length));
      onProgress(progressVal, 'Deleted $deletedCount / ${docIdsToDelete.length} duplicates...');
    }

    onProgress(1.0, 'Completed successfully!');
    onLog('✓ Successfully removed $deletedCount duplicate lead(s).');

    return {
      'total_leads': allDocs.length,
      'duplicate_groups': duplicateGroupsCount,
      'deleted_count': deletedCount,
    };
  }

  /// Show interactive dialog in UI to trigger duplicate leads cleanup
  static void showDuplicateCleanupDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DuplicateCleanupDialog(),
    );
  }
}

class _DuplicateCleanupDialog extends StatefulWidget {
  const _DuplicateCleanupDialog();

  @override
  State<_DuplicateCleanupDialog> createState() =>
      _DuplicateCleanupDialogState();
}

class _DuplicateCleanupDialogState extends State<_DuplicateCleanupDialog> {
  bool _isRunning = false;
  double _progress = 0.0;
  String _status = 'Ready to find and remove duplicate leads.';
  final List<String> _logs = [];
  Map<String, dynamic>? _result;

  void _runCleanup() async {
    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _logs.clear();
      _result = null;
    });

    try {
      final res = await LeadDuplicateRemover.removeDuplicateLeads(
        onLog: (msg) {
          if (mounted) {
            setState(() {
              _logs.add(msg);
            });
          }
        },
        onProgress: (p, s) {
          if (mounted) {
            setState(() {
              _progress = p;
              _status = s;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isRunning = false;
          _result = res;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _logs.add('❌ Error: $e');
          _status = 'Failed with error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.cleaning_services_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Remove Duplicate Leads',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This tool checks for duplicate leads with the same Customer Name, Phone Number, and Date. If all three match, only 1 lead is kept (favoring Sale or Cancelled over In Progress).',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 14),
            if (_isRunning || _progress > 0) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.grey[300],
                color: Colors.orange,
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
            ],
            if (_result != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Completed: ${_result!['deleted_count']} duplicate lead(s) deleted across ${_result!['duplicate_groups']} group(s).',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_logs.isNotEmpty) ...[
              const Text('Execution Logs:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                height: 160,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _logs.length,
                  itemBuilder: (_, idx) => Text(
                    _logs[idx],
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isRunning)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ElevatedButton.icon(
          onPressed: _isRunning ? null : _runCleanup,
          icon: _isRunning
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.delete_sweep_rounded, size: 18),
          label: Text(_result != null ? 'Run Again' : 'Start Duplicate Cleanup'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}
