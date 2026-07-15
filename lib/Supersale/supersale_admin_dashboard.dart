import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'supersale_admin_report.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class SupersaleAdminDashboard extends StatefulWidget {
  const SupersaleAdminDashboard({Key? key}) : super(key: key);

  @override
  State<SupersaleAdminDashboard> createState() => _SupersaleAdminDashboardState();
}

class _SupersaleAdminDashboardState extends State<SupersaleAdminDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  bool _isFetchingChartData = false;
  
  List<Map<String, dynamic>> _activeSupersalesList = [];
  String? _selectedSupersaleItem;
  
  List<String> _chartBranches = [];
  List<double> _chartValues = [];

  @override
  void initState() {
    super.initState();
    _fetchActiveSupersales();
  }

  Future<void> _fetchActiveSupersales() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final snapshot = await _firestore.collection('supersales').get();
      final now = DateTime.now();
      
      List<Map<String, dynamic>> activeList = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        dynamic dEnd = data['deliveryEnd'];
        bool isActive = false;
        
        if (dEnd != null) {
          DateTime deliveryEnd = (dEnd is Timestamp) ? dEnd.toDate() : DateTime.tryParse(dEnd.toString()) ?? now;
          if (deliveryEnd.isAfter(now)) {
            isActive = true;
          }
        } else {
          isActive = true;
        }
        
        if (isActive) {
          activeList.add(data);
        }
      }
      
      if (mounted) {
        setState(() {
          _activeSupersalesList = activeList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching active supersales: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _fetchChartDataForSelected() async {
    if (_selectedSupersaleItem == null) return;
    
    setState(() {
      _isFetchingChartData = true;
    });
    
    try {
      // Find the selected supersale doc to get its branches
      final selectedData = _activeSupersalesList.firstWhere((element) => element['item'] == _selectedSupersaleItem, orElse: () => {});
      final branches = List<String>.from(selectedData['branches'] ?? []);
      
      List<MapEntry<String, double>> paired = [];
      
      for (String branch in branches) {
        final entriesSnapshot = await _firestore
            .collection('supersale_user_entries')
            .doc(branch)
            .collection(_selectedSupersaleItem!)
            .get();
            
        paired.add(MapEntry(branch, entriesSnapshot.docs.length.toDouble()));
      }
      
      // Sort in descending order
      paired.sort((a, b) => b.value.compareTo(a.value));
      
      if (mounted) {
        setState(() {
          _chartBranches = paired.map((e) => e.key).toList();
          _chartValues = paired.map((e) => e.value).toList();
          _isFetchingChartData = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching chart data: $e');
      if (mounted) {
        setState(() {
          _isFetchingChartData = false;
        });
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
          'Supersale Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: primaryBlue))
        : RefreshIndicator(
            onRefresh: _fetchActiveSupersales,
            color: primaryBlue,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Active Supersales',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDropdown(isDark),
                  const SizedBox(height: 32),
                  
                  if (_selectedSupersaleItem != null) ...[
                    Text(
                      'Entries per Branch',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildBarChart(isDark),
                    const SizedBox(height: 32),
                  ] else if (_activeSupersalesList.isNotEmpty) ...[
                    Container(
                      height: 150,
                      alignment: Alignment.center,
                      child: Text(
                        'Select a supersale from the dropdown above to view data.',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                  
                  _buildGenerateReportsButton(context, isDark),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
    );
  }
  
  Widget _buildDropdown(bool isDark) {
    if (_activeSupersalesList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white12 : Colors.grey[200]!),
        ),
        child: const Text('No active supersales found.'),
      );
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSupersaleItem,
          hint: Text(
            'Select a Supersale',
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          icon: Icon(Icons.arrow_drop_down_rounded, color: primaryBlue, size: 28),
          items: _activeSupersalesList.map((sale) {
            final itemName = sale['item'] as String? ?? 'Unnamed';
            return DropdownMenuItem<String>(
              value: itemName,
              child: Text(
                itemName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null && val != _selectedSupersaleItem) {
              setState(() {
                _selectedSupersaleItem = val;
              });
              _fetchChartDataForSelected();
            }
          },
        ),
      ),
    );
  }

  Widget _buildBarChart(bool isDark) {
    if (_isFetchingChartData) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey[200]!,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: primaryBlue),
      );
    }

    if (_chartBranches.isEmpty) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey[200]!,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          'No data for selected supersale',
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
        ),
      );
    }

    double maxY = 0;
    for (var val in _chartValues) {
      if (val > maxY) maxY = val;
    }
    maxY = maxY < 5 ? 5 : maxY + (maxY * 0.2); // Add 20% padding to top

    // Minimum width per bar to ensure it's scrollable if too many
    double minWidthPerBar = 60.0;
    double chartWidth = _chartBranches.length * minWidthPerBar;
    // ensure chart is at least screen width
    final screenWidth = MediaQuery.of(context).size.width - 72; // Padding
    if (chartWidth < screenWidth) {
      chartWidth = screenWidth;
    }

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          width: chartWidth,
          padding: const EdgeInsets.fromLTRB(16, 32, 24, 16),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => isDark ? Colors.white : const Color(0xFF1E293B),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${_chartBranches[groupIndex]}\n',
                      TextStyle(
                        color: isDark ? Colors.black87 : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      children: <TextSpan>[
                        TextSpan(
                          text: (rod.toY).toInt().toString(),
                          style: TextStyle(
                            color: isDark ? primaryBlue : Colors.lightBlueAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    getTitlesWidget: (value, meta) {
                      int index = value.toInt();
                      if (index >= 0 && index < _chartBranches.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _chartBranches[index],
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black87,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: (maxY / 5) > 0 ? (maxY / 5).ceilToDouble() : 1,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const SizedBox.shrink();
                      return Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (maxY / 5) > 0 ? (maxY / 5) : 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: isDark ? Colors.white10 : Colors.grey[200],
                    strokeWidth: 1,
                  );
                },
              ),
              barGroups: List.generate(
                _chartBranches.length,
                (index) => BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: _chartValues[index],
                      color: primaryBlue,
                      width: 20,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        topRight: Radius.circular(6),
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxY,
                        color: isDark ? Colors.white10 : Colors.grey[100],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGenerateReportsButton(BuildContext context, bool isDark) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SupersaleAdminReportPage()),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: primaryGreen,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: primaryGreen.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generate Reports',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Download supersale bookings as an Excel file.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}
