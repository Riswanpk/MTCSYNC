import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'follow.dart';
import 'presentfollowup.dart';
import 'package:flutter_slidable/flutter_slidable.dart'; // Add this import at the top

class LeadsPage extends StatefulWidget {
  final String branch;

  const LeadsPage({super.key, required this.branch});

  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  String searchQuery = '';
  String selectedStatus = 'All';
  String? selectedBranch; // For admin branch selection
  List<String> availableBranches = [];
  final ValueNotifier<bool> _isHovering = ValueNotifier(false);

  final List<String> statusOptions = [
    'All',
    'In Progress',
    'Completed',
    'High',
    'Medium',
    'Low',
  ];

  late Future<Map<String, dynamic>?> _currentUserData;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _currentUserData = FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) => doc.data());
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final branches = snapshot.docs
        .map((doc) => doc.data()['branch'] as String?)
        .where((branch) => branch != null)
        .toSet()
        .cast<String>()
        .toList();
    setState(() {
      availableBranches = branches;
      if (branches.isNotEmpty && selectedBranch == null) {
        selectedBranch = branches.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _currentUserData,
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final userData = userSnapshot.data!;
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final role = userData['role'] ?? 'sales';
        final managerBranch = userData['branch'];

        // For admin, use selectedBranch, otherwise use user's branch
        final branchToShow = role == 'admin' ? selectedBranch ?? '' : widget.branch;

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
                    'assets/images/logo.png',
                    width: 250,
                  ),
                ),
              ),
              Column(
                children: [
                  if (role == 'admin')
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: DropdownButtonFormField<String>(
                        value: selectedBranch,
                        items: availableBranches
                            .map((branch) => DropdownMenuItem(
                                  value: branch,
                                  child: Text(branch),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedBranch = val;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Select Branch',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
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
                    child: role == 'manager'
                        ? FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .where('branch', isEqualTo: managerBranch)
                                .get(),
                            builder: (context, usersSnapshot) {
                              if (!usersSnapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              final branchUserIds = usersSnapshot.data!.docs.map((doc) => doc.id).toSet();

                              return StreamBuilder<QuerySnapshot>(
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

                                  // Show only leads created by users in the same branch
                                  final visibleLeads = allLeads.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    return branchUserIds.contains(data['created_by']);
                                  }).toList();

                                  final filteredLeads = visibleLeads.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    final name = (data['name'] ?? '').toString().toLowerCase();
                                    final status = (data['status'] ?? 'Unknown').toString();
                                    final priority = (data['priority'] ?? 'High').toString();
                                    final matchesSearch = name.contains(searchQuery);
                                    final matchesStatus = selectedStatus == 'All'
                                        || status == selectedStatus
                                        || priority == selectedStatus;
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
                                      final createdById = data['created_by'] ?? '';
                                      final priority = data['priority'] ?? 'High'; // <-- Add this

                                      return FutureBuilder<DocumentSnapshot>(
                                        future: FirebaseFirestore.instance.collection('users').doc(createdById).get(),
                                        builder: (context, userSnapshot) {
                                          String creatorUsername = 'Unknown';
                                          if (userSnapshot.connectionState == ConnectionState.done && userSnapshot.hasData) {
                                            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                                            if (userData != null && userData['username'] != null) {
                                              creatorUsername = userData['username'];
                                            }
                                          }
                                          return LeadCard(
                                            name: name,
                                            status: status,
                                            date: date,
                                            docId: docId,
                                            createdBy: creatorUsername,
                                            priority: priority, // <-- Pass priority
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          )
                        : role == 'admin'
                            ? StreamBuilder<QuerySnapshot>(
                                stream: branchToShow.isNotEmpty
                                    ? FirebaseFirestore.instance
                                        .collection('follow_ups')
                                        .where('branch', isEqualTo: branchToShow)
                                        .snapshots()
                                    : const Stream.empty(),
                                builder: (context, snapshot) {
                                  if (branchToShow.isEmpty) {
                                    return const Center(child: Text("Please select a branch."));
                                  }
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
                                    final priority = (data['priority'] ?? 'High').toString();
                                    final matchesSearch = name.contains(searchQuery);
                                    final matchesStatus = selectedStatus == 'All'
                                        || status == selectedStatus
                                        || priority == selectedStatus;
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
                                      final createdById = data['created_by'] ?? '';

                                      return FutureBuilder<DocumentSnapshot>(
                                        future: FirebaseFirestore.instance.collection('users').doc(createdById).get(),
                                        builder: (context, userSnapshot) {
                                          String creatorUsername = 'Unknown';
                                          if (userSnapshot.connectionState == ConnectionState.done && userSnapshot.hasData) {
                                            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                                            if (userData != null && userData['username'] != null) {
                                              creatorUsername = userData['username'];
                                            }
                                          }
                                          return LeadCard(
                                            name: name,
                                            status: status,
                                            date: date,
                                            docId: docId,
                                            createdBy: creatorUsername,
                                            priority: data['priority'] ?? 'High',
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              )
                            : StreamBuilder<QuerySnapshot>(
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

                                  // Only leads created by current sales user
                                  final visibleLeads = allLeads.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    return data['created_by'] == currentUserId;
                                  }).toList();

                                  final filteredLeads = visibleLeads.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    final name = (data['name'] ?? '').toString().toLowerCase();
                                    final status = (data['status'] ?? 'Unknown').toString();
                                    final priority = (data['priority'] ?? 'High').toString();
                                    final matchesSearch = name.contains(searchQuery);
                                    final matchesStatus = selectedStatus == 'All'
                                        || status == selectedStatus
                                        || priority == selectedStatus;
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
                                      final createdById = data['created_by'] ?? '';

                                      return FutureBuilder<DocumentSnapshot>(
                                        future: FirebaseFirestore.instance.collection('users').doc(createdById).get(),
                                        builder: (context, userSnapshot) {
                                          String creatorUsername = 'Unknown';
                                          if (userSnapshot.connectionState == ConnectionState.done && userSnapshot.hasData) {
                                            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                                            if (userData != null && userData['username'] != null) {
                                              creatorUsername = userData['username'];
                                            }
                                          }
                                          return LeadCard(
                                            name: name,
                                            status: status,
                                            date: date,
                                            docId: docId,
                                            createdBy: creatorUsername,
                                            priority: data['priority'] ?? 'High',
                                          );
                                        },
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
                        elevation: isHovered ? 10 : 6,
                        child: const Icon(Icons.add),
                        onPressed: () {
                          setState(() {
                            buttonColor = const Color(0xFF005BAC);
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
      },
    );
  }
}

class LeadCard extends StatelessWidget {
  final String name;
  final String status;
  final String date;
  final String docId;
  final String createdBy;
  final String priority;

  const LeadCard({
    super.key,
    required this.name,
    required this.status,
    required this.date,
    required this.docId,
    required this.createdBy,
    required this.priority,
  });

  Color getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.amber;
      case 'Low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color getPriorityBackgroundColor(String priority) {
    switch (priority) {
      case 'High':
        return const Color(0xFFFFEBEE); // Light red
      case 'Medium':
        return const Color(0xFFFFF8E1); // Light amber/yellow
      case 'Low':
        return const Color(0xFFE8F5E9); // Light green
      default:
        return Colors.grey.shade100;
    }
  }

  Future<void> _playClickSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/click.mp3'), volume: 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Slidable(
      key: ValueKey(docId),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (context) async {
              String newStatus = status == 'In Progress' ? 'Completed' : 'In Progress';
              await FirebaseFirestore.instance
                  .collection('follow_ups')
                  .doc(docId)
                  .update({'status': newStatus});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Status changed to $newStatus')),
              );
            },
            backgroundColor: status == 'In Progress'
                ? Colors.green.shade400
                : Colors.orange.shade400,
            foregroundColor: Colors.white,
            icon: status == 'In Progress' ? Icons.check_circle : Icons.refresh,
            label: status == 'In Progress' ? 'Completed' : 'In Progress',
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (context) async {
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
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () async {
          await _playClickSound();
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
            color: getPriorityBackgroundColor(priority),
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
              // Priority dot
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: getPriorityColor(priority),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
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
                    const SizedBox(height: 2),
                    Text(
                      'Created by: $createdBy',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey),
                    ),
                    Row(
                      children: [
                        Text(
                          'Priority: ',
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          priority,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: getPriorityColor(priority),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
