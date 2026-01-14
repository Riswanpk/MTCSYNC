import 'package:flutter/material.dart';

class CustomerListInstructionsPage extends StatelessWidget {
  const CustomerListInstructionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer List Instructions'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Customer List Feature Guide',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),

          // Add Customer
          ListTile(
            leading: const Icon(Icons.person_add, color: Color(0xFF8CC63F)),
            title: const Text('Add Customer'),
            subtitle: const Text(
              'Tap the "+" button in the app bar to add a new customer. Enter name and contact number. The customer will appear in your list.',
            ),
          ),

          // View Details & Call
          ListTile(
            leading: const Icon(Icons.phone, color: Color(0xFF005BAC)),
            title: const Text('View Details & Make Call'),
            subtitle: const Text(
              'Tap a customer row to view details. Tap "Make Call" to call the customer directly from the app. Call status is tracked automatically.',
            ),
          ),



          // Remarks
          ListTile(
            leading: const Icon(Icons.note_alt, color: Colors.orange),
            title: const Text('Remarks'),
            subtitle: const Text(
              'After a call, enter remarks for the customer. Remarks help track the outcome of your conversation.',
            ),
          ),

          // Edit & Delete
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text('Edit & Delete'),
            subtitle: const Text(
              'Long press a customer row to edit or delete the customer. Changes are saved to your database.',
            ),
          ),

          // Sort & Filter
          ListTile(
            leading: const Icon(Icons.sort, color: Colors.purple),
            title: const Text('Sort & Filter'),
            subtitle: const Text(
              'Sort customers by call status using the "Sort" button. Called customers can be shown first or last.',
            ),
          ),

          // Add to Leads
          ListTile(
            leading: const Icon(Icons.add_task, color: Colors.teal),
            title: const Text('Add to Leads'),
            subtitle: const Text(
              'After entering remarks, tap "Add To Leads" to create a lead from the customer details.',
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