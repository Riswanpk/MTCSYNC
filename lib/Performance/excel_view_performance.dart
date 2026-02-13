import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Misc/theme_notifier.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Theme colors (matching dashboard)
const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class ExcelViewPerformancePage extends StatefulWidget {
  @override
  State<ExcelViewPerformancePage> createState() =>
      _ExcelViewPerformancePageState();
}

class _ExcelViewPerformancePageState extends State<ExcelViewPerformancePage>
    with SingleTickerProviderStateMixin {
  String? selectedBranch;
  String? selectedUserId;
  Map<String, String> userIdToName = {};
  List<String> branches = [];
  List<String> usersInBranch = [];
  bool isLoadingBranches = true;
  bool isLoadingUsers = false;
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    fetchBranches();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> fetchBranches() async {
    setState(() {
      isLoadingBranches = true;
    });
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final branchSet = <String>{};
    for (var doc in snap.docs) {
      final branch = doc.data()['branch'];
      if (branch != null) branchSet.add(branch);
    }
    setState(() {
      branches = branchSet.toList()..sort();
      isLoadingBranches = false;
    });
    _animController.forward();
  }

  Future<void> fetchUsersForBranch(String branch) async {
    setState(() {
      isLoadingUsers = true;
    });
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: branch)
        .get();
    userIdToName.clear();
    usersInBranch = [];
    for (var doc in snap.docs) {
      userIdToName[doc.id] =
          doc.data()['username'] ?? doc.data()['email'] ?? doc.id;
      usersInBranch.add(doc.id);
    }
    setState(() {
      isLoadingUsers = false;
      selectedUserId = usersInBranch.isNotEmpty ? usersInBranch.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? const Color(0xFF1A1B22) : const Color(0xFFF5F7FA);
    final cardColor =
        isDark ? const Color(0xFF23242B) : Colors.white;

    if (isLoadingBranches) {
      return Scaffold(
        backgroundColor: surfaceColor,
        body: const Center(
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    return Scaffold(
      backgroundColor: surfaceColor,
      body: FadeTransition(
        opacity: _fadeIn,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Sliver App Bar ──
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor:
                  isDark ? const Color(0xFF1A1B22) : Colors.white,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : _primaryBlue)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: isDark ? Colors.white70 : _primaryBlue,
                    size: 18,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding:
                    const EdgeInsets.only(left: 60, bottom: 16),
                title: Text(
                  'Monthly Report',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? Colors.white : const Color(0xFF1A1B22),
                    letterSpacing: -0.3,
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF1A1B22),
                              const Color(0xFF23242B)
                            ]
                          : [Colors.white, const Color(0xFFF0F4FF)],
                    ),
                  ),
                ),
              ),
            ),

            // ── Body ──
            SliverPadding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),

                  // ── Filter Card ──
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black26
                              : Colors.black.withOpacity(0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _primaryBlue
                                    .withOpacity(isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.filter_list_rounded,
                                color: isDark
                                    ? Colors.white70
                                    : _primaryBlue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Select Employee',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1B22),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Branch dropdown
                        Text(
                          'Branch',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white54
                                : Colors.black45,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: (isDark
                                    ? Colors.white
                                    : _primaryBlue)
                                .withOpacity(0.06),
                            borderRadius:
                                BorderRadius.circular(14),
                            border: Border.all(
                              color: (isDark
                                      ? Colors.white
                                      : _primaryBlue)
                                  .withOpacity(0.12),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedBranch,
                              isExpanded: true,
                              hint: Text(
                                'Select Branch',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38,
                                ),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4),
                              borderRadius:
                                  BorderRadius.circular(14),
                              dropdownColor: cardColor,
                              icon: Icon(
                                Icons
                                    .keyboard_arrow_down_rounded,
                                color: isDark
                                    ? Colors.white54
                                    : _primaryBlue,
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1B22),
                              ),
                              items: branches
                                  .map((b) =>
                                      DropdownMenuItem(
                                        value: b,
                                        child: Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets
                                                      .all(6),
                                              decoration:
                                                  BoxDecoration(
                                                color: _primaryBlue
                                                    .withOpacity(
                                                        0.12),
                                                borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                            8),
                                              ),
                                              child: Icon(
                                                Icons
                                                    .store_rounded,
                                                size: 16,
                                                color:
                                                    _primaryBlue,
                                              ),
                                            ),
                                            const SizedBox(
                                                width: 10),
                                            Text(b),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                setState(() {
                                  selectedBranch = val;
                                  selectedUserId = null;
                                  usersInBranch = [];
                                });
                                if (val != null)
                                  fetchUsersForBranch(val);
                              },
                            ),
                          ),
                        ),

                        // User selector
                        if (selectedBranch != null) ...[
                          const SizedBox(height: 20),
                          Text(
                            'Employee',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.black45,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (isLoadingUsers)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5),
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: (isDark
                                        ? Colors.white
                                        : _primaryBlue)
                                    .withOpacity(0.06),
                                borderRadius:
                                    BorderRadius.circular(14),
                                border: Border.all(
                                  color: (isDark
                                          ? Colors.white
                                          : _primaryBlue)
                                      .withOpacity(0.12),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedUserId,
                                  isExpanded: true,
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 4),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  dropdownColor: cardColor,
                                  icon: Icon(
                                    Icons
                                        .keyboard_arrow_down_rounded,
                                    color: isDark
                                        ? Colors.white54
                                        : _primaryBlue,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1B22),
                                  ),
                                  items: usersInBranch
                                      .map((uid) =>
                                          DropdownMenuItem(
                                            value: uid,
                                            child: Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 14,
                                                  backgroundColor:
                                                      _primaryGreen
                                                          .withOpacity(
                                                              0.15),
                                                  child: Text(
                                                    (userIdToName[uid] ??
                                                            'U')
                                                        .substring(
                                                            0, 1)
                                                        .toUpperCase(),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight
                                                              .w700,
                                                      color:
                                                          _primaryGreen,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(
                                                    width: 10),
                                                Text(
                                                    userIdToName[
                                                            uid] ??
                                                        uid),
                                              ],
                                            ),
                                          ))
                                      .toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      selectedUserId = val;
                                    });
                                  },
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Performance Table ──
                  if (selectedBranch != null &&
                      selectedUserId != null)
                    _PerformanceTableView(
                      key: ValueKey(selectedUserId),
                      userId: selectedUserId!,
                    ),

                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Widget to show performance table for selected user
