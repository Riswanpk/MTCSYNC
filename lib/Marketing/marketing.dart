import 'package:flutter/material.dart';
import 'premium_customer_form.dart';
import 'general_customer_form.dart';
import 'hotel_resort_customer_form.dart';
import 'viewer_marketing.dart';
import 'report_marketing.dart'; // Import the report page
import 'sales_marketing_daily_viewer.dart';
import 'sales_marketing_monthly_viewer.dart';
import 'package:showcaseview/showcaseview.dart';
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

  final GlobalKey _drawerShowcaseKey = GlobalKey();
  final GlobalKey _todayShowcaseKey = GlobalKey();
  final GlobalKey _monthShowcaseKey = GlobalKey();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _showShowcaseIfNeeded());
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

  Future<void> _showShowcaseIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    dynamic raw = prefs.get('seen_marketing_drawer_hint');
    int seenCount = 0;
    if (raw is int) {
      seenCount = raw;
    } else if (raw is bool && raw == true) {
      seenCount = 1;
      await prefs.remove('seen_marketing_drawer_hint');
      await prefs.setInt('seen_marketing_drawer_hint', seenCount);
    }

    if (seenCount < 3 && mounted) {
      if (seenCount == 0) {
        ShowCaseWidget.of(context).startShowCase([_drawerShowcaseKey]);
        await Future.delayed(const Duration(seconds: 2));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening menu for you...')),
        );
        _scaffoldKey.currentState?.openEndDrawer();
      } else if (seenCount == 1) {
        ShowCaseWidget.of(context).startShowCase([_todayShowcaseKey]);
        await Future.delayed(const Duration(seconds: 2));
      } else if (seenCount == 2) {
        ShowCaseWidget.of(context).startShowCase([_monthShowcaseKey]);
        await Future.delayed(const Duration(seconds: 2));
      }
      await prefs.setInt('seen_marketing_drawer_hint', seenCount + 1);
    }
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
        title: const Text('Marketing Form'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
        actions: [
          Builder(
            builder: (context) => Showcase(
              key: _drawerShowcaseKey,
              description: "Tap here to open the marketing menu.",
              child: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  _scaffoldKey.currentState?.openEndDrawer();
                },
              ),
            ),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Color(0xFF005BAC),
              ),
              child: Text('Marketing Menu', style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            Showcase(
              key: _todayShowcaseKey,
              description: "Tap here to view today's submitted marketing forms.",
              child: ListTile(
                leading: const Icon(Icons.view_list),
                title: const Text("View Today's Forms"),
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
            ),
            Showcase(
              key: _monthShowcaseKey,
              description: "Tap here to view all forms submitted this month.",
              child: ListTile(
                leading: const Icon(Icons.calendar_month_rounded),
                title: const Text("View This Month's Forms"),
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
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<String>(
              value: _selectedForm,
              items: const [
                DropdownMenuItem(value: 'General Customer', child: Text('General Marketing')),
                DropdownMenuItem(value: 'Premium Customer', child: Text('Premium Customer')),
                DropdownMenuItem(value: 'Hotel / Resort Customer', child: Text('Hotel / Resort')),
              ],
              onChanged: _handleFormChange,
              decoration: const InputDecoration(
                labelText: 'Select Form Type',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: formWidget),
        ],
      ),
    );
  }
}