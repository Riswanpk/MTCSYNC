import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local data representation for an order in the Orders list
class CachedOrderModel {
  final String id;
  final String name;
  final String status;
  final dynamic createdAt;
  final dynamic deliveryDate;
  final String createdBy;
  final String priority;
  final String branch;
  final String? assignedTo;
  final int? createdAtMillis;
  final Map<String, dynamic> rawData;

  CachedOrderModel({
    required this.id,
    required this.name,
    required this.status,
    this.createdAt,
    this.deliveryDate,
    required this.createdBy,
    required this.priority,
    required this.branch,
    this.assignedTo,
    this.createdAtMillis,
    required this.rawData,
  });

  factory CachedOrderModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    int? createdAtMs;
    final createdVal = data['created_at'] ?? data['date'];
    if (createdVal is Timestamp) {
      createdAtMs = createdVal.millisecondsSinceEpoch;
    } else if (createdVal is int) {
      createdAtMs = createdVal;
    }

    final safeRaw = <String, dynamic>{};
    data.forEach((k, v) {
      if (v is Timestamp) {
        safeRaw[k] = v.toDate().toIso8601String();
      } else if (v is DateTime) {
        safeRaw[k] = v.toIso8601String();
      } else if (v is FieldValue) {
        // skip
      } else {
        safeRaw[k] = v;
      }
    });

