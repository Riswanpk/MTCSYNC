import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local cache entry representation for a user's todo items
class TodoModel {
  final String id;
  final String title;
  final String description;
  final String status;
  final DateTime? reminder;
  final DateTime? timestamp;
  final String? email;
  final String? createdBy;
  final String? assignedByName;
  final String? assignedBy;

  TodoModel({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.reminder,
    this.timestamp,
    this.email,
    this.createdBy,
    this.assignedByName,
    this.assignedBy,
  });

  factory TodoModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return TodoModel(
      id: doc.id,
      title: (data['title'] ?? data['text'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      status: (data['status'] ?? 'pending').toString(),
      reminder: parseDate(data['reminder']),
      timestamp: parseDate(data['timestamp']),
      email: data['email'] as String?,
      createdBy: data['created_by'] as String?,
      assignedByName: data['assigned_by_name'] as String?,
      assignedBy: data['assigned_by'] as String?,
    );
  }

  factory TodoModel.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return TodoModel(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      reminder: parseDate(map['reminder']),
      timestamp: parseDate(map['timestamp']),
      email: map['email'] as String?,
      createdBy: map['created_by'] as String?,
      assignedByName: map['assigned_by_name'] as String?,
      assignedBy: map['assigned_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'reminder': reminder?.toIso8601String(),
      'timestamp': timestamp?.toIso8601String(),
      'email': email,
      'created_by': createdBy,
      'assigned_by_name': assignedByName,
      'assigned_by': assignedBy,
    };
  }

  /// Converts to `Map<String, dynamic>` suitable for TodoListItem widget and details
  Map<String, dynamic> toViewData() {
    return {
      'id': id,
      'docId': id,
      'title': title,
      'text': title,
      'description': description,
      'status': status,
      'reminder': reminder?.toIso8601String(),
      'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : null,
      'email': email,
      'created_by': createdBy,
      'assigned_by_name': assignedByName,
      'assigned_by': assignedBy,
    };
  }
}

/// Service that manages local caching of todos in SharedPreferences
/// per user email. When a user opens the Todo page, cached todos are
/// immediately displayed without hitting Firestore. Users can pull-to-refresh
/// or tap the Reload button to sync fresh data from Firestore.
class TodoCacheService {
  TodoCacheService._();
  static final TodoCacheService instance = TodoCacheService._();

  static const String _prefixKey = 'cached_todos_v1_';

  String _cacheKey(String email) => '$_prefixKey${email.trim().toLowerCase()}';

  /// Load cached todos from SharedPreferences
  Future<List<TodoModel>> getCachedTodos(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(email));
      if (raw == null || raw.isEmpty) return [];

      final list = jsonDecode(raw);
      if (list is List) {
        return list
            .map((e) => TodoModel.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Error reading cached todos: $e');
    }
    return [];
  }

  /// Save list of TodoModels to SharedPreferences
  Future<void> saveCachedTodos(String email, List<TodoModel> todos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(todos.map((t) => t.toMap()).toList());
      await prefs.setString(_cacheKey(email), data);
    } catch (e) {
      debugPrint('Error saving cached todos: $e');
    }
  }

  /// Fetch latest todos from Firestore, cache them locally, and return them.
  Future<List<TodoModel>> fetchAndCacheTodos(String email) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('todo')
          .where('email', isEqualTo: email)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      final todos = snap.docs.map((d) => TodoModel.fromFirestore(d)).toList();
      await saveCachedTodos(email, todos);
      return todos;
    } catch (e) {
      debugPrint('Error fetching and caching todos: $e');
      rethrow;
    }
  }

  /// Update a single todo's status locally
  Future<void> updateLocalTodoStatus(
      String email, String docId, String newStatus) async {
    final todos = await getCachedTodos(email);
    final updated = todos.map((t) {
      if (t.id == docId) {
        return TodoModel(
          id: t.id,
          title: t.title,
          description: t.description,
          status: newStatus,
          reminder: t.reminder,
          timestamp: DateTime.now(),
          email: t.email,
          createdBy: t.createdBy,
          assignedByName: t.assignedByName,
          assignedBy: t.assignedBy,
        );
      }
      return t;
    }).toList();
    await saveCachedTodos(email, updated);
  }

  /// Remove a todo locally
  Future<void> removeLocalTodo(String email, String docId) async {
    final todos = await getCachedTodos(email);
    todos.removeWhere((t) => t.id == docId);
    await saveCachedTodos(email, todos);
  }

  /// Update reminder time locally
  Future<void> updateLocalReminder(
      String email, String docId, DateTime newReminder) async {
    final todos = await getCachedTodos(email);
    final updated = todos.map((t) {
      if (t.id == docId) {
        return TodoModel(
          id: t.id,
          title: t.title,
          description: t.description,
          status: t.status,
          reminder: newReminder,
          timestamp: t.timestamp,
          email: t.email,
          createdBy: t.createdBy,
          assignedByName: t.assignedByName,
          assignedBy: t.assignedBy,
        );
      }
      return t;
    }).toList();
    await saveCachedTodos(email, updated);
  }

  /// Clear all pending todos locally
  Future<void> clearPendingTodos(String email) async {
    final todos = await getCachedTodos(email);
    todos.removeWhere((t) => t.status == 'pending');
    await saveCachedTodos(email, todos);
  }
}
