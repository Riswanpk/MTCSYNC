import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' hide Column;

import '../models/dme_complaint.dart';
import '../services/dme_complaint_service.dart';
import '../services/dme_supabase_service.dart';

const Color _primary = Color(0xFF005BAC);

class DmeComplaintsReportPage extends StatefulWidget {
  final String userRole;
  final String? userId;

  const DmeComplaintsReportPage({
    super.key,
    required this.userRole,
    required this.userId,
  });

  @override
  State<DmeComplaintsReportPage> createState() => _DmeComplaintsReportPageState();
}

class _DmeComplaintsReportPageState extends State<DmeComplaintsReportPage> {
  final _complaintService = DmeComplaintService.instance;

  bool _loading = true;
  bool _exporting = false;
  List<DmeComplaint> _allComplaints = [];
  List<String> _availableBranches = ['All Branches'];
  String _selectedBranch = 'All Branches';
  late DateTimeRange _selectedRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedRange = DateTimeRange(
      start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
      end: DateTime(now.year, now.month, now.day),
    );
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      await DmeSupabaseService.instance.ensureInitialized();

      List<DmeComplaint> complaints = [];
      if (widget.userRole == 'dme_admin') {
        complaints = await _complaintService.getAllComplaints();
      } else {
        final uid = widget.userId;
        if (uid == null || uid.isEmpty) {
          throw Exception('Unable to load report: user not found.');
        }
        complaints = await _complaintService.getMyComplaints(userId: uid);
      }

