import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  DateTimeRange? _deliveryRange;

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
      _deliveryRange = widget.deliveryRange;
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
      });
    }
  }

  Future<void> _selectDeliveryRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDateRange: _deliveryRange,
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
        _deliveryRange = picked;
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

    if (_deliveryRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Delivery Date Range')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No authenticated user found');

      final data = {
        'item': _itemController.text.trim(),
        'bookingStart': Timestamp.fromDate(_bookingRange!.start),
        'bookingEnd': Timestamp.fromDate(_bookingRange!.end),
        'deliveryStart': Timestamp.fromDate(_deliveryRange!.start),
        'deliveryEnd': Timestamp.fromDate(_deliveryRange!.end),
        'branches': _selectedBranches,
      };

      if (widget.docId == null) {
        data['created_by'] = user.uid;
        data['created_at'] = FieldValue.serverTimestamp();
        data['status'] = 'active';
        await FirebaseFirestore.instance.collection('supersales').add(data);
      } else {
        await FirebaseFirestore.instance.collection('supersales').doc(widget.docId).update(data);
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

  String _formatDateRange(DateTimeRange? range) {
    if (range == null) return 'Select Date Range';
    final DateFormat formatter = DateFormat('dd MMM yyyy');
    return '${formatter.format(range.start)} - ${formatter.format(range.end)}';
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
                                _formatDateRange(_bookingRange),
                                style: TextStyle(
                                  color: _bookingRange == null
                                      ? Colors.grey
                                      : (isDark ? Colors.white : Colors.black87),
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

                    // Delivery Date Range
                    Text(
                      'Delivery Date Range',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selectDeliveryRange,
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
                            const Icon(Icons.local_shipping_rounded, color: primaryGreen),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _formatDateRange(_deliveryRange),
                                style: TextStyle(
                                  color: _deliveryRange == null
                                      ? Colors.grey
                                      : (isDark ? Colors.white : Colors.black87),
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
