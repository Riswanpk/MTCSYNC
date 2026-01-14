import 'package:flutter/material.dart';
import 'todo_instructions.dart';
import 'leads_instructions.dart';
import 'marketing_instructions.dart';
import 'customer_list_instructions.dart';

class InstructionsPage extends StatelessWidget {
  const InstructionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instructions'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            Text(
              'Main Features',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 18),
            ListTile(
              leading: Icon(Icons.check_circle_outline, color: Color(0xFF8CC63F)),
              title: Text('ToDo'),
              subtitle: Text('Create, edit, and manage your daily tasks.'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TodoInstructionsPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.people_alt_rounded, color: Color(0xFF005BAC)),
              title: Text('Leads'),
              subtitle: Text('Track and manage customer leads for your branch.'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LeadsInstructionsPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.campaign, color: Color.fromARGB(255, 192, 25, 14)),
              title: Text('Marketing'),
              subtitle: Text('Submit and review marketing activities.'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MarketingInstructionsPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.list_alt, color: Color.fromARGB(255, 246, 174, 6)),
              title: Text('Customer List'),
              subtitle: Text('View and manage your customer database.'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CustomerListInstructionsPage()),
                );
              },
            ),
            SizedBox(height: 18),
            Text(
              'For more details, contact your administrator.',
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}