import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
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
  final ValueNotifier<bool> _isHovering = ValueNotifier(false);

  final List<String> statusOptions = ['All', 'In Progress', 'Completed'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM - Leads Follow Up'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Background logo
          Center(
            child: Opacity(
              opacity: 0.05,
              child: Image.asset(
                'assets/images/logo.png', // Make sure path matches your folder
                width: 250,
              ),
            ),
          ),
          Column(
            children: [
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
                    hintStyle: const TextStyle(color: Colors.green),
                    prefixIcon: const Icon(Icons.search, color: Colors.green),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: const TextStyle(color: Colors.green),
                ),
              ),
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
                      return const Center(child: Text("No leads available."));
                    }

                    final allLeads = snapshot.data!.docs;

                    final filteredLeads = allLeads.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = (data['name'] ?? '').toString().toLowerCase();
                      final status = (data['status'] ?? 'Unknown').toString();

                      final matchesSearch = name.contains(searchQuery);
                      final matchesStatus =
                          selectedStatus == 'All' || status == selectedStatus;

                      return matchesSearch && matchesStatus;
                    }).toList();

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
        ],
      ),
      floatingActionButton: MouseRegion(
        onEnter: (_) => _isHovering.value = true,
        onExit: (_) => _isHovering.value = false,
        cursor: SystemMouseCursors.click,
        child: ValueListenableBuilder<bool>(
          valueListenable: _isHovering,
          builder: (_, isHovered, child) {
            return Transform.scale(
              scale: isHovered ? 1.15 : 1.0,
              child: StatefulBuilder(
                builder: (context, setState) {
                  Color buttonColor = isHovered ? const Color(0xFF77B72E) : const Color(0xFF8CC63F);

                  return FloatingActionButton(
                    backgroundColor: buttonColor,
                    elevation: isHovered ? 10 : 6, // Add shadow effect
                    child: const Icon(Icons.add),
                    onPressed: () {
                      setState(() {
                        buttonColor = const Color(0xFF005BAC); // Change to blue when pressed
                      });
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const FollowUpForm()),
                      );
                    },
                  );
                },
              ),
            );
          },
        ),
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

  Future<void> _playClickSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/click.mp3'), volume: 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () async {
        await _playClickSound(); // Play sound on tap
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PresentFollowUp(docId: docId),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor, // Use theme card color
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(isDark ? 0.2 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16),
                      children: [
                        TextSpan(
                          text: name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' '),
                        TextSpan(
                          text: '($status)',
                          style: TextStyle(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Date: $date',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 13, color: theme.hintColor),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.delete,
                color: isDark ? Colors.white : Colors.black, // Change icon color based on theme
              ),
              tooltip: 'Delete Lead',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Lead?'),
                    content: const Text('Are you sure you want to delete this lead? This action cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await FirebaseFirestore.instance
                      .collection('follow_ups')
                      .doc(docId)
                      .delete();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lead deleted')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