    return CachedOrderModel(
      id: doc.id,
      name: (data['name'] ?? 'No Name').toString(),
      status: (data['status'] ?? 'In Progress').toString(),
      createdAt: data['date'] ?? data['created_at'],
      deliveryDate: data['delivery_datetime'] ?? data['delivery_date'],
      createdBy: (data['created_by'] ?? '').toString(),
      priority: (data['priority'] ?? 'High').toString(),
      branch: (data['branch'] ?? '').toString(),
      assignedTo: data['assigned_to'] as String?,
      createdAtMillis: createdAtMs,
      rawData: safeRaw,
    );
  }

  factory CachedOrderModel.fromMap(Map<String, dynamic> map) {
    return CachedOrderModel(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? 'No Name').toString(),
      status: (map['status'] ?? 'In Progress').toString(),
      createdAt: map['created_at_str'],
      deliveryDate: map['delivery_date_str'],
      createdBy: (map['created_by'] ?? '').toString(),
      priority: (map['priority'] ?? 'High').toString(),
      branch: (map['branch'] ?? '').toString(),
      assignedTo: map['assigned_to'] as String?,
      createdAtMillis: map['created_at_millis'] as int?,
      rawData: (map['raw_data'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    String? createdStr;
    if (createdAt is Timestamp) {
      createdStr = (createdAt as Timestamp).toDate().toIso8601String();
    } else if (createdAt is String) {
      createdStr = createdAt as String;
    } else if (createdAt is DateTime) {
      createdStr = (createdAt as DateTime).toIso8601String();
    }

    String? delStr;
    if (deliveryDate is Timestamp) {
      delStr = (deliveryDate as Timestamp).toDate().toIso8601String();
    } else if (deliveryDate is String) {
      delStr = deliveryDate as String;
    } else if (deliveryDate is DateTime) {
      delStr = (deliveryDate as DateTime).toIso8601String();
    }

    return {
      'id': id,
      'name': name,
      'status': status,
      'created_at_str': createdStr,
      'delivery_date_str': delStr,
      'created_by': createdBy,
      'priority': priority,
      'branch': branch,
      'assigned_to': assignedTo,
      'created_at_millis': createdAtMillis,
      'raw_data': rawData,
    };
  }

  Map<String, dynamic> toViewData() {
    final copy = Map<String, dynamic>.from(rawData);
    copy['name'] = name;
    copy['status'] = status;
    copy['created_by'] = createdBy;
    copy['priority'] = priority;
    copy['branch'] = branch;
    if (createdAt != null) {
      copy['created_at'] = createdAt;
      copy['date'] = createdAt;
    }
    if (deliveryDate != null) {
      copy['delivery_datetime'] = deliveryDate;
      copy['delivery_date'] = deliveryDate;
    }
    return copy;
  }
}

/// Service to cache Confirmed Orders locally in SharedPreferences per branch/scope.
class OrdersCacheService {
  OrdersCacheService._();
  static final OrdersCacheService instance = OrdersCacheService._();

  static const String _prefix = 'cached_orders_v1_';
  static const String _lastFetchPrefix = 'orders_last_fetch_';

  String _cacheKey(String branch) => '$_prefix${branch.trim().toLowerCase()}';
  String _todayFetchKey(String branch) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return '$_lastFetchPrefix${branch.trim().toLowerCase()}_$today';
  }

  Future<bool> hasFetchedToday(String branch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_todayFetchKey(branch)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markFetchedToday(String branch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_todayFetchKey(branch), true);
    } catch (e) {
      debugPrint('Error marking orders fetched today: $e');
    }
  }

  Future<List<CachedOrderModel>> getCachedOrders(String branch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(branch));
      if (raw == null || raw.isEmpty) return [];

      final list = jsonDecode(raw);
      if (list is List) {
        return list
            .map((e) => CachedOrderModel.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Error reading cached orders: $e');
    }
    return [];
  }

  Future<void> saveCachedOrders(String branch, List<CachedOrderModel> orders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(orders.map((o) => o.toMap()).toList());
      await prefs.setString(_cacheKey(branch), data);
    } catch (e) {
      debugPrint('Error saving cached orders: $e');
    }
  }

  Future<void> updateOrderStatus({
    required String branch,
    required String docId,
    required String newStatus,
  }) async {
    final list = await getCachedOrders(branch);
    bool found = false;
    final updated = list.map((order) {
      if (order.id == docId) {
        found = true;
        final newRaw = Map<String, dynamic>.from(order.rawData);
        newRaw['status'] = newStatus;
        return CachedOrderModel(
          id: order.id,
          name: order.name,
          status: newStatus,
          createdAt: order.createdAt,
          deliveryDate: order.deliveryDate,
          createdBy: order.createdBy,
          priority: order.priority,
          branch: order.branch,
          assignedTo: order.assignedTo,
          createdAtMillis: order.createdAtMillis,
          rawData: newRaw,
        );
      }
      return order;
    }).toList();

    if (found) {
      await saveCachedOrders(branch, updated);
    }
  }

  Future<void> removeOrder({
    required String branch,
    required String docId,
  }) async {
    final list = await getCachedOrders(branch);
    list.removeWhere((o) => o.id == docId);
    await saveCachedOrders(branch, list);
  }

  Future<void> upsertOrder({
    required String branch,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final list = await getCachedOrders(branch);
    final idx = list.indexWhere((o) => o.id == docId);

    final safeRaw = <String, dynamic>{};
    data.forEach((k, v) {
      if (v is Timestamp) {
        safeRaw[k] = v.toDate().toIso8601String();
      } else if (v is DateTime) {
        safeRaw[k] = v.toIso8601String();
      } else if (v is FieldValue) {
        // skip
      } else {
        safeRaw[k] = v;
      }
    });

    final model = CachedOrderModel(
      id: docId,
      name: (data['name'] ?? 'No Name').toString(),
      status: (data['status'] ?? 'In Progress').toString(),
      createdAt: data['date'] ?? data['created_at'] ?? DateTime.now(),
      deliveryDate: data['delivery_datetime'] ?? data['delivery_date'],
      createdBy: (data['created_by'] ?? '').toString(),
      priority: (data['priority'] ?? 'High').toString(),
      branch: (data['branch'] ?? branch).toString(),
      assignedTo: data['assigned_to'] as String?,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      rawData: safeRaw,
    );

    if (idx >= 0) {
      list[idx] = model;
    } else {
      list.insert(0, model);
    }

    await saveCachedOrders(branch, list);
  }
}