      final branches = complaints
          .map((e) => e.branchName)
          .where((e) => e.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (mounted) {
        setState(() {
          _allComplaints = complaints;
          _availableBranches = ['All Branches', ...branches];
          if (!_availableBranches.contains(_selectedBranch)) {
            _selectedBranch = 'All Branches';
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading report data: $e')),
        );
      }
    }
  }

  List<DmeComplaint> _getFilteredComplaints() {
    final start = DateTime(
      _selectedRange.start.year,
      _selectedRange.start.month,
      _selectedRange.start.day,
    );
    final end = DateTime(
      _selectedRange.end.year,
      _selectedRange.end.month,
      _selectedRange.end.day,
      23,
      59,
      59,
      999,
    );

    return _allComplaints.where((c) {
      final inRange = !c.createdAt.isBefore(start) && !c.createdAt.isAfter(end);
      final branchOk = _selectedBranch == 'All Branches' || c.branchName == _selectedBranch;
      return inRange && branchOk;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _selectedRange,
    );
    if (picked != null) {
      setState(() {
        _selectedRange = picked;
      });
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'raised':
        return 'Raised';
      case 'case_resolved':
        return 'Resolved';
      case 'verified_closed':
        return 'Closed';
      default:
        return status;
    }
  }

  Future<void> _exportExcel() async {
    final filtered = _getFilteredComplaints();
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No complaints found for selected filters.')),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final workbook = Workbook(2);
      final summary = workbook.worksheets[0];
      final details = workbook.worksheets[1];

      summary.name = 'Summary';
      details.name = 'Complaints';

      final generatedAt = DateTime.now();
      final raisedCount = filtered.where((e) => e.status == 'raised').length;
      final resolvedCount = filtered.where((e) => e.status == 'case_resolved').length;
      final closedCount = filtered.where((e) => e.status == 'verified_closed').length;
      final withRemarksCount = filtered.where((e) => (e.remarks ?? '').trim().isNotEmpty).length;
      final withVoiceCount = filtered.where((e) => (e.voiceFileUrl ?? '').trim().isNotEmpty).length;

      int summaryRow = 1;
      void writeSummary(String key, String value) {
        summary.getRangeByIndex(summaryRow, 1).setText(key);
        summary.getRangeByIndex(summaryRow, 2).setText(value);
        summaryRow++;
      }

      writeSummary('Report Generated At', DateFormat('dd MMM yyyy, hh:mm a').format(generatedAt));
      writeSummary('Generated By Role', widget.userRole);
      writeSummary('Date Range',
          '${DateFormat('dd MMM yyyy').format(_selectedRange.start)} to ${DateFormat('dd MMM yyyy').format(_selectedRange.end)}');
      writeSummary('Branch Filter', _selectedBranch);
      writeSummary('Total Complaints', filtered.length.toString());
      writeSummary('Raised', raisedCount.toString());
      writeSummary('Resolved', resolvedCount.toString());
      writeSummary('Closed', closedCount.toString());
      writeSummary('Complaints With Remarks', withRemarksCount.toString());
      writeSummary('Complaints With Voice Note', withVoiceCount.toString());

      final headers = [
        'Complaint ID',
        'Created At',
        'Updated At',
        'Status',
        'Branch',
        'Customer Name',
        'Customer Phone',
        'Assigned To ID',
        'Created By ID',
        'Resolved At',
        'Closed At',
        'Remarks',
        'Remarked At',
        'Has New Remarks',
        'Has Voice Note',
        'Complaint Text',
      ];

      for (int i = 0; i < headers.length; i++) {
        details.getRangeByIndex(1, i + 1).setText(headers[i]);
      }

      int row = 2;
      for (final c in filtered) {
        details.getRangeByIndex(row, 1).setText(c.id ?? '');
        details.getRangeByIndex(row, 2).setText(DateFormat('dd MMM yyyy, hh:mm a').format(c.createdAt));
        details.getRangeByIndex(row, 3).setText(DateFormat('dd MMM yyyy, hh:mm a').format(c.updatedAt));
        details.getRangeByIndex(row, 4).setText(_statusLabel(c.status));
        details.getRangeByIndex(row, 5).setText(c.branchName);
        details.getRangeByIndex(row, 6).setText(c.customerName);
        details.getRangeByIndex(row, 7).setText(c.customerPhone);
        details.getRangeByIndex(row, 8).setText(c.assignedToUsername ?? c.assignedToId);
        details.getRangeByIndex(row, 9).setText(c.createdByUsername ?? c.createdById);
        details.getRangeByIndex(row, 10).setText(
          c.resolvedAt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(c.resolvedAt!) : '',
        );
        details.getRangeByIndex(row, 11).setText(
          c.closedAt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(c.closedAt!) : '',
        );
        details.getRangeByIndex(row, 12).setText(c.remarks ?? '');
        details.getRangeByIndex(row, 13).setText(
          c.remarkedAt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(c.remarkedAt!) : '',
        );
        details.getRangeByIndex(row, 14).setText(c.hasNewRemarks ? 'Yes' : 'No');
        details.getRangeByIndex(row, 15).setText((c.voiceFileUrl ?? '').trim().isNotEmpty ? 'Yes' : 'No');
        details.getRangeByIndex(row, 16).setText(c.complaintText);
        row++;
      }

      final bytes = workbook.saveSync();
      workbook.dispose();

      final dir = await getTemporaryDirectory();
      final fileName =
          'dme_complaints_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'DME Complaints Report',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report ready to share: $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating report: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredComplaints();
    final raisedCount = filtered.where((e) => e.status == 'raised').length;
    final resolvedCount = filtered.where((e) => e.status == 'case_resolved').length;
    final closedCount = filtered.where((e) => e.status == 'verified_closed').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaints Report', style: TextStyle(color: Colors.white)),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.date_range, color: _primary),
                            title: const Text('Date Range'),
                            subtitle: Text(
                              '${DateFormat('dd MMM yyyy').format(_selectedRange.start)} - ${DateFormat('dd MMM yyyy').format(_selectedRange.end)}',
                            ),
                            trailing: TextButton(
                              onPressed: _pickDateRange,
                              child: const Text('Change'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: _selectedBranch,
                            decoration: const InputDecoration(
                              labelText: 'Branch Filter',
                              border: OutlineInputBorder(),
                            ),
                            items: _availableBranches
                                .map((b) => DropdownMenuItem<String>(
                                      value: b,
                                      child: Text(b),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _selectedBranch = value);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildStatChip('Total', filtered.length, Colors.blue),
                      _buildStatChip('Raised', raisedCount, Colors.red),
                      _buildStatChip('Resolved', resolvedCount, Colors.orange),
                      _buildStatChip('Closed', closedCount, Colors.green),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _exporting ? null : _exportExcel,
                      icon: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.table_view),
                      label: Text(_exporting ? 'Generating Excel...' : 'Generate Excel Report'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Preview (${filtered.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No complaints in selected range/filter.'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final c = filtered[i];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(c.customerName),
                                subtitle: Text(
                                  '${c.branchName} • ${_statusLabel(c.status)} • ${DateFormat('dd MMM yyyy').format(c.createdAt)}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
