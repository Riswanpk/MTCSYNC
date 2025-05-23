import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PresentFollowUp extends StatelessWidget {
  final String docId;

  const PresentFollowUp({super.key, required this.docId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Follow-Up Details'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
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

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 20),

                // 2x2 Grid for main info
                GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildInfoCard(Icons.person, 'Name', data['name'], isDark),
                    _buildInfoCard(Icons.apartment, 'Company', data['company'], isDark),
                    _buildInfoCard(Icons.location_on, 'Address', data['address'], isDark),
                    _buildInfoCard(Icons.phone, 'Phone', data['phone'], isDark),
                  ],
                ),

                const SizedBox(height: 32),
                Text(
                  'Follow-Up Info',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 20),

                // Additional info in cards
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoTile(
                        Icons.flag,
                        'Status',
                        DropdownButton<String>(
                          value: data['status'],
                          dropdownColor: isDark ? const Color(0xFF23262F) : Colors.white,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black),
                          items: ['In Progress', 'Completed'].map((status) {
                            return DropdownMenuItem<String>(
                              value: status,
                              child: Text(status),
                            );
                          }).toList(),
                          onChanged: (newStatus) async {
                            if (newStatus != null && newStatus != data['status']) {
                              await FirebaseFirestore.instance
                                  .collection('follow_ups')
                                  .doc(docId)
                                  .update({'status': newStatus});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Status updated to $newStatus')),
                              );
                            }
                          },
                        ),
                        isDark,
                      ),
                    ),
                  ],
                ),
                _buildInfoTile(Icons.calendar_today, 'Date', Text(data['date'] ?? 'N/A', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), isDark),
                _buildInfoTile(Icons.alarm, 'Reminder', Text(data['reminder'] ?? 'N/A', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), isDark),
                _buildInfoTile(Icons.comment, 'Comments', Text(data['comments'] ?? 'N/A', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), isDark),
                _buildInfoTile(Icons.location_city, 'Branch', Text(data['branch'] ?? 'N/A', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), isDark),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String? value, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23262F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black12, blurRadius: 6),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: const Color(0xFF005BAC)),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 4),
          Text(value ?? 'N/A', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, Widget valueWidget, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23262F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black12, blurRadius: 4),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF005BAC)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 4),
                valueWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
