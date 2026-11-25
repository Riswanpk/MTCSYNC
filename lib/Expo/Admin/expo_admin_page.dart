import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../expo_service.dart';
import 'expo_admin_form.dart';
import 'expo_excel_export_service.dart';
import '../User/expo_user_mainpage.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class ExpoAdminPage extends StatefulWidget {
  const ExpoAdminPage({super.key});

  @override
  State<ExpoAdminPage> createState() => _ExpoAdminPageState();
}

class _ExpoAdminPageState extends State<ExpoAdminPage> {
  final Set<String> _endingExhibitionIds = {};
  final Set<String> _exportingExhibitionIds = {};

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
  }

  Future<void> _confirmEndExhibition(Exhibition ex) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Exhibition?'),
        content: Text(
          'Ending "${ex.name}" will convert all pending Stall Delivery orders into Booking orders and make branch orders visible to Managers and Salesmen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
            ),
            child: const Text('End Exhibition'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _endingExhibitionIds.add(ex.id));
    try {
      final convertedCount = await ExpoService.instance.endExhibition(ex);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              convertedCount > 0
                  ? '"${ex.name}" ended. $convertedCount pending Stall Delivery order(s) converted to Booking.'
                  : '"${ex.name}" ended successfully.',
            ),
            backgroundColor: primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to end exhibition: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _endingExhibitionIds.remove(ex.id));
      }
    }
  }

  Future<void> _downloadExcel(Exhibition ex) async {
    setState(() => _exportingExhibitionIds.add(ex.id));
    try {
      await ExpoExcelExportService.exportExhibitionOrdersExcel(context, ex);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export Excel: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exportingExhibitionIds.remove(ex.id));
      }
    }
  }

  Future<void> _confirmDeleteExhibition(Exhibition ex) async {
    final pwdController = TextEditingController();
    String? errorMsg;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Delete Exhibition?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete "${ex.name}"? All associated orders will also be deleted.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pwdController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Enter Password',
                  errorText: errorMsg,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (pwdController.text.trim() != '3300') {
                  setDlgState(() => errorMsg = 'Incorrect password');
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 350), pwdController.dispose);

    if (confirmed == true && mounted) {
      try {
        await ExpoService.instance.deleteExhibition(ex.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exhibition deleted'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
        appBar: AppBar(
          title: const Text(
            'Expo Exhibitions',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: primaryGreen,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Active & Upcoming'),
              Tab(text: 'Past Exhibitions'),
            ],
          ),
        ),
        body: StreamBuilder<List<Exhibition>>(
          stream: ExpoService.instance.streamExhibitions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text('Error loading exhibitions: ${snapshot.error}'),
              );
            }

            final exhibitions = snapshot.data ?? [];
            final activeOrUpcoming = exhibitions
                .where((e) => !e.isEnded)
                .toList();
            final past = exhibitions
                .where((e) => e.isEnded)
                .toList();

            return TabBarView(
              children: [
                _buildExhibitionList(activeOrUpcoming, isDark, isPast: false),
                _buildExhibitionList(past, isDark, isPast: true),
              ],
            );
          },
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ExpoAdminFormPage(),
              ),
            );
          },
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded, size: 22),
          label: const Text(
            'New Exhibition',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildExhibitionList(
    List<Exhibition> list,
    bool isDark, {
    required bool isPast,
  }) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPast ? Icons.history_rounded : Icons.storefront_outlined,
              size: 64,
              color: primaryBlue.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 14),
            Text(
              isPast ? 'No Past Exhibitions' : 'No Active Exhibitions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isPast
                  ? 'Expired exhibitions will appear here.'
                  : 'Tap the + button below to create an exhibition.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final ex = list[index];

        String statusLabel = 'ACTIVE';
        Color statusColor = primaryGreen;
        if (ex.isEnded) {
          statusLabel = 'ENDED';
          statusColor = Colors.grey;
        } else if (ex.isDateEnded) {
          statusLabel = 'DATE ENDED';
          statusColor = const Color(0xFFE65100);
        } else if (ex.isUpcoming) {
          statusLabel = 'UPCOMING';
          statusColor = Colors.orange;
        }

        final bool showEndButton = ex.isDateEnded && !ex.isEnded;
        final bool showExcelButton = ex.isDateEnded || ex.isEnded;
        final bool isEnding = _endingExhibitionIds.contains(ex.id);
        final bool isExporting = _exportingExhibitionIds.contains(ex.id);

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          color: isDark ? const Color(0xFF0F243E) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ex.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded,
                                  size: 14, color: primaryBlue),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  ex.location,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor, width: 1),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Duration Details
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 16, color: primaryBlue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_formatDate(ex.startDate)}  —  ${_formatDate(ex.endDate)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Assigned Users Count & Chip
                Row(
                  children: [
                    const Icon(Icons.group_rounded,
                        size: 16, color: primaryGreen),
                    const SizedBox(width: 6),
                    Text(
                      '${ex.selectedUserIds.length} Assigned User${ex.selectedUserIds.length != 1 ? "s" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ExpoUserMainPage(
                                initialExhibition: ex,
                                isAdminView: true,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list_alt_rounded, size: 18),
                        label: const Text('View Orders'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryBlue,
                          side: const BorderSide(color: primaryBlue),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, color: primaryBlue),
                      tooltip: 'Edit Exhibition',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ExpoAdminFormPage(
                              existingExhibition: ex,
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent),
                      tooltip: 'Delete Exhibition',
                      onPressed: () => _confirmDeleteExhibition(ex),
                    ),
                  ],
                ),
                if (showEndButton || showExcelButton) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (showEndButton)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                isEnding ? null : () => _confirmEndExhibition(ex),
                            icon: isEnding
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.event_busy_rounded, size: 18),
                            label: Text(
                              isEnding ? 'Ending...' : 'End Exhibition',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE65100),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      if (showEndButton && showExcelButton)
                        const SizedBox(width: 10),
                      if (showExcelButton)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                isExporting ? null : () => _downloadExcel(ex),
                            icon: isExporting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.table_view_rounded, size: 18),
                            label: Text(
                              isExporting ? 'Exporting...' : 'Download Excel',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
