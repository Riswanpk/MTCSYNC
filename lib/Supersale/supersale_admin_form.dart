import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../Navigation/user_cache_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class SupersaleFormPage extends StatefulWidget {
  final String? docId;
  final String? item;
  final DateTimeRange? bookingRange;
  final DateTimeRange? deliveryRange;
  final List<String>? branches;

  const SupersaleFormPage({
    Key? key,
    this.docId,
    this.item,
    this.bookingRange,
    this.deliveryRange,
    this.branches,
  }) : super(key: key);

  @override
  State<SupersaleFormPage> createState() => _SupersaleFormPageState();
}

class _SupersaleFormPageState extends State<SupersaleFormPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _itemController = TextEditingController();

  DateTimeRange? _bookingRange;
  DateTime? _deliveryEndDate;
  TimeOfDay? _bookingStartTime;
  TimeOfDay? _bookingEndTime;
  TimeOfDay? _deliveryEndTime;

  List<String> _allBranches = [
    'BGR', 'CBE', 'CHN', 'CLT', 'EKM', 'JBL', 'KKM', 'KSD',
    'KTM', 'PKD', 'PKT', 'PMN', 'TRR', 'TSR', 'TLY', 'TVM',
    'UDP', 'VDK', 'WND',
  ];
  final List<String> _selectedBranches = [];
  bool _isLoadingBranches = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
    if (widget.docId != null) {
      _itemController.text = widget.item ?? '';
      _bookingRange = widget.bookingRange;
      if (widget.bookingRange != null) {
        _bookingStartTime = TimeOfDay.fromDateTime(widget.bookingRange!.start);
        _bookingEndTime = TimeOfDay.fromDateTime(widget.bookingRange!.end);
      }
      if (widget.deliveryRange != null) {
        _deliveryEndDate = widget.deliveryRange!.end;
        _deliveryEndTime = TimeOfDay.fromDateTime(widget.deliveryRange!.end);
      }
      if (widget.branches != null) {
        _selectedBranches.addAll(widget.branches!);
      }
    }
  }

  Future<void> _loadBranches() async {
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      final branches = await cache.getBranches();
      if (branches.isNotEmpty) {
        setState(() {
          _allBranches = branches;
        });
      }
    } catch (e) {
      debugPrint('Error loading branches, using fallback: $e');
    } finally {
      setState(() => _isLoadingBranches = false);
    }
  }

  @override
  void dispose() {
    _itemController.dispose();
    super.dispose();
  }

  Future<void> _selectBookingRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDateRange: _bookingRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _bookingRange = picked;
        _bookingStartTime ??= const TimeOfDay(hour: 0, minute: 0);
        _bookingEndTime ??= const TimeOfDay(hour: 23, minute: 59);
      });

      if (mounted) {
        final TimeOfDay? start = await showTimePicker(
          context: context,
          initialTime: _bookingStartTime!,
          helpText: 'SELECT BOOKING START TIME',
        );
        if (start != null) {
          setState(() {
            _bookingStartTime = start;
          });
        }
      }

      if (mounted) {
        final TimeOfDay? end = await showTimePicker(
          context: context,
          initialTime: _bookingEndTime!,
          helpText: 'SELECT BOOKING END TIME',
        );
        if (end != null) {
          setState(() {
            _bookingEndTime = end;
          });
        }
      }
    }
  }

  Future<void> _selectBookingStartTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _bookingStartTime ?? const TimeOfDay(hour: 0, minute: 0),
      helpText: 'SELECT BOOKING START TIME',
    );
    if (picked != null) {
      setState(() {
        _bookingStartTime = picked;
      });
    }
  }

  Future<void> _selectBookingEndTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _bookingEndTime ?? const TimeOfDay(hour: 23, minute: 59),
      helpText: 'SELECT BOOKING END TIME',
    );
    if (picked != null) {
      setState(() {
        _bookingEndTime = picked;
      });
    }
  }

  Future<void> _selectDeliveryEndDate() async {
    final DateTime initial = _deliveryEndDate ?? _bookingRange?.end ?? _bookingRange?.start ?? DateTime.now();
    final DateTime first = _bookingRange?.start ?? DateTime.now().subtract(const Duration(days: 365));

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryGreen,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _deliveryEndDate = picked;
        _deliveryEndTime ??= const TimeOfDay(hour: 23, minute: 59);
      });

      if (mounted) {
        final TimeOfDay? time = await showTimePicker(
          context: context,
          initialTime: _deliveryEndTime!,
          helpText: 'SELECT DELIVERY END TIME',
        );
        if (time != null) {
          setState(() {
            _deliveryEndTime = time;
          });
        }
      }
    }
  }

  Future<void> _selectDeliveryEndTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _deliveryEndTime ?? const TimeOfDay(hour: 23, minute: 59),
      helpText: 'SELECT DELIVERY END TIME',
    );
    if (picked != null) {
      setState(() {
        _deliveryEndTime = picked;
      });
    }
  }

  void _toggleSelectAllBranches(bool? selectAll) {
    setState(() {
      _selectedBranches.clear();
      if (selectAll == true) {
        _selectedBranches.addAll(_allBranches);
      }
    });
  }

  Future<void> _saveSupersale() async {
    if (!_formKey.currentState!.validate()) return;

    if (_bookingRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Booking Interval Range')),
      );
      return;
    }

    if (_selectedBranches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one branch')),
      );
      return;
    }

    if (_deliveryEndDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Delivery End Date')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No authenticated user found');

      // Indian Standard Time offset (+05:30)
      const istOffset = Duration(hours: 5, minutes: 30);

      final bookingStart = DateTime.utc(
        _bookingRange!.start.year,
        _bookingRange!.start.month,
        _bookingRange!.start.day,
        (_bookingStartTime ?? const TimeOfDay(hour: 0, minute: 0)).hour,
        (_bookingStartTime ?? const TimeOfDay(hour: 0, minute: 0)).minute,
      ).subtract(istOffset);

      final bookingEnd = DateTime.utc(
        _bookingRange!.end.year,
        _bookingRange!.end.month,
        _bookingRange!.end.day,
        (_bookingEndTime ?? const TimeOfDay(hour: 23, minute: 59)).hour,
        (_bookingEndTime ?? const TimeOfDay(hour: 23, minute: 59)).minute,
      ).subtract(istOffset);

      // Delivery start always starts same as booking start time and date
      final deliveryStart = bookingStart;

      final deliveryEnd = DateTime.utc(
        _deliveryEndDate!.year,
        _deliveryEndDate!.month,
        _deliveryEndDate!.day,
        (_deliveryEndTime ?? const TimeOfDay(hour: 23, minute: 59)).hour,
        (_deliveryEndTime ?? const TimeOfDay(hour: 23, minute: 59)).minute,
      ).subtract(istOffset);

      final data = {
        'item': _itemController.text.trim(),
        'bookingStart': Timestamp.fromDate(bookingStart),
        'bookingEnd': Timestamp.fromDate(bookingEnd),
        'deliveryStart': Timestamp.fromDate(deliveryStart),
        'deliveryEnd': Timestamp.fromDate(deliveryEnd),
        'branches': _selectedBranches,
      };

      String? targetDocId = widget.docId;
      String notifTitle = '';
      String notifBody = '';
      final List<String> notifBranches = List<String>.from(_selectedBranches);

      final nowUtc = DateTime.now().toUtc();
      final isNewBookingOpen = nowUtc.isAfter(bookingStart) && nowUtc.isBefore(bookingEnd);
      final itemName = _itemController.text.trim();

      if (widget.docId == null) {
        data['created_by'] = user.uid;
        data['created_at'] = FieldValue.serverTimestamp();
        data['status'] = 'active';
        final docRef = await FirebaseFirestore.instance.collection('supersales').add(data);
        targetDocId = docRef.id;

        if (isNewBookingOpen) {
          notifTitle = 'Booking Opened';
          notifBody = 'Supersale booking for "$itemName" is now open for your branch.';
        } else if (nowUtc.isBefore(bookingStart)) {
          notifTitle = 'Booking Scheduled';
          final localStart = bookingStart.toLocal();
          final formattedTime = DateFormat('dd MMM yyyy, hh:mm a').format(localStart);
          notifBody = 'Supersale booking for "$itemName" is scheduled to start on $formattedTime.';
        }
      } else {
        await FirebaseFirestore.instance.collection('supersales').doc(widget.docId).update(data);

        final oldBookingRange = widget.bookingRange;
        if (oldBookingRange != null) {
          final isOldBookingOpen = nowUtc.isAfter(oldBookingRange.start.toUtc()) && nowUtc.isBefore(oldBookingRange.end.toUtc());

          if (isOldBookingOpen && !isNewBookingOpen) {
            notifTitle = 'Booking Closed';
            notifBody = 'Supersale booking for "$itemName" has been closed.';
          } else if (!isOldBookingOpen && isNewBookingOpen) {
            notifTitle = 'Booking Opened';
            notifBody = 'Supersale booking for "$itemName" is now open for your branch.';
          } else if (oldBookingRange.start.toUtc() != bookingStart || oldBookingRange.end.toUtc() != bookingEnd) {
            notifTitle = 'Booking Time Updated';
            final localStart = bookingStart.toLocal();
            final localEnd = bookingEnd.toLocal();
            final formattedStart = DateFormat('dd MMM, hh:mm a').format(localStart);
            final formattedEnd = DateFormat('dd MMM, hh:mm a').format(localEnd);
            notifBody = 'Booking time for "$itemName" has been updated: $formattedStart to $formattedEnd.';
          }
        }
      }

      if (notifTitle.isNotEmpty && targetDocId != null && notifBranches.isNotEmpty) {
        _sendFCMNotifications(
          branches: notifBranches,
          title: notifTitle,
          body: notifBody,
          docId: targetDocId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.docId == null ? 'Supersale created successfully' : 'Supersale updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _sendFCMNotifications({
    required List<String> branches,
    required String title,
    required String body,
    required String docId,
  }) async {
    try {
      final List<String> recipientUids = [];
      for (final branch in branches) {
        final usersSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('branch', isEqualTo: branch)
            .where('role', whereIn: ['sales', 'manager', 'asst_manager'])
            .get();
        for (final doc in usersSnap.docs) {
          if (doc.id.isNotEmpty && !recipientUids.contains(doc.id)) {
            recipientUids.add(doc.id);
          }
        }
      }

      for (final recipientUid in recipientUids) {
        try {
          await FirebaseFunctions.instanceFor(region: 'asia-south1')
              .httpsCallable('sendLeadAssignmentNotification')
              .call(<String, dynamic>{
            'recipientUid': recipientUid,
            'title': title,
            'body': body,
            'notifType': 'supersale_notification',
            'leadDocId': docId,
          });
        } catch (error) {
          debugPrint('FCM Warning: failed to send supersale notification to $recipientUid: $error');
        }
      }
    } catch (e) {
      debugPrint('Error triggering FCM notifications: $e');
    }
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  String _formatDateOnly(DateTime? date) {
    if (date == null) return 'Select End Date';
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _formatDateTimeRange(DateTimeRange? range, TimeOfDay? startTime, TimeOfDay? endTime) {
    if (range == null) return 'Select Date Range';
    final DateFormat formatter = DateFormat('dd MMM yyyy');
    final sTime = _formatTime(startTime ?? const TimeOfDay(hour: 0, minute: 0));
    final eTime = _formatTime(endTime ?? const TimeOfDay(hour: 23, minute: 59));
    return '${formatter.format(range.start)}, $sTime - ${formatter.format(range.end)}, $eTime';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    final allSelected = _selectedBranches.length == _allBranches.length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          widget.docId == null ? 'Create Supersale' : 'Edit Supersale',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item Field
                    Text(
                      'Item Name',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _itemController,
                      readOnly: widget.docId != null,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Enter item or product name',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: widget.docId != null ? (isDark ? Colors.grey[800] : Colors.grey[200]) : (isDark ? const Color(0xFF1E293B) : Colors.white),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.grey[300]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryBlue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter item name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Booking Interval Range
                    Text(
                      'Booking Interval Range',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selectBookingRange,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white24 : Colors.grey[300]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range_rounded, color: primaryBlue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _formatDateTimeRange(_bookingRange, _bookingStartTime, _bookingEndTime),
                                style: TextStyle(
                                  color: _bookingRange == null
                                      ? Colors.grey
                                      : (isDark ? Colors.white : Colors.black87),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_bookingRange != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _selectBookingStartTime,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDark ? Colors.white12 : Colors.grey[300]!,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded, size: 18, color: primaryBlue),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Start Time',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isDark ? Colors.white54 : Colors.black54,
                                            ),
                                          ),
                                          Text(
                                            _formatTime(_bookingStartTime),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: _selectBookingEndTime,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDark ? Colors.white12 : Colors.grey[300]!,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time_filled_rounded, size: 18, color: primaryBlue),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'End Time',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isDark ? Colors.white54 : Colors.black54,
                                            ),
                                          ),
                                          Text(
                                            _formatTime(_bookingEndTime),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Branch Selection
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Branch Selection',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              'Select All',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Checkbox(
                              value: allSelected,
                              activeColor: primaryBlue,
                              onChanged: widget.docId != null ? null : _toggleSelectAllBranches,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _isLoadingBranches
                        ? const Center(child: CircularProgressIndicator())
                        : Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? Colors.white24 : Colors.grey[300]!,
                              ),
                            ),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _allBranches.map((branch) {
                                final isSelected = _selectedBranches.contains(branch);
                                return FilterChip(
                                  label: Text(branch),
                                  selected: isSelected,
                                  selectedColor: primaryBlue,
                                  checkmarkColor: Colors.white,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? Colors.white70 : Colors.black87),
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey[200],
                                  onSelected: widget.docId != null ? null : (selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedBranches.add(branch);
                                      } else {
                                        _selectedBranches.remove(branch);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                    const SizedBox(height: 24),

                    // Delivery Date & Time Range
                    Text(
                      'Delivery Schedule',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Delivery Start Display (Auto-synced from Booking Start)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey[300]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_shipping_rounded, color: primaryGreen),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Delivery Start',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white54 : Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: primaryGreen.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Same as Booking Start',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: primaryGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _bookingRange == null
                                      ? 'Select Booking Start first'
                                      : '${DateFormat('dd MMM yyyy').format(_bookingRange!.start)}, ${_formatTime(_bookingStartTime)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _bookingRange == null
                                        ? Colors.grey
                                        : (isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Delivery End Date & Time Pickers
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _selectDeliveryEndDate,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? Colors.white24 : Colors.grey[300]!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.event_available_rounded, size: 20, color: primaryGreen),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Delivery End Date',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isDark ? Colors.white54 : Colors.black54,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatDateOnly(_deliveryEndDate),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: _deliveryEndDate == null
                                                ? Colors.grey
                                                : (isDark ? Colors.white : Colors.black87),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _selectDeliveryEndTime,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? Colors.white24 : Colors.grey[300]!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time_filled_rounded, size: 20, color: primaryGreen),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Delivery End Time',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isDark ? Colors.white54 : Colors.black54,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatTime(_deliveryEndTime),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saveSupersale,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          widget.docId == null ? 'Submit Schedule' : 'Update Schedule',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
}
