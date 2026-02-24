import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz_pkg;

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class SyncHeadTodosPage extends StatefulWidget {
  const SyncHeadTodosPage({super.key});

  @override
  State<SyncHeadTodosPage> createState() => _SyncHeadTodosPageState();
}

class _SyncHeadTodosPageState extends State<SyncHeadTodosPage> {
  List<String> _branches = [];
  String? _selectedBranch;
  late DateTime _selectedDate;
  bool _loading = false;
  bool _branchesLoading = true;

  // List of { username, role, email, todos: List<Map> }
  List<Map<String, dynamic>> _userTodos = [];

  static late tz_pkg.Location _istLocation;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _istLocation = tz_pkg.getLocation('Asia/Kolkata');
    _selectedDate = _defaultDate();
    _fetchBranches();
  }

  /// Default date: the "window endpoint" in IST.
  /// After 12 PM IST → today; before 12 PM IST → today (window is yesterday-today).
  DateTime _defaultDate() {
    final nowIST = tz_pkg.TZDateTime.now(_istLocation);
    return DateTime(nowIST.year, nowIST.month, nowIST.day);
  }

  /// Returns (windowStart, windowEnd) for selected date D.
  /// Window = (D-1) 12:00 IST → D 12:00 IST.
  /// Monday special case: Saturday 12:00 IST → Monday 12:00 IST.
  (DateTime, DateTime) _getWindow(DateTime date) {
    final ist = _istLocation;
    final dayIST =
        tz_pkg.TZDateTime(ist, date.year, date.month, date.day);

    DateTime windowStart;
    if (dayIST.weekday == DateTime.monday) {
      final saturday = dayIST.subtract(const Duration(days: 2));
      windowStart = tz_pkg.TZDateTime(
          ist, saturday.year, saturday.month, saturday.day, 12);
    } else {
      final prev = dayIST.subtract(const Duration(days: 1));
      windowStart =
          tz_pkg.TZDateTime(ist, prev.year, prev.month, prev.day, 12);
    }
    final windowEnd = tz_pkg.TZDateTime(
        ist, dayIST.year, dayIST.month, dayIST.day, 12);

    return (windowStart, windowEnd);
  }

  Future<void> _fetchBranches() async {
    final snap =
        await FirebaseFirestore.instance.collection('users').get();
    final branches = snap.docs
        .map((d) => d.data()['branch'] as String?)
        .where((b) => b != null && b.isNotEmpty)
        .toSet()
        .cast<String>()
        .toList()
      ..sort();
    setState(() {
      _branches = branches;
      // No auto-selection — user must pick a branch
      _selectedBranch = null;
      _branchesLoading = false;
    });
  }

  Future<void> _fetchTodos() async {
    if (_selectedBranch == null) return;
    setState(() => _loading = true);

    final (windowStart, windowEnd) = _getWindow(_selectedDate);

    // Fetch all users in selected branch
    final usersSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: _selectedBranch)
        .get();

    final users = usersSnap.docs
        .map((d) {
          final data = d.data();
          return {
            'uid': d.id,
            'username': data['username'] ?? 'Unknown',
            'email': data['email'] ?? '',
            'role': data['role'] ?? 'sales',
          };
        })
        .where(
            (u) => u['role'] != 'admin' && u['role'] != 'sync_head')
        .toList();

    // Fetch todos for each user in parallel
    final List<Map<String, dynamic>> userTodos = [];
    await Future.wait(users.map((user) async {
      final email = user['email'] as String;
      if (email.isEmpty) return;

      final snap = await FirebaseFirestore.instance
          .collection('todo')
          .where('email', isEqualTo: email)
          .where('timestamp',
              isGreaterThanOrEqualTo:
                  Timestamp.fromDate(windowStart))
          .where('timestamp',
              isLessThan: Timestamp.fromDate(windowEnd))
          .orderBy('timestamp', descending: false)
          .get();

      userTodos.add({
        'username': user['username'],
        'role': user['role'],
        'email': email,
        'todos': snap.docs
            .map((d) => {...d.data(), 'id': d.id})
            .toList(),
      });
    }));

    // Sort: managers first, then sales; alphabetically within each group
    userTodos.sort((a, b) {
      final roleA = a['role'] as String;
      final roleB = b['role'] as String;
      if (roleA != roleB) {
        if (roleA == 'manager') return -1;
        if (roleB == 'manager') return 1;
      }
      return (a['username'] as String)
          .compareTo(b['username'] as String);
    });

    setState(() {
      _userTodos = userTodos;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023, 1, 1),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primaryGreen,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _fetchTodos();
    }
  }

  String _formatWindowLabel() {
    final (start, end) = _getWindow(_selectedDate);
    final fmt = DateFormat('dd MMM, hh:mm a');
    return '${fmt.format(start)}  →  ${fmt.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Todos Report'),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Filters ──────────────────────────────────────────────────
          Container(
            color: isDark ? const Color(0xFF0D2137) : Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Date picker
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _primaryGreen.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(10),
                      color: isDark
                          ? const Color(0xFF162236)
                          : const Color(0xFFF3FBF0),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            color: _primaryGreen, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('dd MMM yyyy')
                                    .format(_selectedDate),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : _primaryGreen,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                _formatWindowLabel(),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_drop_down_rounded,
                            color: isDark
                                ? Colors.white54
                                : _primaryGreen),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Branch dropdown
                _branchesLoading
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<String>(
                        value: _selectedBranch,
                        decoration: InputDecoration(
                          labelText: 'Branch',
                          labelStyle: const TextStyle(
                              color: _primaryGreen),
                          prefixIcon: const Icon(
                              Icons.location_city_rounded,
                              color: _primaryGreen,
                              size: 20),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: _primaryGreen
                                    .withOpacity(0.4)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: _primaryGreen
                                    .withOpacity(0.4)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: _primaryGreen,
                                width: 1.5),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF162236)
                              : const Color(0xFFF3FBF0),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                        ),
                        dropdownColor: isDark
                            ? const Color(0xFF162236)
                            : Colors.white,
                        style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : Colors.black87,
                            fontSize: 14),
                        items: _branches
                            .map((b) => DropdownMenuItem(
                                value: b, child: Text(b)))
                            .toList(),
                        onChanged: (val) {
                          setState(() => _selectedBranch = val);
                          _fetchTodos();
                        },
                      ),
              ],
            ),
          ),

          // ── Content ───────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: _primaryGreen))
                : _userTodos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.checklist_rounded,
                                size: 56,
                                color: isDark
                                    ? Colors.white24
                                    : Colors.black26),
                            const SizedBox(height: 12),
                            Text(
                              _selectedBranch == null
                                  ? 'Select a branch to view todos'
                                  : 'No users found in this branch',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white38
                                    : Colors.black38,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _userTodos.length,
                        itemBuilder: (ctx, i) {
                          final entry = _userTodos[i];
                          final todos =
                              (entry['todos'] as List<dynamic>)
                                  .cast<Map<String, dynamic>>();
                          return _UserTodoSection(
                            username:
                                entry['username'] as String,
                            role: entry['role'] as String,
                            todos: todos,
                            isDark: isDark,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Per-user section ──────────────────────────────────────────────────────────

class _UserTodoSection extends StatelessWidget {
  final String username;
  final String role;
  final List<Map<String, dynamic>> todos;
  final bool isDark;

  const _UserTodoSection({
    required this.username,
    required this.role,
    required this.todos,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D2137) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Username header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _primaryGreen
                  .withOpacity(isDark ? 0.15 : 0.08),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      _primaryGreen.withOpacity(0.2),
                  radius: 18,
                  child: Text(
                    username.isNotEmpty
                        ? username[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: _primaryGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      Text(
                        role.isNotEmpty
                            ? role[0].toUpperCase() +
                                role.substring(1)
                            : role,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white54
                              : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: todos.isEmpty
                        ? Colors.red.withOpacity(0.15)
                        : _primaryGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${todos.length} task${todos.length != 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: todos.isEmpty
                          ? Colors.red
                          : _primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Todos list or empty message
          if (todos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No tasks created in this window',
                style: TextStyle(
                  color: isDark
                      ? Colors.white38
                      : Colors.black38,
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                ),
              ),
            )
          else
            ...todos.asMap().entries.map((entry) {
              final idx = entry.key;
              final todo = entry.value;
              final isLast = idx == todos.length - 1;
              final status = (todo['status'] ?? 'pending') as String;
              final priority = (todo['priority'] ?? '') as String;
              final isDone =
                  status == 'done' || status == 'completed';

              return Container(
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(
                            color: isDark
                                ? Colors.white12
                                : Colors.black
                                    .withOpacity(0.06),
                          ),
                        ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  leading: Icon(
                    isDone
                        ? Icons.check_circle_rounded
                        : Icons
                            .radio_button_unchecked_rounded,
                    color:
                        isDone ? _primaryGreen : Colors.grey,
                    size: 22,
                  ),
                  title: Text(
                    (todo['title'] ?? 'Untitled') as String,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white
                          : Colors.black87,
                      decoration: isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (todo['description'] != null &&
                          (todo['description'] as String).isNotEmpty)
                        Text(
                          todo['description'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white54
                                : Colors.black45,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (todo['timestamp'] != null)
                        Text(
                          () {
                            final ts = todo['timestamp'];
                            DateTime? dt;
                            if (ts is Timestamp) dt = ts.toDate();
                            if (dt == null) return '';
                            return DateFormat('MMM dd, hh:mm a')
                                .format(dt)
                                .toUpperCase();
                          }(),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white38
                                : Colors.black38,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  trailing: priority.isNotEmpty
                      ? _PriorityBadge(priority: priority)
                      : null,
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Priority badge ────────────────────────────────────────────────────────────

class _PriorityBadge extends StatelessWidget {
  final String priority;
  const _PriorityBadge({required this.priority});

  Color get _color {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(
        priority,
        style: TextStyle(
          fontSize: 10,
          color: _color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
