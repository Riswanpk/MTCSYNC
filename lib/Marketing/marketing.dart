import 'package:flutter/material.dart';
import 'premium_customer_form.dart';
import 'general_customer_form.dart';
import 'hotel_resort_customer_form.dart';
import 'viewer_marketing.dart';
import 'report_marketing.dart'; // Import the report page
import 'sales_marketing_daily_viewer.dart';
import 'sales_marketing_monthly_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class MarketingFormPage extends StatefulWidget {
  final String username;
  final String userid;
  final String branch;
  final bool loadDraft;
  final String? formToLoad;

  const MarketingFormPage({
    super.key,
    required this.username,
    required this.userid,
    required this.branch,
    this.loadDraft = false,
    this.formToLoad,
  });

  @override
  State<MarketingFormPage> createState() => _MarketingFormPageState();
}

class _MarketingFormPageState extends State<MarketingFormPage> {
  String _selectedForm = 'General Customer';
  bool _draftChecked = false;


  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    if (widget.loadDraft && widget.formToLoad != null) {
      _selectedForm = widget.formToLoad!;
      _draftChecked = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndPromptForDraft());
    }

  }

  Future<void> _checkAndPromptForDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final generalDraft = prefs.getString(GeneralCustomerForm.DRAFT_KEY);
    final premiumDraft = prefs.getString(PremiumCustomerForm.DRAFT_KEY);
    final hotelDraft = prefs.getString(HotelResortCustomerForm.DRAFT_KEY);

    String? draftFormType;
    if (generalDraft != null) draftFormType = 'General Customer';
    if (premiumDraft != null) draftFormType = 'Premium Customer';
    if (hotelDraft != null) draftFormType = 'Hotel / Resort Customer';

    if (draftFormType != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Draft Found'),
          content: Text('An unsaved "$draftFormType" form was found. Would you like to continue editing it?'),
          actions: [
            TextButton(
              child: const Text('Start New'),
              onPressed: () async {
                await _clearAllDrafts();
                Navigator.of(context).pop();
                setState(() {
                  _draftChecked = true;
                });
              },
            ),
            ElevatedButton(
              child: const Text('Load Draft'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _selectedForm = draftFormType!;
                  _draftChecked = true;
                });
              },
            ),
          ],
        ),
      );
    } else {
      setState(() {
        _draftChecked = true;
      });
    }
  }

  Future<void> _clearAllDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(GeneralCustomerForm.DRAFT_KEY);
    await prefs.remove(PremiumCustomerForm.DRAFT_KEY);
    await prefs.remove(HotelResortCustomerForm.DRAFT_KEY);
  }

  Future<void> _handleFormChange(String? newFormType) async {
    if (newFormType == null || newFormType == _selectedForm) return;

    final prefs = await SharedPreferences.getInstance();
    final hasAnyDraft = prefs.getString(GeneralCustomerForm.DRAFT_KEY) != null ||
                        prefs.getString(PremiumCustomerForm.DRAFT_KEY) != null ||
                        prefs.getString(HotelResortCustomerForm.DRAFT_KEY) != null;

    if (hasAnyDraft) {
      // Silently clear other drafts when switching to a new form type
      await _clearAllDrafts();
    }

    setState(() {
      _selectedForm = newFormType;
    });
  }



  @override
  Widget build(BuildContext context) {
    if (!_draftChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    Widget formWidget;
    switch (_selectedForm) {
      case 'General Customer':
        formWidget = GeneralCustomerForm(
          username: widget.username,
          userid: widget.userid,
          branch: widget.branch,
        );
        break;
      case 'Hotel / Resort Customer':
        formWidget = HotelResortCustomerForm(
          username: widget.username,
          userid: widget.userid,
          branch: widget.branch,
        );
        break;
      case 'Premium Customer':
        formWidget = PremiumCustomerForm(
          username: widget.username,
          userid: widget.userid,
          branch: widget.branch,
        );
        break;
      default:
        formWidget = GeneralCustomerForm( // Default to General
          username: widget.username,
          userid: widget.userid,
          branch: widget.branch,
        );
    }

    final String? userRole = ModalRoute.of(context)?.settings.arguments is Map
        ? (ModalRoute.of(context)!.settings.arguments as Map)['role'] as String?
        : null;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Marketing', style: TextStyle(fontFamily: 'Electorize', fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      endDrawer: Drawer(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.campaign_outlined, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 14),
                  const Text('Marketing', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'Electorize')),
                  const SizedBox(height: 4),
                  Text('Quick Actions', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14, fontFamily: 'Electorize')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16213E).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.today_rounded, color: Color(0xFF16213E), size: 22),
                    ),
                    title: const Text("Today's Forms", style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Electorize')),
                    subtitle: const Text('View submissions from today', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => SalesMarketingDailyViewer(
                            userId: widget.userid,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 72),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16213E).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF16213E), size: 22),
                    ),
                    title: const Text("Monthly Forms", style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Electorize')),
                    subtitle: const Text('View this month\'s submissions', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => SalesMarketingMonthlyViewer(
                            userId: widget.userid,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _buildFormTab('General Customer', 'General', Icons.storefront_outlined, const Color(0xFFFF6B35)),
                _buildFormTab('Premium Customer', 'Premium', Icons.workspace_premium_outlined, const Color(0xFFD4AF37)),
                _buildFormTab('Hotel / Resort Customer', 'Hotel', Icons.hotel_outlined, const Color(0xFF009688)),
              ],
            ),
          ),
          Expanded(child: formWidget),
        ],
      ),
    );
  }

  Widget _buildFormTab(String value, String label, IconData icon, Color color) {
    final isSelected = _selectedForm == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _handleFormChange(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: isSelected ? color : Colors.grey[500]),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? color : Colors.grey[600],
                  fontFamily: 'Electorize',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}