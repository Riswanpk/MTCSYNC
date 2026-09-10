import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'supersale_admin_booking_report.dart';
import 'supersale_admin_delivery_report.dart';
import 'supersale_admin_full_report.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class SupersaleAdminReportPage extends StatefulWidget {
  const SupersaleAdminReportPage({Key? key}) : super(key: key);

  @override
  State<SupersaleAdminReportPage> createState() => _SupersaleAdminReportPageState();
}

class _SupersaleAdminReportPageState extends State<SupersaleAdminReportPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isGenerating = false;
  bool _isLoadingItems = true;

  List<Map<String, dynamic>> _supersaleList = [];
  String? _selectedDocId;
  String _selectedReportType = 'Booking Report'; // 'Booking Report', 'Delivery Report', 'Full Report'

  @override
  void initState() {
    super.initState();
    _loadSupersaleItems();
  }

  String _formatSimpleDate(dynamic dateField) {
    if (dateField == null) return '';
    DateTime dt;
    if (dateField is Timestamp) {
      dt = dateField.toDate();
    } else if (dateField is String) {
      dt = DateTime.tryParse(dateField) ?? DateTime.now();
    } else {
      return '';
    }
    return DateFormat('dd/MM/yy').format(dt.toLocal());
  }

  Future<void> _loadSupersaleItems() async {
    try {
      final snapshot = await _firestore
          .collection('supersales')
          .orderBy('created_at', descending: true)
          .get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'item': data['item'] as String? ?? 'Unnamed',
          'bookingStart': data['bookingStart'],
          'bookingEnd': data['bookingEnd'],
          'branches': data['branches'],
          'raw': data,
        };
      }).toList();

      setState(() {
        _supersaleList = list;
        if (list.isNotEmpty) {
          _selectedDocId = list.first['id'] as String;
        }
        _isLoadingItems = false;
      });
    } catch (e) {
      debugPrint('Error loading supersale items: $e');
      setState(() {
        _isLoadingItems = false;
      });
    }
  }

  Future<void> _generateReport() async {
    if (_selectedDocId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a supersale first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedSale = _supersaleList.firstWhere(
      (element) => element['id'] == _selectedDocId,
      orElse: () => {},
    );

    if (selectedSale.isEmpty) return;

    final String selectedItem = selectedSale['item'] as String;
    final List<String> branches = List<String>.from(selectedSale['branches'] ?? []);

    setState(() => _isGenerating = true);
    
    try {
      final List<String> fallbackBranches = [
        'BGR', 'CBE', 'CHN', 'CLT', 'EKM', 'JBL', 'KKM', 'KSD',
        'KTM', 'PKD', 'PKT', 'PMN', 'TRR', 'TSR', 'TLY', 'TVM',
        'UDP', 'VDK', 'WND', 'PKTR', 'PLA', 'PMNA'
      ];
      List<String> activeBranches = List<String>.from(branches);
      if (activeBranches.isEmpty || activeBranches.contains('all')) {
        activeBranches = fallbackBranches;
      }

      if (_selectedReportType == 'Booking Report') {
        await generateBookingReport(
          selectedItem: selectedItem,
          activeBranches: activeBranches,
          adminPostingId: _selectedDocId,
        );
      } else if (_selectedReportType == 'Delivery Report') {
        await generateDeliveryReport(
          selectedItem: selectedItem,
          activeBranches: activeBranches,
          adminPostingId: _selectedDocId,
        );
      } else {
        await generateFullReport(
          selectedItem: selectedItem,
          activeBranches: activeBranches,
          adminPostingId: _selectedDocId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_selectedReportType generated successfully! Opening...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generating report: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Supersale Reports',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: _isLoadingItems
          ? const Center(child: CircularProgressIndicator(color: primaryBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Icon(
                      Icons.analytics_rounded,
                      size: 80,
                      color: primaryGreen.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Generate Excel Report',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Download detailed bookings or delivery reports summary by branch.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Supersale Selection Card
                  Text(
                    'Select Supersale Campaign',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.grey[200]!,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedDocId,
                        hint: const Text('Select a Supersale Campaign'),
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: primaryBlue, size: 26),
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        itemHeight: null, // dynamic height for multi-line items
                        items: _supersaleList.map((sale) {
                          final String docId = sale['id'];
                          final String itemName = sale['item'];
                          final String startStr = _formatSimpleDate(sale['bookingStart']);
                          final String endStr = _formatSimpleDate(sale['bookingEnd']);
                          final List<dynamic> branches = sale['branches'] ?? [];

                          return DropdownMenuItem<String>(
                            value: docId,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: primaryBlue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.flash_on_rounded, size: 16, color: primaryBlue),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          itemName,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ),
                                      if (startStr.isNotEmpty && endStr.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: primaryGreen.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$startStr - $endStr',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: primaryGreen,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (branches.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const SizedBox(width: 32),
                                        Icon(Icons.location_on_outlined, size: 12, color: Colors.grey[500]),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            branches.contains('all')
                                                ? 'All Branches'
                                                : 'Branches: ${branches.take(4).join(", ")}${branches.length > 4 ? " +${branches.length - 4}" : ""}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.white54 : Colors.black54,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedDocId = val;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Report Type Selector
                  Text(
                    'Report Format Type',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildReportTypeOption(
                        title: 'Booking',
                        subtitle: 'Summary',
                        icon: Icons.receipt_long_rounded,
                        value: 'Booking Report',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildReportTypeOption(
                        title: 'Delivery',
                        subtitle: 'Status',
                        icon: Icons.local_shipping_rounded,
                        value: 'Delivery Report',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildReportTypeOption(
                        title: 'Full Data',
                        subtitle: 'Detailed',
                        icon: Icons.table_chart_rounded,
                        value: 'Full Report',
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generateReport,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        _isGenerating ? 'Generating...' : 'Download Report',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildReportTypeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required bool isDark,
  }) {
    final bool isSelected = _selectedReportType == value;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedReportType = value;
            });
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryBlue.withOpacity(0.12)
                  : (isDark ? const Color(0xFF1E293B) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? primaryBlue
                    : (isDark ? Colors.white12 : Colors.grey[200]!),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected ? primaryBlue.withOpacity(0.15) : Colors.black.withOpacity(0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isSelected ? primaryBlue : (isDark ? Colors.white60 : Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? primaryBlue : (isDark ? Colors.white : Colors.black87),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected
                        ? primaryBlue.withOpacity(0.8)
                        : (isDark ? Colors.white38 : Colors.grey[500]),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
