import 'package:flutter/material.dart';
import 'todo_widgets.dart';
import 'todo_cache_service.dart';

/// Builds the pending or completed todo list for a user using local caching.
///
/// If local data exists, it is displayed immediately (0 database reads).
/// Pull-to-refresh fetches the latest updates from Firestore.
class TodoListBody extends StatefulWidget {
  final String status;
  final bool onlySelf;
  final String? userEmail;
  final Future<void> Function(String docId, Map<String, dynamic> data) onToggleStatus;
  final Future<void> Function(String docId) onDelete;
  final Future<void> Function(String docId, DateTime newReminder) onPostpone;
  final Future<String> Function(String email) getUsernameByEmail;
  final String? role;

  const TodoListBody({
    super.key,
    required this.status,
    this.onlySelf = false,
    required this.userEmail,
    required this.onToggleStatus,
    required this.onDelete,
    required this.onPostpone,
    required this.getUsernameByEmail,
    this.role,
  });

  @override
  State<TodoListBody> createState() => TodoListBodyState();
}

class TodoListBodyState extends State<TodoListBody> {
  List<TodoModel> _todos = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void didUpdateWidget(covariant TodoListBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userEmail != widget.userEmail ||
        oldWidget.status != widget.status) {
      _loadInitial();
    }
  }

  /// Initial load: Check local cache first!
  /// If local cache has data, show it immediately without waiting for Firestore.
  /// If cache is empty, fetch from Firestore.
  Future<void> _loadInitial() async {
    final email = widget.userEmail;
    if (email == null || email.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 1. Try reading from local cache
    final cached = await TodoCacheService.instance.getCachedTodos(email);
    if (!mounted) return;

    if (cached.isNotEmpty) {
      setState(() {
        _todos = cached.where((t) => t.status == widget.status).toList();
        _isLoading = false;
        _error = null;
      });
      return;
    }

    // 2. Cache is empty, fetch from Firestore
    await refreshFromDatabase(showSpinner: true);
  }

  /// Refresh from Firestore (called by pull-to-refresh or the top reload button)
  Future<void> refreshFromDatabase({bool showSpinner = false}) async {
    final email = widget.userEmail;
    if (email == null || email.isEmpty) return;

    if (showSpinner && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final fetched = await TodoCacheService.instance.fetchAndCacheTodos(email);
      if (!mounted) return;
      setState(() {
        _todos = fetched.where((t) => t.status == widget.status).toList();
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load todos';
      });
    }
  }

  /// Update local list immediately when parent modifies or deletes a task
  void reloadFromLocalCache() async {
    final email = widget.userEmail;
    if (email == null || !mounted) return;
    final cached = await TodoCacheService.instance.getCachedTodos(email);
    if (!mounted) return;
    setState(() {
      _todos = cached.where((t) => t.status == widget.status).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userEmail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => refreshFromDatabase(showSpinner: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_todos.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => refreshFromDatabase(showSpinner: false),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.status == 'pending'
                        ? Icons.check_circle_outline_rounded
                        : Icons.celebration_rounded,
                    size: 64,
                    color: primaryGreen.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.status == 'pending'
                        ? 'No pending tasks'
                        : 'No completed tasks',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.status == 'pending'
                        ? 'All caught up!'
                        : 'Complete tasks to see them here',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => refreshFromDatabase(showSpinner: false),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: _todos.length,
        itemBuilder: (context, index) {
          final item = _todos[index];
          final data = item.toViewData();

          return TodoListItem(
            docId: item.id,
            data: data,
            onToggleStatus: (docId, d) async {
              await widget.onToggleStatus(docId, d);
              reloadFromLocalCache();
            },
            onDelete: (docId) async {
              await widget.onDelete(docId);
              reloadFromLocalCache();
            },
            onPostpone: (docId, newReminder) async {
              await widget.onPostpone(docId, newReminder);
              reloadFromLocalCache();
            },
            getUsernameByEmail: widget.getUsernameByEmail,
          );
        },
      ),
    );
  }
}
