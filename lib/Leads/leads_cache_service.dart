import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local data representation for a lead item in the leads list
class CachedLeadModel {
  final String id;
  final String name;
  final String status;
  final String date;
  final String reminder;
  final String createdBy;
  final String priority;
  final String? source;
  final String branch;
  final String? assignedTo;
  final String? screenedBy;
  final String? screeningStatus;
  final int? createdAtMillis;
  final Map<String, dynamic> rawData;

  CachedLeadModel({
    required this.id,
    required this.name,
    required this.status,
    required this.date,
    required this.reminder,
    required this.createdBy,
    required this.priority,
    this.source,
    required this.branch,
    this.assignedTo,
    this.screenedBy,
    this.screeningStatus,
    this.createdAtMillis,
    required this.rawData,
  });

  factory CachedLeadModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    String dateStr = 'No Date';
    final dateVal = data['date'];
    if (dateVal is Timestamp) {
      dateStr = dateVal.toDate().toIso8601String();
    } else if (dateVal is String) {
      dateStr = dateVal;
    } else if (dateVal is DateTime) {
      dateStr = dateVal.toIso8601String();
    }

    int? createdAt;
    final createdVal = data['created_at'];
    if (createdVal is Timestamp) {
      createdAt = createdVal.millisecondsSinceEpoch;
    } else if (createdVal is int) {
      createdAt = createdVal;
    }

    // Convert non-json serializable types in rawData for local cache safety
    final safeRaw = <String, dynamic>{};
    data.forEach((k, v) {
      if (v is Timestamp) {
        safeRaw[k] = v.toDate().toIso8601String();
      } else if (v is DateTime) {
        safeRaw[k] = v.toIso8601String();
      } else if (v is FieldValue) {
        // skip or ignore
      } else {
        safeRaw[k] = v;
      }
    });

    return CachedLeadModel(
      id: doc.id,
      name: (data['name'] ?? 'No Name').toString(),
      status: (data['status'] ?? 'Unknown').toString(),
      date: dateStr,
      reminder: (data['reminder'] ?? 'No Reminder').toString(),
      createdBy: (data['created_by'] ?? '').toString(),
      priority: (data['priority'] ?? 'High').toString(),
      source: data['source'] as String?,
      branch: (data['branch'] ?? '').toString(),
      assignedTo: data['assigned_to'] as String?,
      screenedBy: data['screened_by'] as String?,
      screeningStatus: data['screening_status'] as String?,
      createdAtMillis: createdAt,
      rawData: safeRaw,
    );
  }

  factory CachedLeadModel.fromMap(Map<String, dynamic> map) {
    return CachedLeadModel(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? 'No Name').toString(),
      status: (map['status'] ?? 'Unknown').toString(),
      date: (map['date'] ?? 'No Date').toString(),
      reminder: (map['reminder'] ?? 'No Reminder').toString(),
      createdBy: (map['created_by'] ?? '').toString(),
      priority: (map['priority'] ?? 'High').toString(),
      source: map['source'] as String?,
      branch: (map['branch'] ?? '').toString(),
      assignedTo: map['assigned_to'] as String?,
      screenedBy: map['screened_by'] as String?,
      screeningStatus: map['screening_status'] as String?,
      createdAtMillis: map['created_at_millis'] as int?,
      rawData: (map['raw_data'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'date': date,
      'reminder': reminder,
      'created_by': createdBy,
      'priority': priority,
      'source': source,
      'branch': branch,
      'assigned_to': assignedTo,
      'screened_by': screenedBy,
      'screening_status': screeningStatus,
      'created_at_millis': createdAtMillis,
      'raw_data': rawData,
    };
  }

  Map<String, dynamic> toViewData() {
    return {
      ...rawData,
      'id': id,
      'docId': id,
      'name': name,
      'status': status,
      'date': date,
      'reminder': reminder,
      'created_by': createdBy,
      'priority': priority,
      'source': source,
      'branch': branch,
      'assigned_to': assignedTo,
      'screened_by': screenedBy,
      'screening_status': screeningStatus,
    };
  }
}

