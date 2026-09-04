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
  static bool isCustomerMatching(
    Map<String, dynamic> candidate,
    Map<String, dynamic> target,
  ) {
    final tName = (target['name'] ?? '').toString().trim().toLowerCase();
    final tContact1 = (target['contact1'] ?? target['contact'] ?? '').toString().trim();
    final tContact2 = (target['contact2'] ?? '').toString().trim();

    final cName = (candidate['name'] ?? '').toString().trim().toLowerCase();
    final cContact1 = (candidate['contact1'] ?? candidate['contact'] ?? '').toString().trim();
    final cContact2 = (candidate['contact2'] ?? '').toString().trim();

    if (tContact1.isNotEmpty) {
      if (cContact1 == tContact1 || (cContact2.isNotEmpty && cContact2 == tContact1)) {
        return true;
      }
    }
    if (tContact2.isNotEmpty) {
      if (cContact1 == tContact2 || (cContact2.isNotEmpty && cContact2 == tContact2)) {
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

          // Append transferred customers directly without overwriting existing customers
          for (final toMove in matchedToMove) {
            destList.add(Map<String, dynamic>.from(toMove));
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
