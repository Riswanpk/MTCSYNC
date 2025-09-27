import 'package:flutter/material.dart';
import 'premium_customer_form.dart';
import 'general_customer_form.dart';
import 'hotel_resort_customer_form.dart';
import 'viewer_marketing.dart';
import 'report_marketing.dart'; // Import the report page

class MarketingFormPage extends StatefulWidget {
  final String username;
  final String userid;
  final String branch;

  const MarketingFormPage({
    super.key,
    required this.username,
    required this.userid,
    required this.branch,
  });

  @override
  State<MarketingFormPage> createState() => _MarketingFormPageState();
}

class _MarketingFormPageState extends State<MarketingFormPage> {
  String _selectedForm = 'Premium Customer';

  @override
  Widget build(BuildContext context) {
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
      default:
        formWidget = PremiumCustomerForm(
          username: widget.username,
          userid: widget.userid,
          branch: widget.branch,
        );
    }

    // Assume you pass user role as an argument or get it from context/provider
    final String? userRole = ModalRoute.of(context)?.settings.arguments is Map
        ? (ModalRoute.of(context)!.settings.arguments as Map)['role'] as String?
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketing Form'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          if (userRole != 'sales' && userRole != 'manager')
            IconButton(
              icon: const Icon(Icons.insert_drive_file),
              tooltip: 'Report',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ReportMarketingPage()),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<String>(
              value: _selectedForm,
              items: const [
                DropdownMenuItem(value: 'General Customer', child: Text('General Customer')),
                DropdownMenuItem(value: 'Premium Customer', child: Text('Premium Customer')),
                DropdownMenuItem(value: 'Hotel / Resort Customer', child: Text('Hotel / Resort Customer')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _selectedForm = value);
              },
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