/// Service that manages local caching of leads per user/branch.
///
/// Requirement:
/// - When user opens the leads page for the first time on a day, fetch from Firestore.
/// - Otherwise, serve immediately from local cache (0 database reads).
/// - Manual reload button or pull-to-refresh forces a refresh from Firestore.
/// - Any updates/adds made in leads are also synced to local cache immediately.
class LeadsCacheService {
  LeadsCacheService._();
  static final LeadsCacheService instance = LeadsCacheService._();

  static const String _prefixKey = 'cached_leads_v1_';
  static const String _lastFetchDateKey = 'cached_leads_last_date_';

  String _cacheKey(String userIdOrBranch) =>
      '$_prefixKey${userIdOrBranch.trim().toLowerCase()}';
  String _dateKey(String userIdOrBranch) =>
      '$_lastFetchDateKey${userIdOrBranch.trim().toLowerCase()}';

  String _todayDateStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Checks if Firestore was already fetched today for this user/branch scope
  Future<bool> hasFetchedToday(String userIdOrBranch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDate = prefs.getString(_dateKey(userIdOrBranch));
      return lastDate == _todayDateStr();
    } catch (_) {
      return false;
    }
  }

  /// Mark today as fetched
  Future<void> markFetchedToday(String userIdOrBranch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dateKey(userIdOrBranch), _todayDateStr());
    } catch (_) {}
  }

  /// Get cached leads
  Future<List<CachedLeadModel>> getCachedLeads(String userIdOrBranch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(userIdOrBranch));
      if (raw == null || raw.isEmpty) return [];

      final list = jsonDecode(raw);
      if (list is List) {
        return list
            .map((e) =>
                CachedLeadModel.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Error reading cached leads: $e');
    }
    return [];
  }

  /// Save leads to local cache
  Future<void> saveCachedLeads(
      String userIdOrBranch, List<CachedLeadModel> leads) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(leads.map((l) => l.toMap()).toList());
      await prefs.setString(_cacheKey(userIdOrBranch), data);
    } catch (e) {
      debugPrint('Error saving cached leads: $e');
    }
  }

  /// Update a single lead status in local cache
  Future<void> updateLeadStatus(String userIdOrBranch, String docId,
      String newStatus, {String? billedPhone, String? cancellationReason}) async {
    final leads = await getCachedLeads(userIdOrBranch);
    final updated = leads.map((l) {
      if (l.id == docId) {
        final newRaw = Map<String, dynamic>.from(l.rawData);
        newRaw['status'] = newStatus;
        if (billedPhone != null) newRaw['billed_phone'] = billedPhone;
        if (cancellationReason != null) {
          newRaw['cancellation_reason'] = cancellationReason;
        }
        return CachedLeadModel(
          id: l.id,
          name: l.name,
          status: newStatus,
          date: l.date,
          reminder: l.reminder,
          createdBy: l.createdBy,
          priority: l.priority,
          source: l.source,
          branch: l.branch,
          assignedTo: l.assignedTo,
          screenedBy: l.screenedBy,
          screeningStatus: l.screeningStatus,
          createdAtMillis: l.createdAtMillis,
          rawData: newRaw,
        );
      }
      return l;
    }).toList();
    await saveCachedLeads(userIdOrBranch, updated);
  }

  /// Add or update a lead in local cache
  Future<void> upsertLead(String userIdOrBranch, CachedLeadModel lead) async {
    final leads = await getCachedLeads(userIdOrBranch);
    final index = leads.indexWhere((l) => l.id == lead.id);
    if (index >= 0) {
      leads[index] = lead;
    } else {
      leads.insert(0, lead);
    }
    await saveCachedLeads(userIdOrBranch, leads);
  }
}
