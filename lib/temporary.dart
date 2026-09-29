import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class OrphanedDeletionChecker {
  static Future<void> showCheckDialog(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _OrphanedDeletionDialog(),
    );
  }
}

class _OrphanedDeletionDialog extends StatefulWidget {
  const _OrphanedDeletionDialog();

  @override
  State<_OrphanedDeletionDialog> createState() => _OrphanedDeletionDialogState();
}

class _OrphanedDeletionDialogState extends State<_OrphanedDeletionDialog> {
  bool _isScanning = false;
  bool _isFixing = false;
  final List<String> _logs = [];
  final List<Map<String, dynamic>> _orphanedItems = [];
  String _monthYear = 'Sep 2026';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monthYear = 'Sep ${now.year}';
  }

  void _addLog(String msg) {
    if (mounted) {
      setState(() {
        _logs.add(msg);
      });
    }
  }

  Future<void> _scanOrphanedRequests() async {
    setState(() {
      _isScanning = true;
      _logs.clear();
      _orphanedItems.clear();
    });

    try {
      _addLog('Scanning customer_target/$_monthYear/users...');

      // 1. Fetch all user docs under customer_target/$_monthYear/users
      final usersSnap = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_monthYear)
          .collection('users')
          .get();

      _addLog('Found ${usersSnap.docs.length} user documents.');

      // 2. Fetch all deletion requests for this month
      _addLog('Fetching existing deletion requests for $_monthYear...');
      final delSnap = await FirebaseFirestore.instance
          .collection('customer_deletion_requests')
          .where('monthYear', isEqualTo: _monthYear)
          .get();

      _addLog('Found ${delSnap.docs.length} deletion requests in Firestore.');

      // Build index of requests for quick matching: userDocId + name + contact
      final Set<String> existingRequestKeys = {};
      for (final doc in delSnap.docs) {
        final data = doc.data();
        final userDocId = (data['userDocId'] ?? data['userEmail'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final cData = data['customerData'] as Map<String, dynamic>?;
        if (cData != null) {
          final cName = (cData['name'] ?? '').toString().trim().toLowerCase();
          final cContact = (cData['contact1'] ?? cData['contact'] ?? '')
              .toString()
              .trim()
              .replaceAll(RegExp(r'\D'), '');
          existingRequestKeys.add('$userDocId|$cName|$cContact');
          existingRequestKeys.add('$userDocId|$cName');
        }
      }

      int totalPendingFound = 0;
      int orphanedCount = 0;

      for (final userDoc in usersSnap.docs) {
        final userDocId = userDoc.id.trim().toLowerCase();
        final userData = userDoc.data();
        final customers = List<dynamic>.from(userData['customers'] ?? []);

        for (int i = 0; i < customers.length; i++) {
          final c = customers[i];
          if (c is Map && c['pendingDeletion'] == true) {
            totalPendingFound++;
            final cName = (c['name'] ?? '').toString().trim().toLowerCase();
            final cContact = (c['contact1'] ?? c['contact'] ?? '')
                .toString()
                .trim()
                .replaceAll(RegExp(r'\D'), '');

            final keyWithContact = '$userDocId|$cName|$cContact';
            final keyNameOnly = '$userDocId|$cName';

            final hasRequest = existingRequestKeys.contains(keyWithContact) ||
                (cContact.isEmpty && existingRequestKeys.contains(keyNameOnly));

            if (!hasRequest) {
              orphanedCount++;
              _orphanedItems.add({
                'userDocId': userDoc.id,
                'customerIndex': i,
                'customer': Map<String, dynamic>.from(c),
              });
              _addLog(
                  '⚠ Missing request for: "${c['name']}" (User: ${userDoc.id})');
            }
          }
        }
      }

      _addLog('--- Scan Finished ---');
      _addLog('Total pendingDeletion customers: $totalPendingFound');
      _addLog('Orphaned (missing doc): $orphanedCount');
    } catch (e) {
      _addLog('Error during scan: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _resetPendingStatus() async {
    if (_orphanedItems.isEmpty) return;

    setState(() => _isFixing = true);
    _addLog('Resetting pendingDeletion to false for ${_orphanedItems.length} customers...');

    try {
      final Map<String, List<Map<String, dynamic>>> byUser = {};
      for (final item in _orphanedItems) {
        final uId = item['userDocId'] as String;
        byUser.putIfAbsent(uId, () => []).add(item);
      }

      for (final entry in byUser.entries) {
        final userDocRef = FirebaseFirestore.instance
            .collection('customer_target')
            .doc(_monthYear)
            .collection('users')
            .doc(entry.key);

        final snap = await userDocRef.get();
        if (snap.exists && snap.data()?['customers'] != null) {
          final List<dynamic> customers = List.from(snap.data()!['customers']);
          for (final item in entry.value) {
            final targetCust = item['customer'] as Map<String, dynamic>;
            final targetName = (targetCust['name'] ?? '').toString();
            final targetContact =
                (targetCust['contact1'] ?? targetCust['contact'] ?? '').toString();

            for (var c in customers) {
              if (c is Map &&
                  (c['name'] ?? '').toString() == targetName &&
                  (c['contact1'] ?? c['contact'] ?? '').toString() ==
                      targetContact) {
                c['pendingDeletion'] = false;
              }
            }
          }
          await userDocRef.update({'customers': customers});
          _addLog('✓ Reset pendingDeletion for user: ${entry.key}');
        }
      }
      _addLog('Completed resetting pendingDeletion!');
      _orphanedItems.clear();
    } catch (e) {
      _addLog('Error resetting pending status: $e');
    } finally {
      if (mounted) setState(() => _isFixing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.search_off_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Check Missing Deletion Requests',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Target Month:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _monthYear,
                    isExpanded: true,
                    items: [
                      'Sep 2026',
                      'Sep 2025',
                      'Sep 2024',
                    ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: _isScanning || _isFixing
                        ? null
                        : (val) {
                            if (val != null) {
                              setState(() => _monthYear = val);
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _isScanning || _isFixing ? null : _scanOrphanedRequests,
              icon: _isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.manage_search_rounded),
              label: Text(_isScanning ? 'Scanning...' : 'Scan Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005BAC),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            if (_orphanedItems.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text(
                  'Found ${_orphanedItems.length} customers with pendingDeletion = true but no deletion request document.',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.deepOrange),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isFixing ? null : _resetPendingStatus,
                  icon: _isFixing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(_isFixing
                      ? 'Resetting Status...'
                      : 'Reset pendingDeletion to False (${_orphanedItems.length})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Text(
              'Logs:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              height: 160,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text('Tap "Scan Now" to begin scan',
                          style: TextStyle(color: Colors.grey, fontSize: 12)))
                  : ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (ctx, idx) => Text(
                        _logs[idx],
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isScanning || _isFixing
              ? null
              : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
