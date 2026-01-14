import 'package:flutter/material.dart';

class MarketingInstructionsPage extends StatelessWidget {
  const MarketingInstructionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketing Instructions'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Marketing Feature Guide',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),

          // Add Marketing Entry
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Color(0xFF8CC63F)),
            title: const Text('Add Marketing Entry'),
            subtitle: const Text(
              'Tap the "+" button to add a new marketing entry. Choose the form type: General, Premium Customer, or Hotel/Resort. Fill in all required details and submit.',
            ),
          ),

          // Edit Marketing Entry
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text('Edit Marketing Entry'),
            subtitle: const Text(
              'Tap on an existing entry to view or edit its details. Update information as needed and save changes.',
            ),
          ),

          // View Today's Forms
          ListTile(
            leading: const Icon(Icons.view_list, color: Colors.teal),
            title: const Text("View Today's Forms"),
            subtitle: const Text(
              'Access the marketing menu and tap "View Today\'s Forms" to see all entries submitted today.',
            ),
          ),

          // View This Month's Forms
          ListTile(
            leading: const Icon(Icons.calendar_month_rounded, color: Colors.orange),
            title: const Text("View This Month's Forms"),
            subtitle: const Text(
              'Access the marketing menu and tap "View This Month\'s Forms" to see all entries submitted this month.',
            ),
          ),

          // Drafts
          ListTile(
            leading: const Icon(Icons.drafts, color: Colors.brown),
            title: const Text('Drafts'),
            subtitle: const Text(
              'If you leave the form without submitting, your input is saved as a draft. You can load the draft when you return.',
            ),
          ),

          // Showcase Hints
          ListTile(
            leading: const Icon(Icons.lightbulb_outline, color: Colors.amber),
            title: const Text('Showcase Hints'),
            subtitle: const Text(
              'The app will highlight important features and menu items the first few times you use the marketing section.',
            ),
          ),



          // Customer Types
          ListTile(
            leading: const Icon(Icons.people, color: Colors.purple),
            title: const Text('Customer Types'),
            subtitle: const Text(
              'Choose between General, Premium, or Hotel/Resort customer forms based on the marketing activity.',
            ),
          ),



          const SizedBox(height: 24),
          const Text(
            'For more help, contact your administrator.',
            style: TextStyle(fontSize: 15, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}