import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PresentFollowUp extends StatelessWidget {
  final String docId;

  const PresentFollowUp({super.key, required this.docId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow-Up Details'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('follow_ups').doc(docId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Follow-up not found.'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                _buildDetailTile('Customer Name', data['name']),
                _buildDetailTile('Company', data['company']),
                _buildDetailTile('Address', data['address']),
                _buildDetailTile('Phone Number', data['phone']),
                _buildDetailTile('Status', data['status']),
                _buildDetailTile('Date', data['date']),
                _buildDetailTile('Reminder', data['reminder']),
                _buildDetailTile('Comments', data['comments']),
                _buildDetailTile('Branch', data['branch']),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailTile(String title, String? value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value ?? 'N/A'),
      ),
    );
  }
}
