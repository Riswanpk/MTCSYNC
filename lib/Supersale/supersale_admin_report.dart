import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'supersale_admin_booking_report.dart';
import 'supersale_admin_delivery_report.dart';

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

  List<String> _supersaleItems = [];
  String? _selectedItem;
  String _selectedReportType = 'Booking Report'; // 'Booking Report' or 'Delivery Report'

  @override
  void initState() {
    super.initState();
    _loadSupersaleItems();
  }

  Future<void> _loadSupersaleItems() async {
    try {
      final snapshot = await _firestore.collection('supersales').get();
      final items = snapshot.docs
          .map((doc) => doc.data()['item'] as String? ?? '')
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();
      
      items.sort();

      setState(() {
        _supersaleItems = items;
        if (items.isNotEmpty) {
          _selectedItem = items.first;
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
    if (_selectedItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a supersale item first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);
    
    try {
      // Find the selected supersale doc to get its branches
      final postingSnap = await _firestore
          .collection('supersales')
          .where('item', isEqualTo: _selectedItem)
          .limit(1)
          .get();

      List<String> branches = [];
      if (postingSnap.docs.isNotEmpty) {
        branches = List<String>.from(postingSnap.docs.first.data()['branches'] ?? []);
      }

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
          selectedItem: _selectedItem!,
          activeBranches: activeBranches,
        );
      } else {
        await generateDeliveryReport(
          selectedItem: _selectedItem!,
          activeBranches: activeBranches,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedReportType} generated successfully! Opening...'),
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

                  // Supersale Dropdown
                  Text(
                    'Select Supersale',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedItem,
                        hint: const Text('Select a Supersale'),
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        items: _supersaleItems.map((item) {
                          return DropdownMenuItem<String>(
                            value: item,
                            child: Text(
                              item,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedItem = val;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Report Type Dropdown
                  Text(
                    'Report Type',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedReportType,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        items: const [
                          DropdownMenuItem<String>(
                            value: 'Booking Report',
                            child: Text('Booking Report'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'Delivery Report',
                            child: Text('Delivery Report'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedReportType = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

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
}
