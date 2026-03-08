import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Misc/user_cache_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);
const Color _darkSurface = Color(0xFF1E2028);
const Color _darkCard = Color(0xFF252830);

class EntryPage extends StatefulWidget {
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  String? selectedBranch;
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> users = [];
  Map<String, TextEditingController> controllers = {};
  Map<String, TextEditingController> bdaControllers = {};
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchBranches();
  }

  Future<void> fetchBranches() async {
    final cachedUsers = await UserCacheService.instance.getAllUsers();
    final branchSet = <String>{};
    for (var u in cachedUsers) {
      final branch = u['branch'];
      if (branch != null && branch.toString().isNotEmpty) branchSet.add(branch);
    }
    final sortedBranches = branchSet.toList()..sort();
    setState(() {
      branches = sortedBranches.map((b) => {'branch': b}).toList();
    });
  }

  String _monthName(int month) {
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return months[month - 1];
  }

  Future<void> fetchUsersForBranch(String? branch) async {
    if (branch == null) return;
    setState(() {
      isLoading = true;
      users = [];
      controllers.clear();
      bdaControllers.clear();
    });
    final usersSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: branch)
        .get();
    setState(() {
      users = usersSnap.docs
          .map((doc) => {
                'id': doc.id,
                'username': doc.data()['username'] ?? doc.data()['email'] ?? 'User',
              })
          .toList();
      for (var user in users) {
        controllers[user['id']] = TextEditingController();
        bdaControllers[user['id']] = TextEditingController();
      }
    });

    // Load existing marks for this branch/month
    // Marks entered this month are for the previous month's performance
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final monthYear = "${_monthName(prevMonth)} $prevYear";
    final branchDoc = await FirebaseFirestore.instance
        .collection('performance_mark')
        .doc(monthYear)
        .collection('branches')
        .doc(branch)
        .get();
    if (branchDoc.exists && branchDoc.data()?['users'] != null) {
      final usersMap = Map<String, dynamic>.from(branchDoc.data()!['users']);
      for (var user in users) {
        final uid = user['id'];
        if (usersMap.containsKey(uid)) {
          final userData = Map<String, dynamic>.from(usersMap[uid]);
          controllers[uid]?.text = (userData['score'] ?? '').toString();
          bdaControllers[uid]?.text = (userData['bdaScore'] ?? '').toString();
        }
      }
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> saveMarks() async {
    // Marks entered this month are for the previous month's performance
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final monthYear = "${_monthName(prevMonth)} $prevYear";

    Map<String, dynamic> usersData = {};
    for (var user in users) {
      final uid = user['id'];
      final username = user['username'];
      final markStr = controllers[uid]?.text ?? '';
      final bdaStr = bdaControllers[uid]?.text ?? '';
      if (markStr.isEmpty && bdaStr.isEmpty) continue;
      final mark = markStr.isNotEmpty ? int.tryParse(markStr) : null;
      final bdaMark = bdaStr.isNotEmpty ? int.tryParse(bdaStr) : null;
      if (mark != null && mark > 30) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Performance mark for $username must be 0-30')),
        );
        return;
      }
      if (bdaMark != null && bdaMark > 20) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('BDA mark for $username must be 0-20')),
        );
        return;
      }
      final userData = <String, dynamic>{'username': username};
      if (mark != null) userData['score'] = mark;
      if (bdaMark != null) userData['bdaScore'] = bdaMark;
      usersData[uid] = userData;
    }

    if (usersData.isEmpty) return;

    final docRef = FirebaseFirestore.instance
        .collection('performance_mark')
        .doc(monthYear)
        .collection('branches')
        .doc(selectedBranch);

    await docRef.set({'users': usersData}, SetOptions(merge: true));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Performance marks saved!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final monthLabel = '${_monthName(prevMonth)} $prevYear';
    final bgColor = isDark ? _darkSurface : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // Gradient header
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: _primaryBlue,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF003D73), _primaryBlue, Color(0xFF0078E7)],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 30),
                      const Text(
                        'Performance Entry',
                        style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold,
                          color: Colors.white, letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          monthLabel,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              collapseMode: CollapseMode.pin,
            ),
          ),

          // Branch dropdown
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? _darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DropdownButtonFormField<String>(
                  value: selectedBranch,
                  hint: Text(
                    'Select Branch',
                    style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
                  ),
                  dropdownColor: isDark ? _darkCard : Colors.white,
                  items: branches
                      .map((b) => DropdownMenuItem<String>(
                            value: b['branch'] as String,
                            child: Text(b['branch'] as String),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() { selectedBranch = val; });
                    fetchUsersForBranch(val);
                  },
                  decoration: InputDecoration(
                    labelText: 'Select Branch',
                    labelStyle: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    prefixIcon: Icon(
                      Icons.store_rounded,
                      color: _primaryBlue.withOpacity(0.7),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ),
            ),
          ),

          // Body states
          if (selectedBranch == null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_note_rounded, size: 64,
                        color: isDark ? Colors.grey[700] : Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text(
                      'Select a branch to enter marks',
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // User cards list
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final user = users[idx];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark ? _darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // User name row
                            Row(
                              children: [
                                Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(
                                    color: _primaryBlue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${idx + 1}',
                                      style: TextStyle(
                                        color: _primaryBlue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    user['username'],
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Input fields row
                            Row(
                              children: [
                                Expanded(
                                  child: _ScoreField(
                                    controller: controllers[user['id']]!,
                                    label: 'Performance',
                                    hint: '0 – 30',
                                    icon: Icons.trending_up_rounded,
                                    accentColor: const Color(0xFFEF5350),
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _ScoreField(
                                    controller: bdaControllers[user['id']]!,
                                    label: 'BDA',
                                    hint: '0 – 20',
                                    icon: Icons.business_center_rounded,
                                    accentColor: const Color(0xFF26A69A),
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: users.length,
                ),
              ),
            ),

            // Save button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF003D73), _primaryBlue, Color(0xFF0078E7)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryBlue.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: saveMarks,
                      borderRadius: BorderRadius.circular(14),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Save Marks',
                              style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold,
                                color: Colors.white, letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color accentColor;
  final bool isDark;

  const _ScoreField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: accentColor, fontWeight: FontWeight.w600, fontSize: 13),
        hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 13),
        prefixIcon: Icon(icon, color: accentColor, size: 20),
        filled: true,
        fillColor: accentColor.withOpacity(isDark ? 0.08 : 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentColor.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}