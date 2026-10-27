import 'package:cloud_firestore/cloud_firestore.dart';

class TransferResult {
  final bool success;
  final int totalTransferredRecords;
  final int monthsAffected;
  final String? errorMessage;

  const TransferResult({
    required this.success,
    this.totalTransferredRecords = 0,
    this.monthsAffected = 0,
    this.errorMessage,
  });
}

class TransferCallListService {
  static String _normalizePhone(dynamic phone) {
    if (phone == null) return '';
    final cleaned = phone.toString().replaceAll(RegExp(r'\D'), '');
    if (cleaned.length > 10) {
      return cleaned.substring(cleaned.length - 10);
    }
    return cleaned;
  }

  static bool isCustomerMatching(
    Map<String, dynamic> candidate,
    Map<String, dynamic> target,
  ) {
    final tName = (target['name'] ?? '').toString().trim().toLowerCase();
    final t1 = _normalizePhone(target['contact1'] ?? target['contact']);
    final t2 = _normalizePhone(target['contact2']);

    final cName = (candidate['name'] ?? '').toString().trim().toLowerCase();
    final c1 = _normalizePhone(candidate['contact1'] ?? candidate['contact']);
    final c2 = _normalizePhone(candidate['contact2']);

    if (t1.isNotEmpty) {
      if (c1 == t1 || (c2.isNotEmpty && c2 == t1)) {
        return true;
      }
    }
    if (t2.isNotEmpty) {
      if (c1 == t2 || (c2.isNotEmpty && c2 == t2)) {
        return true;
      }
    }
    if (tName.isNotEmpty && cName == tName) {
      return true;
    }

    return false;
  }

  static Future<TransferResult> executeTransfer({
    required String sourceEmail,
    required String destEmail,
    required String destBranch,
    required List<Map<String, dynamic>> customersToTransfer,
    required List<String> monthYears,
  }) async {
    try {
      final monthDocsSnapshot =
          await FirebaseFirestore.instance.collection('customer_target').get();

      final Set<String> allMonthIds = monthDocsSnapshot.docs.map((d) => d.id).toSet();
      for (final m in monthYears) {
        allMonthIds.add(m);
      }

      int totalTransferredRecords = 0;
      int monthsAffected = 0;

      for (final monthId in allMonthIds) {
        final sourceUserDocRef = FirebaseFirestore.instance
            .collection('customer_target')
            .doc(monthId)
            .collection('users')
            .doc(sourceEmail);

        final sourceDocSnap = await sourceUserDocRef.get();
        if (!sourceDocSnap.exists || sourceDocSnap.data() == null) {
          continue;
        }

        final sourceData = sourceDocSnap.data()!;
        final rawSourceCustomers = sourceData['customers'];
        if (rawSourceCustomers is! List || rawSourceCustomers.isEmpty) {
          continue;
        }

        final List<Map<String, dynamic>> sourceList =
            rawSourceCustomers.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        final List<Map<String, dynamic>> matchedToMove = [];
        final List<Map<String, dynamic>> remainingForSource = [];

        for (final item in sourceList) {
          bool matchFound = false;
          for (final target in customersToTransfer) {
            if (isCustomerMatching(item, target)) {
              matchFound = true;
              break;
            }
          }
          if (matchFound) {
            matchedToMove.add(item);
          } else {
            remainingForSource.add(item);
          }
        }

        if (matchedToMove.isNotEmpty) {
          final destUserDocRef = FirebaseFirestore.instance
              .collection('customer_target')
              .doc(monthId)
              .collection('users')
              .doc(destEmail);

          final destDocSnap = await destUserDocRef.get();
          List<Map<String, dynamic>> destList = [];
          if (destDocSnap.exists &&
              destDocSnap.data() != null &&
              destDocSnap.data()!['customers'] is List) {
            destList = (destDocSnap.data()!['customers'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }

          // Deduplicate destList against matchedToMove by phone and name
          final destPhoneSet = <String>{};
          for (final existing in destList) {
            final p1 = _normalizePhone(existing['contact1'] ?? existing['contact']);
            final p2 = _normalizePhone(existing['contact2']);
            if (p1.length >= 7) destPhoneSet.add(p1);
            if (p2.length >= 7) destPhoneSet.add(p2);
          }

          // Append or merge transferred customers without introducing duplicate phone entries in destination list
          for (final toMove in matchedToMove) {
            final p1 = _normalizePhone(toMove['contact1'] ?? toMove['contact']);
            final p2 = _normalizePhone(toMove['contact2']);
            final hasP1 = p1.length >= 7 && destPhoneSet.contains(p1);
            final hasP2 = p2.length >= 7 && destPhoneSet.contains(p2);

            if (hasP1 || hasP2) {
              // Existing customer with same phone already in destination: merge remarks/fields if needed
              final existingIndex = destList.indexWhere((c) {
                final cp1 = _normalizePhone(c['contact1'] ?? c['contact']);
                final cp2 = _normalizePhone(c['contact2']);
                return (p1.length >= 7 && (cp1 == p1 || cp2 == p1)) ||
                       (p2.length >= 7 && (cp1 == p2 || cp2 == p2));
              });
              if (existingIndex != -1) {
                final existing = destList[existingIndex];
                if ((existing['remarks'] == null || (existing['remarks'] as String).isEmpty) &&
                    (toMove['remarks'] != null && (toMove['remarks'] as String).isNotEmpty)) {
                  existing['remarks'] = toMove['remarks'];
                  existing['callMade'] = toMove['callMade'] ?? existing['callMade'];
                }
              }
            } else {
              destList.add(Map<String, dynamic>.from(toMove));
              if (p1.length >= 7) destPhoneSet.add(p1);
              if (p2.length >= 7) destPhoneSet.add(p2);
            }
          }

          final batch = FirebaseFirestore.instance.batch();

          batch.set(
            destUserDocRef,
            {
              'user': destEmail,
              'branch': destBranch,
              'customers': destList,
              'updated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          batch.update(sourceUserDocRef, {
            'customers': remainingForSource,
            'updated': FieldValue.serverTimestamp(),
          });

          await batch.commit();

          totalTransferredRecords += matchedToMove.length;
          monthsAffected++;
        }
      }

      return TransferResult(
        success: true,
        totalTransferredRecords: totalTransferredRecords,
        monthsAffected: monthsAffected,
      );
    } catch (e) {
      return TransferResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }
}
