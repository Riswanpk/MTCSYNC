import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/dme_supabase_service.dart';
import 'models/dme_user.dart';
import 'screens/dme_reminders.dart';
import 'screens/dme_call_customers.dart';
import 'screens/dme_product_upload.dart';
import 'screens/dme_customer_db_upload.dart';
import 'screens/dme_user_management.dart';
import 'screens/dme_dashboard.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class DmeHomePage extends StatefulWidget {
  const DmeHomePage({super.key});

  @override
  State<DmeHomePage> createState() => _DmeHomePageState();
}

class _DmeHomePageState extends State<DmeHomePage> {
  DmeUser? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final user = await DmeSupabaseService.instance.getCurrentUser(uid);
    if (mounted) setState(() { _user = user; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[100],
      appBar: AppBar(
        title: Text(_user?.username ?? 'DME',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_user?.isAdmin == true)
            IconButton(
              icon: const Icon(Icons.dashboard_rounded),
              tooltip: 'Dashboard',
              onPressed: () => _navigate(const DmeDashboardPage()),
            ),
        ],
      ),
      drawer: _user?.isAdmin == true ? _buildSidebar(isDark) : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _user == null
              ? _buildNoAccess()
              : _buildTiles(isDark),
    );
  }

  Widget _buildSidebar(bool isDark) {
    return Drawer(
      backgroundColor: isDark ? const Color(0xFF1A2332) : Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: _primaryBlue,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Text(
                    (_user?.username.isNotEmpty ?? false)
                        ? _user!.username[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _user?.username ?? 'DME Admin',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_rounded, color: _primaryBlue),
            title: const Text('Users'),
            onTap: () {
              Navigator.pop(context);
              _navigate(const DmeUserManagementPage());
            },
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildNoAccess() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'You do not have DME access.\nContact your DME Admin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTiles(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Core DME user tiles ──
          _tileRow(
            left: _DmeTile(
              icon: Icons.notifications_active_rounded,
              label: 'Reminders',
              color: _primaryGreen,
              onTap: () => _navigate(DmeRemindersPage(dmeUser: _user!)),
            ),
            right: _DmeTile(
              icon: Icons.phone_in_talk_rounded,
              label: 'Call Customers',
              color: _primaryBlue,
              onTap: () => _navigate(DmeCallCustomersPage(dmeUser: _user!)),
            ),
          ),
          // ── Admin-only tiles ──
          if (_user!.isAdmin) ...[
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('ADMIN',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white38 : Colors.black38,
                    letterSpacing: 1.2,
                  )),
            ),
            const SizedBox(height: 10),
            _tileRow(
              left: _DmeTile(
                icon: Icons.inventory_2_rounded,
                label: 'Products',
                color: const Color(0xFF607D8B),
                onTap: () => _navigate(const DmeProductUploadPage()),
              ),
              right: _DmeTile(
                icon: Icons.dashboard_rounded,
                label: 'Dashboard',
                color: const Color(0xFF607D8B),
                onTap: () => _navigate(const DmeDashboardPage()),
              ),
            ),
            const SizedBox(height: 14),
            _DmeTile(
              icon: Icons.cloud_upload_rounded,
              label: 'Customer DB Upload',
              color: const Color(0xFF607D8B),
              onTap: () => _navigate(const DmeCustomerDbUploadPage()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tileRow({required Widget left, required Widget right}) {
    return Row(children: [
      Expanded(child: left),
      const SizedBox(width: 14),
      Expanded(child: right),
    ]);
  }

  void _navigate(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

// ── Simple tile widget matching NeumorphicButton style ───────
class _DmeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DmeTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      borderRadius: BorderRadius.circular(18),
      color: isDark ? const Color(0xFF1A2332) : Colors.white,
      elevation: isDark ? 0 : 3,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 110,
          padding: const EdgeInsets.all(16),
          decoration: isDark
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 10),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
