import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Misc/dme_constants.dart';
import 'excel_uploader_models.dart';

class MissingBranchDialog extends StatefulWidget {
  final List<MissingBranchSale> missingBranches;
  final List<GroupedSale> groupedSales;
  final List<ParsedExcelRow> parsedRows;
  final List<ParsedCustomerItem> customerList;
  final VoidCallback onCompleted;

  const MissingBranchDialog({
    super.key,
    required this.missingBranches,
    required this.groupedSales,
    required this.parsedRows,
    required this.customerList,
    required this.onCompleted,
  });

  @override
  State<MissingBranchDialog> createState() => _MissingBranchDialogState();
}

class _MissingBranchDialogState extends State<MissingBranchDialog> {
  int? _globalBranchId;

  @override
  Widget build(BuildContext context) {
    final allAssigned = widget.missingBranches.every((m) => m.selectedBranchId != null);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.business_rounded, color: Colors.orange, size: 26),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Missing Branch Name',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following sale(s) have a missing or unrecognized branch name in the Excel sheet. DME requires a branch for every transaction. Please select the appropriate branch below:',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),

            // Fast action: Apply branch to all missing items at once
            if (widget.missingBranches.length > 1) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF005BAC).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF005BAC).withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flash_on_rounded, size: 18, color: Color(0xFF005BAC)),
                    const SizedBox(width: 8),
                    const Text(
                      'Apply to all:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isDense: true,
                          hint: const Text('Select branch for all', style: TextStyle(fontSize: 12)),
                          value: _globalBranchId,
                          items: DmeConstants.branches.map((b) {
                            return DropdownMenuItem<int>(
                              value: b.id,
                              child: Text(
                                '${b.name} (${b.toString()})',
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                          onChanged: (newId) {
                            if (newId == null) return;
                            final bName = DmeConstants.getBranchName(newId);
                            setState(() {
                              _globalBranchId = newId;
                              for (var m in widget.missingBranches) {
                                m.selectedBranchId = newId;
                                m.selectedBranchName = bName;
                              }
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.missingBranches.length,
                separatorBuilder: (_, __) => const Divider(height: 20),
                itemBuilder: (context, idx) {
                  final m = widget.missingBranches[idx];
                  final formattedDate = DateFormat('dd MMM yyyy').format(m.date);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.partyName.isNotEmpty ? m.partyName : 'Unnamed Party',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          if (m.voucherNo.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Voucher: ${m.voucherNo}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (m.phone.isNotEmpty) ...[
                            Icon(Icons.phone_rounded, size: 12, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(m.phone, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            const SizedBox(width: 10),
                          ],
                          Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(formattedDate, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          if (m.rawBranchName.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Excel: "${m.rawBranchName}"',
                                style: const TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        decoration: InputDecoration(
                          labelText: 'Select Branch *',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.location_on_rounded, size: 18),
                        ),
                        value: m.selectedBranchId,
                        items: DmeConstants.branches.map((b) {
                          return DropdownMenuItem<int>(
                            value: b.id,
                            child: Text('${b.name} (${b.toString()})', style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            m.selectedBranchId = val;
                            m.selectedBranchName = val != null ? DmeConstants.getBranchName(val) : null;
                          });
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: allAssigned ? const Color(0xFF005BAC) : Colors.grey,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final unassigned = widget.missingBranches.where((m) => m.selectedBranchId == null).toList();
            if (unassigned.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Please select a branch for all ${unassigned.length} transaction(s).'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            // Propagate selected branches to grouped sales, parsed rows, and customer list
            for (var m in widget.missingBranches) {
              final branchId = m.selectedBranchId!;
              final branchName = m.selectedBranchName ?? DmeConstants.getBranchName(branchId);

              for (var s in widget.groupedSales) {
                final matchVoucher = m.voucherNo.isNotEmpty && s.voucherNo == m.voucherNo;
                final matchParty = s.party.toLowerCase() == m.partyName.toLowerCase();
                final matchDate = s.date.year == m.date.year && s.date.month == m.date.month && s.date.day == m.date.day;

                if ((matchVoucher || (matchParty && matchDate)) && (s.branchId == null || s.branchName.trim().isEmpty)) {
                  s.branchId = branchId;
                  s.branchName = branchName;
                }
              }

              for (var r in widget.parsedRows) {
                final matchVoucher = m.voucherNo.isNotEmpty && r.voucherNo == m.voucherNo;
                final matchParty = r.party.toLowerCase() == m.partyName.toLowerCase();
                final matchDate = r.date.year == m.date.year && r.date.month == m.date.month && r.date.day == m.date.day;

                if ((matchVoucher || (matchParty && matchDate)) && (r.branchId == null || r.branchName.trim().isEmpty)) {
                  r.branchId = branchId;
                  r.branchName = branchName;
                }
              }

              for (var c in widget.customerList) {
                if (c.partyName.toLowerCase() == m.partyName.toLowerCase() &&
                    (c.branchName.isEmpty || c.branchName == 'N/A' || c.branchName == 'Unknown')) {
                  c.branchName = branchName;
                }
              }
            }

            widget.missingBranches.clear();
            Navigator.of(context).pop();
            widget.onCompleted();
          },
          child: const Text('Save Branch & Continue'),
        ),
      ],
    );
  }
}
