import 'package:flutter/material.dart';
import 'follow.dart';

class LeadsPage extends StatelessWidget {
  const LeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM - Leads Follow Up'),
        backgroundColor: Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          LeadCard(name: "John Doe", status: "In Progress", date: "May 10"),
          LeadCard(name: "Jane Smith", status: "Completed", date: "May 12"),
          LeadCard(name: "Mike Johnson", status: "In Progress", date: "May 14"),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFF8CC63F),
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FollowUpForm()),
          );
        },
      ),
    );
  }
}

class LeadCard extends StatelessWidget {
  final String name;
  final String status;
  final String date;

  const LeadCard({
    super.key,
    required this.name,
    required this.status,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Text('Status: $status\nDate: $date'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Optionally handle detailed view
        },
      ),
    );
  }
}
