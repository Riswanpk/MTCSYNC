import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../Misc/theme_notifier.dart';
import 'tile_viewer/make_call.dart';
import 'tile_viewer/fetch_last_remarks.dart';

class AdminCustomerCallEditPage extends StatefulWidget {
  final Map<String, dynamic> customer;
  final String monthYear;
  final String userEmail;
  final String? userName;
  final bool isCurrentMonth;
  final String currentMonthYear;

  const AdminCustomerCallEditPage({
    super.key,
    required this.customer,
    required this.monthYear,
    required this.userEmail,
    this.userName,
    required this.isCurrentMonth,
    required this.currentMonthYear,
  });

  @override
  State<AdminCustomerCallEditPage> createState() =>
      _AdminCustomerCallEditPageState();
}

class _AdminCustomerCallEditPageState extends State<AdminCustomerCallEditPage> {
  late bool _callMade;
  late TextEditingController _remarksController;
  bool _saving = false;
  bool _loadingLastRemarks = false;
  List<Map<String, String>> _pastRemarks = [];

  @override
  void initState() {
    super.initState();
    _callMade = widget.customer['callMade'] == true;
    _remarksController =
        TextEditingController(text: widget.customer['remarks'] ?? '');
    _loadPastRemarks();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadPastRemarks() async {
    setState(() => _loadingLastRemarks = true);
    try {
      final results = await fetchLastRemarks(customer: widget.customer);
      if (mounted) {
        setState(() {
          _pastRemarks = results;
          _loadingLastRemarks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLastRemarks = false);
    }
  }

  Future<void> _saveCallingDetails() async {
    if (!widget.isCurrentMonth) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
              'Editing call status and remarks is only allowed for the current month (${widget.currentMonthYear}).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(widget.monthYear)
          .collection('users')
          .doc(widget.userEmail.toLowerCase());

      final doc = await docRef.get();
      if (!doc.exists || doc.data()?['customers'] == null) {
        throw Exception(
            'Target document for ${widget.userEmail} does not exist.');
      }

      final List customers = List.from(doc.data()!['customers']);
      final c1 = (widget.customer['contact1'] ?? widget.customer['contact'] ?? '')
          .toString()
          .trim();
      final c2 = (widget.customer['contact2'] ?? '').toString().trim();
      final name = (widget.customer['name'] ?? '').toString().trim();

      int idx = customers.indexWhere((c) {
        if (c is! Map) return false;
        final targetC1 =
            (c['contact1'] ?? c['contact'] ?? '').toString().trim();
        final targetC2 = (c['contact2'] ?? '').toString().trim();
        final targetName = (c['name'] ?? '').toString().trim();

        if (c1.isNotEmpty && (targetC1 == c1 || targetC2 == c1)) return true;
        if (c2.isNotEmpty && (targetC1 == c2 || targetC2 == c2)) return true;
        if (name.isNotEmpty && targetName == name) return true;
        return false;
      });

      if (idx == -1) {
        throw Exception('Customer not found in user target list.');
      }

      final newRemarks = _remarksController.text.trim();
      final updatedCustomer = Map<String, dynamic>.from(customers[idx]);
      updatedCustomer['callMade'] = _callMade;
      updatedCustomer['remarks'] = newRemarks;
      if (_callMade) {
        if (updatedCustomer['callDate'] == null) {
          updatedCustomer['callDate'] = Timestamp.now();
        }
      } else {
        updatedCustomer['callDate'] = null;
      }

      customers[idx] = updatedCustomer;
      await docRef.update({'customers': customers});

      // Update in-memory customer
      widget.customer['callMade'] = _callMade;
      widget.customer['remarks'] = newRemarks;
      widget.customer['callDate'] = updatedCustomer['callDate'];

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content:
                Text('Customer call status and remarks updated successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatCallDate(dynamic callDate) {
    if (callDate == null) return 'No date recorded';
    DateTime date;
    if (callDate is Timestamp) {
      date = callDate.toDate().toLocal();
    } else if (callDate is DateTime) {
      date = callDate.toLocal();
    } else {
      return callDate.toString();
    }
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final minuteStr = date.minute.toString().padLeft(2, '0');
    final hourStr = date.hour.toString().padLeft(2, '0');
    return "${date.day} ${months[date.month - 1]} ${date.year}, $hourStr:$minuteStr";
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark ||
        (themeProvider.themeMode == ThemeMode.system &&
            theme.brightness == Brightness.dark);

    const Color primaryGreen = Color(0xFF005BAC);

    final bgColor = isDark ? const Color(0xFF181A20) : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF23262B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;

    final customerName = widget.customer['name'] ?? 'Unnamed Customer';
    final contact1 =
        widget.customer['contact1'] ?? widget.customer['contact'] ?? '';
    final contact2 = widget.customer['contact2'] ?? '';
    final address = widget.customer['address'] ?? '';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Edit Customer Call Record',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? primaryGreen : const Color(0xFF005BAC),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_saving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Month Notice Banner if not viewing current month
            if (!widget.isCurrentMonth) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Viewing ${widget.monthYear}. Call status and remarks can only be edited for the current month (${widget.currentMonthYear}).',
                        style: TextStyle(
                          color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Customer Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.12),
                        child: const Icon(Icons.person, color: Color(0xFF005BAC)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            if (widget.userName != null || widget.userEmail.isNotEmpty)
                              Text(
                                'Assigned to: ${widget.userName ?? widget.userEmail}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subtitleColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.isCurrentMonth
                              ? const Color(0xFF8CC63F).withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          widget.monthYear,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: widget.isCurrentMonth
                                ? (isDark ? const Color(0xFF8CC63F) : const Color(0xFF4B8B0F))
                                : subtitleColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (contact1.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 18, color: Color(0xFF005BAC)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Contact 1: $contact1',
                            style: TextStyle(color: textColor, fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.call, color: Colors.green),
                          tooltip: 'Call $contact1',
                          onPressed: () => makeCall(
                            context,
                            widget.customer,
                            contact1,
                            contact2.isNotEmpty ? contact2 : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (contact2.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.phone_android,
                            size: 18, color: Color(0xFF005BAC)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Contact 2: $contact2',
                            style: TextStyle(color: textColor, fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.call, color: Colors.green),
                          tooltip: 'Call $contact2',
                          onPressed: () => makeCall(
                            context,
                            widget.customer,
                            contact2,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            address,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Call Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Call Status',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: widget.isCurrentMonth
                              ? () => setState(() => _callMade = true)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _callMade
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : (isDark
                                      ? Colors.grey.shade900
                                      : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _callMade
                                    ? Colors.green
                                    : (isDark
                                        ? Colors.grey.shade700
                                        : Colors.grey.shade300),
                                width: _callMade ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: _callMade
                                      ? Colors.green
                                      : Colors.grey.shade500,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Called',
                                  style: TextStyle(
                                    fontWeight: _callMade
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _callMade
                                        ? Colors.green.shade700
                                        : subtitleColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: widget.isCurrentMonth
                              ? () => setState(() => _callMade = false)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !_callMade
                                  ? Colors.red.withValues(alpha: 0.15)
                                  : (isDark
                                      ? Colors.grey.shade900
                                      : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !_callMade
                                    ? Colors.red
                                    : (isDark
                                        ? Colors.grey.shade700
                                        : Colors.grey.shade300),
                                width: !_callMade ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cancel,
                                  color: !_callMade
                                      ? Colors.red
                                      : Colors.grey.shade500,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Not Called',
                                  style: TextStyle(
                                    fontWeight: !_callMade
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: !_callMade
                                        ? Colors.red.shade700
                                        : subtitleColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_callMade && widget.customer['callDate'] != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          'Recorded call date: ${_formatCallDate(widget.customer['callDate'])}',
                          style: TextStyle(
                            fontSize: 12,
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Remarks Section Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remarks',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _remarksController,
                    enabled: widget.isCurrentMonth && !_saving,
                    maxLines: 4,
                    minLines: 2,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Enter calling remarks...',
                      hintStyle: TextStyle(color: subtitleColor),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E2126)
                          : const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF005BAC),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Past Remarks History (if available)
            if (_loadingLastRemarks)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_pastRemarks.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history,
                            size: 20, color: Color(0xFF005BAC)),
                        const SizedBox(width: 8),
                        Text(
                          'Previous Remarks History',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._pastRemarks.map((entry) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E2126)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry['monthYear'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Color(0xFF005BAC),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry['remarks'] ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Save Button
            if (widget.isCurrentMonth) ...[
              ElevatedButton.icon(
                onPressed: _saving ? null : _saveCallingDetails,
                icon: const Icon(Icons.save),
                label: Text(
                  _saving ? 'Saving...' : 'Save Changes',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
