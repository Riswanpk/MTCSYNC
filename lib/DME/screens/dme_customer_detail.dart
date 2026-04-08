import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_customer.dart';

class DmeCustomerDetailPage extends StatefulWidget {
  final DmeCustomer customer;
  final DmeUser dmeUser;

  const DmeCustomerDetailPage({
    super.key,
    required this.customer,
    required this.dmeUser,
  });

  @override
  State<DmeCustomerDetailPage> createState() => _DmeCustomerDetailPageState();
}

class _DmeCustomerDetailPageState extends State<DmeCustomerDetailPage>
    with WidgetsBindingObserver {
  final _svc = DmeSupabaseService.instance;
  final _remarksCtrl = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _makeCall() async {
    final phone = widget.customer.phone;
    if (phone.isEmpty) return;

    final status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone permission required')),
        );
      }
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final dateFmt = DateFormat('dd-MMM-yy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Customer Header Card ──
                    Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF005BAC).withValues(alpha: 0.8),
                              const Color(0xFF005BAC),
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.white.withValues(alpha: 0.2),
                              child: Text(
                                c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              c.name,
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              c.phone,
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withValues(alpha: 0.9)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Customer Information Grid ──
                    if (c.address != null && c.address!.isNotEmpty)
                      _buildInfoCard(
                        Icon(Icons.location_on,
                            color: const Color(0xFF005BAC), size: 28),
                        'Address',
                        c.address!,
                      ),
                    if (c.purchasedFor != null && c.purchasedFor!.isNotEmpty)
                      _buildInfoCard(
                        Icon(Icons.people_alt,
                            color: const Color(0xFF005BAC), size: 28),
                        'Also Known As',
                        c.purchasedFor!,
                      ),
                    if (c.category != null)
                      _buildInfoCard(
                        Icon(Icons.category,
                            color: const Color(0xFF005BAC), size: 28),
                        'Category',
                        c.category!,
                      ),
                    if (c.customerType != null)
                      _buildInfoCard(
                        Icon(Icons.star,
                            color: const Color(0xFF005BAC), size: 28),
                        'Customer Type',
                        c.customerType!,
                      ),
                    if (c.salesman != null)
                      _buildInfoCard(
                        Icon(Icons.person,
                            color: const Color(0xFF005BAC), size: 28),
                        'Salesman',
                        c.salesman!,
                      ),
                    if (c.lastPurchaseDate != null)
                      _buildInfoCard(
                        Icon(Icons.calendar_today,
                            color: const Color(0xFF005BAC), size: 28),
                        'Last Purchase',
                        dateFmt.format(c.lastPurchaseDate!),
                      ),
                    if (c.branchName != null)
                      _buildInfoCard(
                        Icon(Icons.business,
                            color: const Color(0xFF005BAC), size: 28),
                        'Branch',
                        c.branchName!,
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildInfoCard(Icon icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF005BAC).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: icon,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
