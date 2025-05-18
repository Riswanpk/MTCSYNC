import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'follow.dart';
import 'presentfollowup.dart';

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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('follow_ups')
            .orderBy('created_at', descending: true)
            .snapshots(), // ✅ Fixed: Proper stream type
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No leads available."));
          }

          final leads = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: leads.length,
            itemBuilder: (context, index) {
              final data = leads[index].data() as Map<String, dynamic>;
              final name = data['name'] ?? 'No Name';
              final status = data['status'] ?? 'Unknown';
              final date = data['date'] ?? 'No Date';
              final docId = leads[index].id;

              return LeadCard(
                name: name,
                status: status,
                date: date,
                docId: docId,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF8CC63F),
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
  final String docId;

  const LeadCard({
    super.key,
    required this.name,
    required this.status,
    required this.date,
    required this.docId,
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PresentFollowUp(docId: docId),
            ),
          );
        },
      ),
    );
  }
}
