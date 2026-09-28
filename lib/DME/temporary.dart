import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OldLeadsRemover {
  /// Deletes leads from the Firestore `follow_ups` collection that were created
  /// more than 2 months ago based strictly on creation date (`created_at` or `date`).
  /// Note: Reminder dates are intentionally ignored.
  static Future<Map<String, dynamic>> deleteLeadsOlderThan2Months({
    required Function(String log) onLog,
    required Function(double progress, String status) onProgress,
  }) async {
    final firestore = FirebaseFirestore.instance;

    final now = DateTime.now();
    // Calculate cutoff date: exactly 60 days / 2 calendar months ago
    final cutoffDate = DateTime(now.year, now.month - 2, now.day, 0, 0, 0);
    final cutoffStr = DateFormat('dd MMM yyyy').format(cutoffDate);

    onLog('Starting cleanup of leads older than 2 months (Created before $cutoffStr)...');
    onProgress(0.05, 'Fetching all leads from follow_ups collection...');

    final QuerySnapshot querySnapshot =
        await firestore.collection('follow_ups').get();
    final allDocs = querySnapshot.docs;

    onLog('✓ Fetched ${allDocs.length} total lead documents.');
    if (allDocs.isEmpty) {
      onProgress(1.0, 'No leads found.');
      return {
        'total_leads': 0,
        'deleted_count': 0,
      };
    }

    onProgress(0.3, 'Checking creation dates against cutoff ($cutoffStr)...');

    DateTime? extractCreationDate(Map<String, dynamic> data) {
      // 1. Check created_at (Timestamp or DateTime or String)
      final createdAt = data['created_at'];
      if (createdAt is Timestamp) return createdAt.toDate();
      if (createdAt is DateTime) return createdAt;
      if (createdAt is String && createdAt.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(createdAt.trim());
        if (parsed != null) return parsed;
      }

      // 2. Fallback to date field (creation date set when lead is logged)
      final dateVal = data['date'];
      if (dateVal is Timestamp) return dateVal.toDate();
      if (dateVal is DateTime) return dateVal;
      if (dateVal is String && dateVal.trim().isNotEmpty) {
        final str = dateVal.trim();
        try {
          return DateTime.parse(str);
        } catch (_) {
          try {
            return DateFormat('dd-MM-yyyy').parse(str);
          } catch (_) {
            try {
              return DateFormat('dd/MM/yyyy').parse(str);
            } catch (_) {
              return null;
            }
          }
        }
      }

      return null;
    }

    final List<String> docIdsToDelete = [];

    for (final doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final creationDate = extractCreationDate(data);
      if (creationDate == null) {
        // If no creation date could be determined, do not delete to be safe
        continue;
      }

      if (creationDate.isBefore(cutoffDate)) {
        docIdsToDelete.add(doc.id);
        final leadName = data['name'] ?? 'Unknown';
        final leadPhone = data['phone'] ?? 'No Phone';
        final leadDateStr = DateFormat('dd-MM-yyyy').format(creationDate);
        final leadStatus = data['status'] ?? 'Unknown';
        final leadSource = data['source'] ?? 'General';

        onLog('Lead to delete: "$leadName" ($leadPhone) | Created: $leadDateStr | Source: $leadSource | Status: $leadStatus');
      }
    }

    onLog('Found ${docIdsToDelete.length} lead(s) created before $cutoffStr out of ${allDocs.length} total leads.');

    if (docIdsToDelete.isEmpty) {
      onProgress(1.0, 'No leads older than 2 months found. Database is clean!');
      return {
        'total_leads': allDocs.length,
        'deleted_count': 0,
      };
    }

    onProgress(0.6, 'Deleting ${docIdsToDelete.length} old lead(s)...');

    // Batch delete in chunks of 450 (Firestore limit is 500 operations per batch)
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
      onProgress(
        progressVal,
        'Deleted $deletedCount / ${docIdsToDelete.length} old leads...',
      );
    }

    onProgress(1.0, 'Completed successfully!');
    onLog('✓ Successfully deleted $deletedCount lead(s) older than 2 months.');

    return {
      'total_leads': allDocs.length,
      'deleted_count': deletedCount,
    };
  }

  /// Show interactive dialog in UI to trigger old leads cleanup
  static void showOldLeadsCleanupDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _OldLeadsCleanupDialog(),
    );
  }
}

class _OldLeadsCleanupDialog extends StatefulWidget {
  const _OldLeadsCleanupDialog();

  @override
  State<_OldLeadsCleanupDialog> createState() => _OldLeadsCleanupDialogState();
}

class _OldLeadsCleanupDialogState extends State<_OldLeadsCleanupDialog> {
  bool _isRunning = false;
  double _progress = 0.0;
  String _status = 'Ready to find and delete leads older than 2 months.';
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
      final res = await OldLeadsRemover.deleteLeadsOlderThan2Months(
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

    final now = DateTime.now();
    final cutoffDate = DateTime(now.year, now.month - 2, now.day);
    final cutoffStr = DateFormat('dd MMM yyyy').format(cutoffDate);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.auto_delete_rounded, color: Colors.redAccent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Delete Old Leads (> 2 Months)',
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
              'This tool checks the creation date (`created_at` / `date`) of all leads in follow_ups and permanently deletes any lead created before $cutoffStr (older than 2 months). Reminder dates are ignored.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 14),
            if (_isRunning || _progress > 0) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.grey[300],
                color: Colors.redAccent,
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
                        'Completed: ${_result!['deleted_count']} old lead(s) deleted.',
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
              : const Icon(Icons.delete_forever_rounded, size: 18),
          label: Text(_result != null ? 'Run Again' : 'Delete Old Leads'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}
