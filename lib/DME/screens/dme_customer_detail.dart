import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_customer.dart';
import 'dme_customer_purchases.dart';
import 'dme_customer_branches.dart';

// ── Hardcoded lookup tables ───────────────────────────────────────
const Map<int, String> _categoryIdToName = {
  1: 'EVENT',
  2: 'CATERING',
  3: 'RESTAURANT',
  4: 'PANTHAL',
  5: 'STAGE DECORATION',
  6: 'AUDITORIUM',
  7: 'TRUST',
  8: 'INSTITUTION',
  9: 'RENTAL',
  10: 'HIRING',
  11: 'VEHICLE SHOWROOM',
  12: 'RESORT',
  13: 'GENERAL & OTHERS',
};

const Map<int, String> _customerTypeIdToName = {
  1: 'PREMIUM',
  2: 'REGULAR',
  3: 'BARGAIN',
  4: 'INSTITUTIONS',
  5: 'DEALERS',
  6: 'GENERAL',
};

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

    // Convert IDs to names if stored as IDs
    final displayCategory = c.category ??
        (c.categoryId != null
            ? _categoryIdToName[c.categoryId] ?? 'Unknown'
            : null);
    final displayCustomerType = c.customerType ??
        (c.customerTypeId != null
            ? _customerTypeIdToName[c.customerTypeId] ?? 'Unknown'
            : null);

    const primaryBlue = Color(0xFF005BAC);
    const accentGreen = Color(0xFF8CC63F);

    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),
      appBar: AppBar(
        title: Text(c.name),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header Card ──────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo row
                        Row(
                          children: [
                            Icon(Icons.diamond_rounded,
                                color: accentGreen, size: 22),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('MALABAR',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87)),
                                Text('TRADING COMPANY',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey[500],
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Name / phone / avatar row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.phone,
                                    style: TextStyle(
                                        fontSize: 14, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            // Avatar + badges
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: primaryBlue,
                                  child: Text(
                                    c.name.isNotEmpty
                                        ? c.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                ),
                                if (displayCustomerType != null) ...[
                                  const SizedBox(height: 8),
                                  _badge(displayCustomerType, primaryBlue),
                                ],
                                if (displayCategory != null) ...[
                                  const SizedBox(height: 4),
                                  _badge(displayCategory, accentGreen),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Address ──────────────────────────────────────
                  if (c.address != null && c.address!.isNotEmpty) ...[
                    _sectionCard(
                      header: 'Address',
                      headerColor: accentGreen,
                      children: [
                        _sectionRow(
                          icon: Icons.location_on,
                          label: 'Address',
                          value: c.address!,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Also Known As ─────────────────────────────────
                  if (c.purchasedFor != null && c.purchasedFor!.isNotEmpty) ...[
                    _sectionCard(
                      header: 'Also Known As',
                      headerColor: accentGreen,
                      children: [
                        _sectionRow(
                          icon: Icons.people_alt,
                          label: 'Names',
                          value: c.purchasedFor!,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Account Details ───────────────────────────────
                  if (c.salesman != null || c.branchName != null) ...[
                    _sectionCard(
                      header: 'Account Details',
                      headerColor: accentGreen,
                      children: [
                        if (c.salesman != null)
                          _sectionRow(
                            icon: Icons.person,
                            label: 'Salesman',
                            value: c.salesman!,
                            showChevron: true,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DmeCustomerBranchesPage(
                                  customer: c,
                                  dmeUser: widget.dmeUser,
                                ),
                              ),
                            ),
                          ),
                        if (c.salesman != null && c.branchName != null)
                          const Divider(height: 1, indent: 64),
                        if (c.branchName != null)
                          _sectionRow(
                            icon: Icons.business,
                            label: 'Branch',
                            value: c.branchName!,
                            showChevron: true,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DmeCustomerBranchesPage(
                                  customer: c,
                                  dmeUser: widget.dmeUser,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Recent Activity ───────────────────────────────
                  if (c.lastPurchaseDate != null)
                    _sectionCard(
                      header: 'Recent Activity',
                      headerColor: accentGreen,
                      children: [
                        _sectionRow(
                          icon: Icons.calendar_today,
                          label: 'Last Purchase',
                          value: dateFmt.format(c.lastPurchaseDate!),

                        ),
                        const Divider(height: 1, indent: 64),
                        _sectionRow(
                          icon: Icons.calendar_month,
                          label: 'View All Orders',
                          value: '',
                          showExternalLink: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DmeCustomerPurchasesPage(
                                customer: c,
                                dmeUser: widget.dmeUser,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _sectionCard({
    required String header,
    required Color headerColor,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: headerColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              header,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          Container(
            color: isDark ? Colors.grey[850] : Colors.white,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _sectionRow({
    required IconData icon,
    required String label,
    required String value,
    bool showChevron = false,
    bool showExternalLink = false,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: Colors.grey[500]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: value.isEmpty
                  ? Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                        const SizedBox(height: 2),
                        Text(value,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
            ),
            if (showChevron) Icon(Icons.chevron_right, color: Colors.grey[400]),
            if (showExternalLink)
              Icon(Icons.open_in_new, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
