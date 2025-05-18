import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'follow.dart';
import 'presentfollowup.dart';

class LeadsPage extends StatefulWidget {
  final String branch;

  const LeadsPage({super.key, required this.branch});

  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  String searchQuery = '';
  String selectedStatus = 'All';

  final List<String> statusOptions = ['All', 'New', 'In Progress', 'Closed']; // Add as needed

  @override
  Widget build(BuildContext context) {
    print("Fetching leads for branch: ${widget.branch}");

    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM - Leads Follow Up'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  searchQuery = val.toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Filter dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: DropdownButtonFormField<String>(
              value: selectedStatus,
              items: statusOptions.map((status) {
                return DropdownMenuItem<String>(
                  value: status,
                  child: Text(status),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  selectedStatus = val!;
                });
              },
              decoration: InputDecoration(
                labelText: 'Filter by Status',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Leads list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('follow_ups')
                  .where('branch', isEqualTo: widget.branch)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  print("No leads found for branch: ${widget.branch}");
                  return const Center(child: Text("No leads available."));
                }

                final allLeads = snapshot.data!.docs;

                // Apply search and filter
                final filteredLeads = allLeads.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final status = (data['status'] ?? 'Unknown').toString();

                  final matchesSearch = name.contains(searchQuery);
                  final matchesStatus = selectedStatus == 'All' || status == selectedStatus;

                  return matchesSearch && matchesStatus;
                }).toList();

                print("Found ${filteredLeads.length} leads after filter.");

                if (filteredLeads.isEmpty) {
                  return const Center(child: Text("No leads match your criteria."));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredLeads.length,
                  itemBuilder: (context, index) {
                    final data = filteredLeads[index].data() as Map<String, dynamic>;
                    final name = data['name'] ?? 'No Name';
                    final status = data['status'] ?? 'Unknown';
                    final date = data['date'] ?? 'No Date';
                    final docId = filteredLeads[index].id;

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
          ),
        ],
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
