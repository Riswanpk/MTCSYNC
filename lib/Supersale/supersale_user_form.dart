import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import '../Misc/notification_permission_service.dart';
import '../Navigation/user_cache_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class SupersaleUserFormPage extends StatefulWidget {
  final QueryDocumentSnapshot? bookingDoc; // Present in edit mode
  final bool isSpotSale;

  const SupersaleUserFormPage({
    Key? key,
    this.bookingDoc,
    this.isSpotSale = false,
  }) : super(key: key);

  @override
  State<SupersaleUserFormPage> createState() => _SupersaleUserFormPageState();
}

class _SupersaleUserFormPageState extends State<SupersaleUserFormPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _advanceController = TextEditingController();

  List<QueryDocumentSnapshot> _activeAdminPostings = [];
  QueryDocumentSnapshot? _selectedPosting;
  String? _userBranch;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSpotSale = false;

  // Delivery reminder timestamp for normal bookings
  DateTime? _deliveryReminderDateTime;

  // Local state variables representing the selected item properties
  String? _itemName;
  Timestamp? _bookingStart;
  Timestamp? _bookingEnd;
  Timestamp? _deliveryStart;
  Timestamp? _deliveryEnd;

  bool get _isEditMode => widget.bookingDoc != null;

  @override
  void initState() {
    super.initState();
    _isSpotSale = widget.isSpotSale;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      _userBranch = cache.branch;

      if (_userBranch == null || _userBranch!.isEmpty) {
        throw Exception('User branch not found. Cannot load supersale options.');
      }

      if (_isEditMode) {
        final data = widget.bookingDoc!.data() as Map<String, dynamic>;
        _isSpotSale = data['isSpotSale'] == true || data['saleType'] == 'spot_sale';
        _customerController.text = data['customerName'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _quantityController.text = (data['quantity'] ?? '').toString();
        _rateController.text = (data['rate'] ?? '').toString();
        if (_isSpotSale) {
          _advanceController.text = '0';
        } else {
          _advanceController.text = (data['advance'] ?? '').toString();
        }

        _itemName = widget.bookingDoc!.reference.parent.id; // subcollection name is item name
        _bookingStart = data['bookingStart'] as Timestamp?;
        _bookingEnd = data['bookingEnd'] as Timestamp?;
        if (_isSpotSale) {
          _deliveryStart = _bookingStart;
          _deliveryEnd = _bookingEnd;
        } else {
          _deliveryStart = data['deliveryStart'] as Timestamp?;
          _deliveryEnd = data['deliveryEnd'] as Timestamp?;
        }

        if (data['deliveryReminder'] != null && data['deliveryReminder'] is Timestamp) {
          _deliveryReminderDateTime = (data['deliveryReminder'] as Timestamp).toDate();
        }
      } else {
        if (_isSpotSale) {
          _advanceController.text = '0';
        }
        // Create mode: Fetch active postings
        final now = DateTime.now();
        final snap = await FirebaseFirestore.instance
            .collection('supersales')
            .orderBy('created_at', descending: true)
            .get();

        _activeAdminPostings = snap.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final List<dynamic> branches = data['branches'] ?? [];
          final Timestamp? start = data['bookingStart'];
          final Timestamp? end = data['bookingEnd'];
          if (start == null || end == null) return false;

          final startTime = start.toDate();
          final endTime = end.toDate();

          final isBranchEligible = branches.contains(_userBranch) || branches.contains('all');
          final isTimeEligible = now.isAfter(startTime) && now.isBefore(endTime);

          return isBranchEligible && isTimeEligible;
        }).toList();

        if (_activeAdminPostings.isNotEmpty) {
          _updateSelectedPosting(_activeAdminPostings.first);
        }
      }
    } catch (e) {
      debugPrint('Error loading form data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _updateSelectedPosting(QueryDocumentSnapshot posting) {
    _selectedPosting = posting;
    final data = posting.data() as Map<String, dynamic>;
    _itemName = data['item'];
    _bookingStart = data['bookingStart'] as Timestamp?;
    _bookingEnd = data['bookingEnd'] as Timestamp?;
    if (_isSpotSale) {
      _deliveryStart = _bookingStart;
      _deliveryEnd = _bookingEnd;
      _advanceController.text = '0';
    } else {
      _deliveryStart = data['deliveryStart'] as Timestamp?;
      _deliveryEnd = data['deliveryEnd'] as Timestamp?;
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _phoneController.dispose();
    _quantityController.dispose();
    _rateController.dispose();
    _advanceController.dispose();
    super.dispose();
  }

  String _formatDateRange(Timestamp? start, Timestamp? end) {
    if (start == null || end == null) return 'N/A';
    final DateFormat formatter = DateFormat('dd MMM yyyy HH:mm');
    return '${formatter.format(start.toDate().toLocal())} - ${formatter.format(end.toDate().toLocal())}';
  }

  Future<void> _scheduleDeliveryReminder(String docId) async {
    if (_deliveryReminderDateTime == null) return;
    try {
      final notifId = docId.hashCode & 0x7FFFFFFF;
      final tz = await AwesomeNotifications().getLocalTimeZoneIdentifier();
      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: notifId,
          channelKey: 'delivery_reminder_channel',
          title: 'Delivery Reminder',
          body: 'Delivery reminder for customer ${_customerController.text.trim()} (${_itemName ?? ""})',
          notificationLayout: NotificationLayout.Default,
          customSound: 'resource://raw/delivery_reminder',
          payload: {
            'type': 'supersale_delivery_reminder',
            'docId': docId,
            'branch': _userBranch ?? '',
            'item': _itemName ?? '',
          },
        ),
        schedule: NotificationCalendar(
          year: _deliveryReminderDateTime!.year,
          month: _deliveryReminderDateTime!.month,
          day: _deliveryReminderDateTime!.day,
          hour: _deliveryReminderDateTime!.hour,
          minute: _deliveryReminderDateTime!.minute,
          second: 0,
          millisecond: 0,
          timeZone: tz,
          repeats: false,
        ),
      );
    } catch (e) {
      debugPrint('Error creating delivery reminder notification: $e');
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isEditMode && _selectedPosting == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active Supersale item selected')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No authenticated user found');

      final advanceValue = _isSpotSale
          ? 0.0
          : (double.tryParse(_advanceController.text.trim()) ?? 0.0);

      if (_isEditMode) {
        // Edit Mode: update existing document fields
        final updateData = <String, dynamic>{
          'customerName': _customerController.text.trim(),
          'phone': _phoneController.text.trim(),
          'quantity': int.parse(_quantityController.text.trim()),
          'rate': double.parse(_rateController.text.trim()),
          'advance': advanceValue,
        };

        if (!_isSpotSale && _deliveryReminderDateTime != null) {
          updateData['deliveryReminder'] = Timestamp.fromDate(_deliveryReminderDateTime!);
        }

        await widget.bookingDoc!.reference.update(updateData);

        if (!_isSpotSale &&
            _deliveryReminderDateTime != null &&
            _deliveryReminderDateTime!.isAfter(DateTime.now())) {
          await _scheduleDeliveryReminder(widget.bookingDoc!.reference.id);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Entry updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        // Create Mode: save new entry
        final cache = UserCacheService.instance;
        await cache.ensureLoaded();

        final newEntry = <String, dynamic>{
          'bookingStart': _bookingStart,
          'bookingEnd': _bookingEnd,
          'deliveryStart': _isSpotSale ? _bookingStart : _deliveryStart,
          'deliveryEnd': _isSpotSale ? _bookingEnd : _deliveryEnd,
          'customerName': _customerController.text.trim(),
          'phone': _phoneController.text.trim(),
          'quantity': int.parse(_quantityController.text.trim()),
          'rate': double.parse(_rateController.text.trim()),
          'advance': advanceValue,
          'userId': user.uid,
          'email': cache.email ?? user.email,
          'username': cache.username ?? 'User',
          'created_at': FieldValue.serverTimestamp(),
          'adminPostingId': _selectedPosting!.id,
          'status': _isSpotSale ? 'delivered' : 'pending',
          'isSpotSale': _isSpotSale,
          'saleType': _isSpotSale ? 'spot_sale' : 'booking',
          if (_isSpotSale) 'billedPhone': _phoneController.text.trim(),
          if (!_isSpotSale && _deliveryReminderDateTime != null)
            'deliveryReminder': Timestamp.fromDate(_deliveryReminderDateTime!),
        };

        final docRef = await FirebaseFirestore.instance
            .collection('supersale_user_entries')
            .doc(_userBranch)
            .collection(_itemName!)
            .add(newEntry);

        if (!_isSpotSale &&
            _deliveryReminderDateTime != null &&
            _deliveryReminderDateTime!.isAfter(DateTime.now())) {
          await _scheduleDeliveryReminder(docRef.id);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isSpotSale
                    ? 'Spot-sale entry submitted and marked delivered'
                    : 'Supersale booking submitted successfully',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save entry: $e'),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    final titleText = _isEditMode
        ? 'Edit Entry'
        : (_isSpotSale ? 'Add Spot-sale' : 'Add Supersale Booking');

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
        appBar: AppBar(
          title: Text(titleText),
          backgroundColor: primaryBlue,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isEditMode && _activeAdminPostings.isEmpty) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
        appBar: AppBar(
          title: Text(titleText),
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_clock_rounded,
                  size: 64,
                  color: Colors.red.withOpacity(0.6),
                ),
                const SizedBox(height: 16),
                Text(
                  'Booking Closed',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'There are no active Supersale items currently open for booking in your branch ($_userBranch) at this time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          titleText,
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
                    // Spot-sale Banner indicator
                    if (_isSpotSale)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: primaryGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: primaryGreen, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.flash_on_rounded, color: primaryGreen, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Spot-sale Mode: Advance amount disabled, delivery date same as booking date, auto-marked as Delivered upon submit.',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Item Selection
                    Text(
                      'Item',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _isEditMode
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(
                              _itemName ?? 'Unnamed Item',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? Colors.white24 : Colors.grey[300]!,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<QueryDocumentSnapshot>(
                                value: _selectedPosting,
                                isExpanded: true,
                                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 16,
                                ),
                                items: _activeAdminPostings.map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  return DropdownMenuItem<QueryDocumentSnapshot>(
                                    value: doc,
                                    child: Text(data['item'] ?? 'Unnamed Item'),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _updateSelectedPosting(val);
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                    const SizedBox(height: 20),

                    // Read-only Booking Interval Display
                    Text(
                      'Booking Interval',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.grey[300]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range_rounded, color: primaryGreen, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatDateRange(_bookingStart, _bookingEnd),
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Read-only Delivery Date Period Display
                    Text(
                      _isSpotSale ? 'Delivery Date Period (Same as Booking Date)' : 'Delivery Date Period',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.grey[300]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_shipping_rounded, color: primaryGreen, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatDateRange(_deliveryStart, _deliveryEnd),
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Customer Name
                    Text(
                      'Customer Name',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _customerController,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: _buildInputDecoration(isDark, 'Enter customer name'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter customer name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Phone Number / Billed Phone Number
                    Text(
                      _isSpotSale ? 'Billed Phone Number' : 'Phone Number',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: _buildInputDecoration(
                        isDark,
                        _isSpotSale ? 'Enter 10-digit billed phone number' : 'Enter 10-digit phone number',
                      ).copyWith(
                        counterText: '',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return _isSpotSale ? 'Please enter billed phone number' : 'Please enter phone number';
                        }
                        if (value.trim().length != 10) {
                          return 'Phone number must be exactly 10 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Quantity
                    Text(
                      'Quantity',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: _buildInputDecoration(isDark, 'Enter quantity'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter quantity';
                        }
                        if (int.tryParse(value) == null) {
                          return 'Please enter a valid integer';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Rate
                    Text(
                      'Rate',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _rateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: _buildInputDecoration(isDark, 'Enter rate'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter rate';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid rate';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Advance Paid (Disabled if Spot-sale)
                    Text(
                      _isSpotSale ? 'Advance Paid (Disabled for Spot-sale)' : 'Advance Paid',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _isSpotSale
                            ? (isDark ? Colors.white38 : Colors.black38)
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _advanceController,
                      enabled: !_isSpotSale,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        color: _isSpotSale
                            ? (isDark ? Colors.white38 : Colors.black38)
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                      decoration: _buildInputDecoration(
                        isDark,
                        _isSpotSale ? 'Disabled (Spot-sale)' : 'Enter advance amount',
                      ).copyWith(
                        fillColor: _isSpotSale
                            ? (isDark ? const Color(0xFF0F172A) : Colors.grey[200])
                            : (isDark ? const Color(0xFF1E293B) : Colors.white),
                      ),
                      validator: (value) {
                        if (_isSpotSale) return null;
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter advance amount';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Delivery Reminder field (Only for normal booking)
                    if (!_isSpotSale) ...[
                      _buildDeliveryReminderPicker(isDark, textTheme),
                      const SizedBox(height: 20),
                    ],

                    const SizedBox(height: 16),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          _isEditMode
                              ? 'Update Entry'
                              : (_isSpotSale ? 'Submit Spot-sale' : 'Submit Booking'),
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

  Widget _buildDeliveryReminderPicker(bool isDark, TextTheme textTheme) {
    final DateFormat formatter = DateFormat('dd MMM yyyy, hh:mm a');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery Reminder (Optional)',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final initialDate = _deliveryStart != null && _deliveryStart!.toDate().isAfter(now)
                ? _deliveryStart!.toDate()
                : now;
            final pickedDate = await showDatePicker(
              context: context,
              initialDate: _deliveryReminderDateTime ?? initialDate,
              firstDate: now.subtract(const Duration(days: 1)),
              lastDate: now.add(const Duration(days: 365)),
            );

            if (pickedDate != null && mounted) {
              final pickedTime = await showTimePicker(
                context: context,
                initialTime: _deliveryReminderDateTime != null
                    ? TimeOfDay.fromDateTime(_deliveryReminderDateTime!)
                    : const TimeOfDay(hour: 9, minute: 0),
              );

              if (pickedTime != null) {
                setState(() {
                  _deliveryReminderDateTime = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  );
                });
              }
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white24 : Colors.grey[300]!,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _deliveryReminderDateTime != null
                      ? Icons.notifications_active_rounded
                      : Icons.alarm_add_rounded,
                  color: _deliveryReminderDateTime != null ? primaryGreen : Colors.grey,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _deliveryReminderDateTime != null
                        ? formatter.format(_deliveryReminderDateTime!)
                        : 'Select date & time for delivery reminder',
                    style: TextStyle(
                      color: _deliveryReminderDateTime != null
                          ? (isDark ? Colors.white : Colors.black87)
                          : Colors.grey,
                      fontSize: 15,
                      fontWeight: _deliveryReminderDateTime != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                if (_deliveryReminderDateTime != null)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 20, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _deliveryReminderDateTime = null;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(bool isDark, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
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
    );
  }
}
