import 'package:flutter/material.dart';

class LeadsInstructionsPage extends StatelessWidget {
  const LeadsInstructionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leads Instructions'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Leads Feature Guide',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),

          // Add Lead
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Color(0xFF8CC63F)),
            title: const Text('Add Lead'),
            subtitle: const Text(
              'Tap the "+" button to add a new lead. Fill in customer name, address, phone, comments, priority, and reminder. Suggestions are shown from your customer list.',
            ),
          ),

          // Edit Lead
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text('Edit Lead'),
            subtitle: const Text(
              'Tap a lead to view and edit its details. Update status, comments, or reminder as needed.',
            ),
          ),

          // Mark as Completed / In Progress
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text('Mark as Completed / In Progress'),
            subtitle: const Text(
              'Swipe right on a lead to mark it as "Completed" or "In Progress". Status is shown next to the lead name.',
            ),
          ),

          // Delete Lead
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete Lead'),
            subtitle: const Text(
              'Swipe left and tap the delete icon to remove a lead. Admins and managers can delete all completed leads for a branch from the menu.',
            ),
          ),

          // Filters & Sorting
          ListTile(
            leading: const Icon(Icons.filter_alt, color: Colors.deepPurple),
            title: const Text('Filters & Sorting'),
            subtitle: const Text(
              'Filter leads by branch, user, status, and priority. Sort by newest or oldest. Use the search bar to find leads by name.',
            ),
          ),

          // Pagination
          ListTile(
            leading: const Icon(Icons.pages, color: Colors.orange),
            title: const Text('Pagination'),
            subtitle: const Text(
              'Navigate through leads using the page controls at the bottom. Each page shows up to 15 leads.',
            ),
          ),



          // Customer List Integration
          ListTile(
            leading: const Icon(Icons.people_outline, color: Colors.blueGrey),
            title: const Text('Customer List Integration'),
            subtitle: const Text(
              'Tap "Customer List" in the menu to view all customers. Adding or editing a lead updates the customer profile.',
            ),
          ),

          // Reminders & Notifications
          ListTile(
            leading: const Icon(Icons.alarm, color: Colors.teal),
            title: const Text('Reminders & Notifications'),
            subtitle: const Text(
              'Set a reminder for each lead. You will receive a notification at the scheduled time.',
            ),
          ),

          // Drafts
          ListTile(
            leading: const Icon(Icons.drafts, color: Colors.brown),
            title: const Text('Drafts'),
            subtitle: const Text(
              'If you leave the form without saving, your input is saved as a draft. You can load the draft when you return.',
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