class _PerformanceTableView extends StatefulWidget {
  final String userId;
  const _PerformanceTableView({Key? key, required this.userId})
      : super(key: key);

  @override
  State<_PerformanceTableView> createState() => _PerformanceTableViewState();
}

class _PerformanceTableViewState extends State<_PerformanceTableView>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> dailyForms = [];
  bool isLoading = true;
  List<DateTime> monthDates = [];
  int selectedWeek = 0;
  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);
    fetchMonthlyForms();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchMonthlyForms() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final formsSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: widget.userId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    dailyForms = formsSnapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();
    monthDates = List.generate(
      monthEnd.difference(monthStart).inDays,
      (i) => monthStart.add(Duration(days: i)),
    );
    setState(() {
      isLoading = false;
    });
    _slideCtrl.forward();
  }

  Map<String, dynamic>? getFormForDate(DateTime date) {
    return dailyForms.firstWhere(
      (form) {
        final ts = form['timestamp'];
        final formDate = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
        return formDate.year == date.year && formDate.month == date.month && formDate.day == date.day;
      },
      orElse: () => {},
    );
  }

  List<DateTime> getFilteredDates() {
    if (selectedWeek == 0) return monthDates;
    int start = (selectedWeek - 1) * 7;
    int end = start + 7;
    if (start >= monthDates.length) return [];
    if (end > monthDates.length) end = monthDates.length;
    return monthDates.sublist(start, end);
  }

  Widget buildTableSection(String title, List<String> categories,
      String sectionKey, List<DateTime> filteredDates, bool isDark) {
    const double categoryColWidth = 180;
    final cardColor =
        isDark ? const Color(0xFF23242B) : Colors.white;
    final headerColor = isDark ? Colors.grey[850] : const Color(0xFFF0F4FF);

    // Pick icon/color per section
    IconData sectionIcon;
    Color accentColor;
    switch (sectionKey) {
      case 'attendance':
        sectionIcon = Icons.access_time_rounded;
        accentColor = const Color(0xFF4A90D9);
        break;
      case 'dressCode':
        sectionIcon = Icons.checkroom_rounded;
        accentColor = _primaryGreen;
        break;
      case 'attitude':
        sectionIcon = Icons.emoji_emotions_rounded;
        accentColor = const Color(0xFFFFA726);
        break;
      case 'meeting':
        sectionIcon = Icons.groups_rounded;
        accentColor = const Color(0xFFEF5350);
        break;
      default:
        sectionIcon = Icons.list_alt_rounded;
        accentColor = _primaryBlue;
    }

    return IntrinsicWidth(
      child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black26
                : Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [accentColor.withOpacity(0.15), cardColor]
                    : [accentColor.withOpacity(0.08), cardColor],
              ),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(sectionIcon,
                      color: accentColor, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isDark
                        ? Colors.white
                        : const Color(0xFF1A1B22),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          // Table
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DataTable(
              columnSpacing: 12,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 38,
              headingRowHeight: 34,
              horizontalMargin: 12,
              headingRowColor:
                  WidgetStateProperty.resolveWith<Color?>(
                (states) => headerColor,
              ),
              columns: [
                DataColumn(
                  label: SizedBox(
                    width: categoryColWidth,
                    child: Text('Category',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white54
                              : Colors.black54,
                        )),
                  ),
                ),
                ...filteredDates.map((d) => DataColumn(
                      label: Text(
                        '${d.day}/${d.month < 10 ? '0' : ''}${d.month}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white38
                              : Colors.black45,
                        ),
                      ),
                    )),
              ],
              rows: categories.map((cat) {
                return DataRow(
                  cells: [
                    DataCell(SizedBox(
                      width: categoryColWidth,
                      child: Text(cat,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF1A1B22),
                          )),
                    )),
                    ...filteredDates.map((date) {
                      final form = getFormForDate(date);
                      bool? value;
                      if (form == null || form.isEmpty) {
                        return DataCell(Text('-',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white24
                                    : Colors.black26)));
                      }
                      if (sectionKey == 'attendance') {
                        String att = form['attendance'] ?? '';
                        if (cat == 'Punching Time') {
                          value = att == 'punching' ? true : null;
                        } else if (cat == 'Late time') {
                          value = att == 'late' ? true : null;
                        } else if (cat == 'Approved Leave') {
                          value = att == 'approved' ? true : null;
                        } else if (cat == 'Unapproved Leave') {
                          value =
                              att == 'notApproved' ? true : null;
                        }
                      } else if (sectionKey == 'dressCode') {
                        if (cat == 'Wear clean uniform')
                          value = form['dressCode']
                                  ?['cleanUniform'] !=
                              false;
                        if (cat == 'Keep inside')
                          value = form['dressCode']
                                  ?['keepInside'] !=
                              false;
                        if (cat == 'Keep your hair neat')
                          value =
                              form['dressCode']?['neatHair'] !=
                                  false;
                      } else if (sectionKey == 'attitude') {
                        if (cat == 'Greet with a warm smile')
                          value = form['attitude']
                                  ?['greetSmile'] !=
                              false;
                        if (cat == 'Ask about their needs')
                          value =
                              form['attitude']?['askNeeds'] !=
                                  false;
                        if (cat ==
                            'Help find the right product')
                          value = form['attitude']
                                  ?['helpFindProduct'] !=
                              false;
                        if (cat == 'Confirm the purchase')
                          value = form['attitude']
                                  ?['confirmPurchase'] !=
                              false;
                        if (cat ==
                            'Offer carry or delivery help')
                          value = form['attitude']
                                  ?['offerHelp'] !=
                              false;
                      } else if (sectionKey == 'meeting') {
                        if (cat == 'Meeting') {
                          if (form['meeting']?['noMeeting'] ==
                              true) {
                            value = null;
                          } else {
                            value =
                                form['meeting']?['attended'] ==
                                    true;
                          }
                        }
                      }
                      return DataCell(
                        sectionKey == 'meeting' &&
                                form['meeting']?['noMeeting'] ==
                                    true
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.info_outline,
                                      color:
                                          const Color(0xFF64B5F6),
                                      size: 14),
                                  const SizedBox(width: 2),
                                  Text('No meeting',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: const Color(
                                              0xFF64B5F6))),
                                ],
                              )
                            : value == null
                                ? Text('-',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white24
                                            : Colors.black26))
                                : value
                                    ? Container(
                                        padding:
                                            const EdgeInsets.all(
                                                2),
                                        decoration: BoxDecoration(
                                          color:
                                              const Color(
                                                      0xFF66BB6A)
                                                  .withOpacity(
                                                      0.15),
                                          borderRadius:
                                              BorderRadius
                                                  .circular(6),
                                        ),
                                        child: const Icon(
                                            Icons.check_rounded,
                                            color: Color(
                                                0xFF66BB6A),
                                            size: 15),
                                      )
                                    : Container(
                                        padding:
                                            const EdgeInsets.all(
                                                2),
                                        decoration: BoxDecoration(
                                          color:
                                              const Color(
                                                      0xFFEF5350)
                                                  .withOpacity(
                                                      0.15),
                                          borderRadius:
                                              BorderRadius
                                                  .circular(6),
                                        ),
                                        child: const Icon(
                                            Icons.close_rounded,
                                            color: Color(
                                                0xFFEF5350),
                                            size: 15),
                                      ),
                      );
                    }).toList(),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget buildNewQuestionTableSection(String title, String fieldKey,
      List<DateTime> filteredDates, bool isDark,
      {bool isBool = false, String? trueText, String? falseText}) {
    const double categoryColWidth = 180;
    final cardColor =
        isDark ? const Color(0xFF23242B) : Colors.white;
    final headerColor = isDark ? Colors.grey[850] : const Color(0xFFF0F4FF);
    final accentColor = _primaryBlue;

    return IntrinsicWidth(
      child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black26
                : Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [accentColor.withOpacity(0.15), cardColor]
                    : [accentColor.withOpacity(0.08), cardColor],
              ),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isBool
                        ? Icons.toggle_on_rounded
                        : Icons.timer_outlined,
                    color: accentColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isDark
                        ? Colors.white
                        : const Color(0xFF1A1B22),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DataTable(
              columnSpacing: 12,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 38,
              headingRowHeight: 34,
              horizontalMargin: 12,
              headingRowColor:
                  WidgetStateProperty.resolveWith<Color?>(
                (states) => headerColor,
              ),
              columns: [
                DataColumn(
                  label: SizedBox(
                    width: categoryColWidth,
                    child: Text('Category',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white54
                              : Colors.black54,
                        )),
                  ),
                ),
                ...filteredDates.map((d) => DataColumn(
                      label: Text(
                        '${d.day}/${d.month < 10 ? '0' : ''}${d.month}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white38
                              : Colors.black45,
                        ),
                      ),
                    )),
              ],
              rows: [
                DataRow(
                  cells: [
                    DataCell(SizedBox(
                      width: categoryColWidth,
                      child: Text(title,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF1A1B22),
                          )),
                    )),
                    ...filteredDates.map((date) {
                      final form = getFormForDate(date);
                      if (form == null || form.isEmpty) {
                        return DataCell(Text('-',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white24
                                    : Colors.black26)));
                      }
                      final value = form[fieldKey];
                      if (isBool) {
                        if (value == true) {
                          return DataCell(Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF66BB6A)
                                  .withOpacity(0.15),
                              borderRadius:
                                  BorderRadius.circular(6),
                            ),
                            child: const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF66BB6A),
                                size: 15),
                          ));
                        } else if (value == false) {
                          return DataCell(Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF5350)
                                  .withOpacity(0.15),
                              borderRadius:
                                  BorderRadius.circular(6),
                            ),
                            child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFFEF5350),
                                size: 15),
                          ));
                        } else {
                          return DataCell(Text('-',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.black26)));
                        }
                      } else {
                        String display =
                            (value ?? '').toString();
                        if (display.isEmpty ||
                            display == 'null') {
                          display = '-';
                        }
                        return DataCell(Text(display,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF1A1B22),
                            )));
                      }
                    }).toList(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF23242B) : Colors.white;

    if (isLoading) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    int numWeeks = (monthDates.length / 7).ceil();
    final filteredDates = getFilteredDates();

    return FadeTransition(
      opacity: _slideAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Week Filter Chips ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black26
                      : Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: _primaryGreen
                            .withOpacity(isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.date_range_rounded,
                        color: isDark
                            ? Colors.white70
                            : _primaryGreen,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Filter by Week',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1A1B22),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildWeekChip('All', 0, isDark),
                    ...List.generate(
                      numWeeks,
                      (i) => _buildWeekChip(
                          'Week ${i + 1}', i + 1, isDark),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Table Sections (synchronized horizontal scroll) ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          buildTableSection(
            'ATTENDANCE (OUT OF 20)',
            [
              'Punching Time',
              'Late time',
              'Approved Leave',
              'Unapproved Leave'
            ],
            'attendance',
            filteredDates,
            isDark,
          ),
          buildTableSection(
            'DRESS CODE (OUT OF 20)',
            [
              'Wear clean uniform',
              'Keep inside',
              'Keep your hair neat'
            ],
            'dressCode',
            filteredDates,
            isDark,
          ),
          buildTableSection(
            'ATTITUDE (OUT OF 20)',
            [
              'Greet with a warm smile',
              'Ask about their needs',
              'Help find the right product',
              'Confirm the purchase',
              'Offer carry or delivery help'
            ],
            'attitude',
            filteredDates,
            isDark,
          ),
          buildTableSection(
            'MEETING (OUT OF 10)',
            ['Meeting'],
            'meeting',
            filteredDates,
            isDark,
          ),

          // ── Additional Questions ──
          buildNewQuestionTableSection(
              'Time Taken for Other Tasks (min)',
              'timeTakenOtherTasks',
              filteredDates,
              isDark),
          buildNewQuestionTableSection(
              'Old Stock Offer Given?',
              'oldStockOfferGiven',
              filteredDates,
              isDark,
              isBool: true),
          buildNewQuestionTableSection(
              'Cross-selling & Upselling?',
              'crossSellingUpselling',
              filteredDates,
              isDark,
              isBool: true),
          buildNewQuestionTableSection(
              'Product Complaints?',
              'productComplaints',
              filteredDates,
              isDark,
              isBool: true),
          buildNewQuestionTableSection(
              'Achieved Daily Target?',
              'achievedDailyTarget',
              filteredDates,
              isDark,
              isBool: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekChip(String label, int weekIndex, bool isDark) {
    final isSelected = selectedWeek == weekIndex;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedWeek = weekIndex;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
                )
              : null,
          color: isSelected
              ? null
              : (isDark ? Colors.white : _primaryGreen)
                  .withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (isDark ? Colors.white : _primaryGreen)
                    .withOpacity(0.15),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _primaryGreen.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : _primaryGreen),
          ),
        ),
      ),
    );
  }
}