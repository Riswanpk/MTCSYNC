import 'package:call_log/call_log.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class SmeCallScannerService {
  static bool numberMatches(String logNumber, String? contact) {
    if (contact == null || contact.isEmpty) return false;
    String clean = contact.replaceAll(RegExp(r'\D'), '');
    return logNumber.endsWith(clean) || clean.endsWith(logNumber);
  }

  /// Scans today's call logs and returns a list of SME leads that match the call criteria
  /// (outgoing call initiated today, and any call >= outgoing call time lasting >5 seconds).
  static Future<List<Map<String, dynamic>>> scanTodayCallLog(
      List<Map<String, dynamic>> leads, {String? currentUid}) async {
    final permStatus = await Permission.phone.status;
    if (!permStatus.isGranted) return [];

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: startOfDay.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      final List<Map<String, dynamic>> matchedLeads = [];

      for (var lead in leads) {
        String screeningStatus = (lead['screening_status'] ?? 'pending').toString().toLowerCase();
        if (screeningStatus == 'called' || screeningStatus == 'promoted' || screeningStatus == 'rejected') {
          continue;
        }

        String? c1 = lead['phone'] ?? lead['contact1'] ?? lead['contact'];
        String? c2 = lead['contact2'];

        int latestOutgoingTime = -1;
        for (final entry in entries) {
          if (entry.callType != CallType.outgoing) continue;
          String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
          if (logNumber.isEmpty) continue;
          if (numberMatches(logNumber, c1) || numberMatches(logNumber, c2)) {
            if (entry.timestamp != null && entry.timestamp! > latestOutgoingTime) {
              latestOutgoingTime = entry.timestamp!;
            }
          }
        }
        if (latestOutgoingTime == -1) continue;

        CallLogEntry? matchedEntry;
        for (final entry in entries) {
          if (entry.timestamp == null || entry.timestamp! < latestOutgoingTime) continue;
          String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
          if (logNumber.isEmpty) continue;
          bool longEnough = (entry.duration ?? 0) > 5;
          if ((numberMatches(logNumber, c1) || numberMatches(logNumber, c2)) && longEnough) {
            matchedEntry = entry;
            break;
          }
        }

        if (matchedEntry != null) {
          lead['screening_status'] = 'called';
          lead['screening_call_duration'] = matchedEntry.duration ?? 0;
          if (matchedEntry.timestamp != null) {
            lead['screening_call_time'] = Timestamp.fromMillisecondsSinceEpoch(matchedEntry.timestamp!);
          }
          matchedLeads.add(lead);

          final docId = (lead['_docSnapshot'] as DocumentSnapshot?)?.id ?? lead['docId'] ?? lead['doc_id'] ?? lead['id'];
          if (docId != null && docId.toString().isNotEmpty) {
            final updateData = <String, dynamic>{
              'screening_status': 'called',
              'screening_call_duration': matchedEntry.duration ?? 0,
            };
            if (matchedEntry.timestamp != null) {
              updateData['screening_call_time'] = Timestamp.fromMillisecondsSinceEpoch(matchedEntry.timestamp!);
            } else {
              updateData['screening_call_time'] = FieldValue.serverTimestamp();
            }
            if (currentUid != null && currentUid.isNotEmpty) {
              updateData['screened_by'] = currentUid;
            }
            try {
              await FirebaseFirestore.instance.collection('follow_ups').doc(docId.toString()).update(updateData);
            } catch (e) {
              debugPrint('Error updating lead screening_status to called: $e');
            }
          }
        }
      }

      return matchedLeads;
    } catch (e) {
      debugPrint('Error scanning SME call log: $e');
      return [];
    }
  }
}
