import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../Navigation/user_cache_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class SupersaleUserFormPage extends StatefulWidget {
  final QueryDocumentSnapshot? bookingDoc; // Present in edit mode

  const SupersaleUserFormPage({Key? key, this.bookingDoc}) : super(key: key);

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
        _customerController.text = data['customerName'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _quantityController.text = (data['quantity'] ?? '').toString();
        _rateController.text = (data['rate'] ?? '').toString();
        _advanceController.text = (data['advance'] ?? '').toString();

        _itemName = widget.bookingDoc!.reference.parent.id; // subcollection name is item name
        _bookingStart = data['bookingStart'] as Timestamp?;
        _bookingEnd = data['bookingEnd'] as Timestamp?;
        _deliveryStart = data['deliveryStart'] as Timestamp?;
        _deliveryEnd = data['deliveryEnd'] as Timestamp?;
      } else {
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
    _deliveryStart = data['deliveryStart'] as Timestamp?;
    _deliveryEnd = data['deliveryEnd'] as Timestamp?;
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

      if (_isEditMode) {
        // Edit Mode: update existing document fields only
        await widget.bookingDoc!.reference.update({
          'customerName': _customerController.text.trim(),
          'phone': _phoneController.text.trim(),
          'quantity': int.parse(_quantityController.text.trim()),
          'rate': double.parse(_rateController.text.trim()),
          'advance': double.parse(_advanceController.text.trim()),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking entry updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        // Create Mode: save new entry
        final cache = UserCacheService.instance;
        await cache.ensureLoaded();

        final newEntry = {
          'bookingStart': _bookingStart,
          'bookingEnd': _bookingEnd,
          'deliveryStart': _deliveryStart,
          'deliveryEnd': _deliveryEnd,
          'customerName': _customerController.text.trim(),
          'phone': _phoneController.text.trim(),
          'quantity': int.parse(_quantityController.text.trim()),
          'rate': double.parse(_rateController.text.trim()),
          'advance': double.parse(_advanceController.text.trim()),
          'userId': user.uid,
          'email': cache.email ?? user.email,
          'username': cache.username ?? 'User',
          'created_at': FieldValue.serverTimestamp(),
          'adminPostingId': _selectedPosting!.id,
          'status': 'pending',
        };

        await FirebaseFirestore.instance
            .collection('supersale_user_entries')
            .doc(_userBranch)
            .collection(_itemName!)
            .add(newEntry);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Supersale entry submitted successfully'),
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
        appBar: AppBar(
          title: Text(_isEditMode ? 'Edit Booking' : 'Add Supersale Bookings'),
          backgroundColor: primaryBlue,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isEditMode && _activeAdminPostings.isEmpty) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
        appBar: AppBar(
          title: const Text('Add Supersale Bookings'),
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
          _isEditMode ? 'Edit Booking' : 'Supersale Booking',
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
                    // Item Selection (Dropdown in create mode, read-only field in edit mode)
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
                      'Delivery Date Period',
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

                    // Phone Number
                    Text(
                      'Phone Number',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: _buildInputDecoration(isDark, 'Enter phone number'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter phone number';
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

                    // Advance
                    Text(
                      'Advance Paid',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _advanceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: _buildInputDecoration(isDark, 'Enter advance amount'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter advance amount';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 36),

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
                          _isEditMode ? 'Update Booking' : 'Submit Booking',
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
