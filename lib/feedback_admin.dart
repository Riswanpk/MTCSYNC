import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Add this import
import 'marketing.dart';

class FeedbackAdminPage extends StatelessWidget {
  const FeedbackAdminPage({super.key});

  Future<void> _openMarketingForm(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] ?? userDoc.data()?['email'] ?? '';
    final branch = userDoc.data()?['branch'] ?? '';
    final userid = user.uid;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MarketingFormPage(
          username: username,
          userid: userid,
          branch: branch,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Feedback'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign),
            tooltip: 'Marketing Form',
            onPressed: () => _openMarketingForm(context), // Use the new method
          ),
        ],
      ),
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('feedbacks')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No feedback yet.'));
          }
          final docs = snapshot.data!.docs;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.resolveWith(
                (states) => isDark ? const Color(0xFF23262F) : Colors.grey[200],
              ),
              columns: const [
                DataColumn(label: Text('User')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Feedback')),
                DataColumn(label: Text('Date')),
              ],
              rows: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final date = data['timestamp'] != null
                    ? (data['timestamp'] as Timestamp).toDate()
                    : null;
                return DataRow(
                  cells: [
                    DataCell(Text(data['username'] ?? '')),
                    DataCell(Text(data['email'] ?? '')),
                    DataCell(SizedBox(
                      width: 250,
                      child: Text(data['feedback'] ?? ''),
                    )),
                    DataCell(Text(date != null
                        ? "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}"
                        : '')),
                  ],
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}