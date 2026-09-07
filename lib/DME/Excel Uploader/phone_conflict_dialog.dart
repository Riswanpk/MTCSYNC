import 'package:flutter/material.dart';
import 'excel_uploader_models.dart';

class PhoneConflictDialog extends StatefulWidget {
  final List<CustomerConflict> conflicts;
  final VoidCallback onApplied;

  const PhoneConflictDialog({
    super.key,
    required this.conflicts,
    required this.onApplied,
  });

  @override
  State<PhoneConflictDialog> createState() => _PhoneConflictDialogState();
}

class _PhoneConflictDialogState extends State<PhoneConflictDialog> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Customer Name Conflicts',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold),
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
            // Color Theme Legend
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  // Red Legend (Database)
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red[600],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Red = Database',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Green Legend (Excel)
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.green[600],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Green = Excel',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.conflicts.length,
                separatorBuilder: (_, __) => const Divider(height: 28),
                itemBuilder: (context, idx) {
                  final c = widget.conflicts[idx];
                  final isDb = c.isFromDatabase;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Phone Number Tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF005BAC).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone_android_rounded, size: 14, color: Color(0xFF005BAC)),
                            const SizedBox(width: 4),
                            Text(
                              'Phone: ${c.originalPhone}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF005BAC)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Side-by-Side / Stacked Comparison Cards
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 400;

                          final dbCard = Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: isDark ? 0.2 : 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(isDb ? Icons.storage_rounded : Icons.history_rounded, size: 14, color: Colors.red[700]),
                                    const SizedBox(width: 4),
                                    Text(
                                      isDb ? 'DATABASE RECORD' : 'PREVIOUS EXCEL ROW',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                        color: Colors.red[800],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  c.existingName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.red[200] : Colors.red[900],
                                  ),
                                ),
                              ],
                            ),
                          );

                          final excelCard = Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: isDark ? 0.2 : 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.table_chart_rounded, size: 14, color: Colors.green[700]),
                                    const SizedBox(width: 4),
                                    Text(
                                      'EXCEL SHEET ROW',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                        color: Colors.green[800],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  c.newName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.green[200] : Colors.green[900],
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (isNarrow) {
                            return Column(
                              children: [
                                SizedBox(width: double.infinity, child: dbCard),
                                const SizedBox(height: 6),
                                SizedBox(width: double.infinity, child: excelCard),
                              ],
                            );
                          } else {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: dbCard),
                                const SizedBox(width: 8),
                                Expanded(child: excelCard),
                              ],
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 10),

                      // Choices with Red (Database) and Green (Excel) styling
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            avatar: Icon(
                              Icons.storage_rounded,
                              size: 14,
                              color: c.userChoice == ConflictResolution.keepExisting ? Colors.red[800] : Colors.grey[700],
                            ),
                            label: Text(
                              isDb ? 'Keep Database ("${c.existingName}")' : 'Keep Previous ("${c.existingName}")',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: c.userChoice == ConflictResolution.keepExisting ? FontWeight.bold : FontWeight.normal,
                                color: c.userChoice == ConflictResolution.keepExisting ? (isDark ? Colors.red[200] : Colors.red[900]) : null,
                              ),
                            ),
                            selected: c.userChoice == ConflictResolution.keepExisting,
                            selectedColor: Colors.red.withValues(alpha: 0.25),
                            side: BorderSide(
                              color: c.userChoice == ConflictResolution.keepExisting ? Colors.red : Colors.grey.withValues(alpha: 0.4),
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => c.userChoice = ConflictResolution.keepExisting);
                              }
                            },
                          ),
                          ChoiceChip(
                            avatar: Icon(
                              Icons.table_chart_rounded,
                              size: 14,
                              color: c.userChoice == ConflictResolution.overwriteExisting ? Colors.green[800] : Colors.grey[700],
                            ),
                            label: Text(
                              'Use Excel ("${c.newName}")',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: c.userChoice == ConflictResolution.overwriteExisting ? FontWeight.bold : FontWeight.normal,
                                color: c.userChoice == ConflictResolution.overwriteExisting ? (isDark ? Colors.green[200] : Colors.green[900]) : null,
                              ),
                            ),
                            selected: c.userChoice == ConflictResolution.overwriteExisting,
                            selectedColor: Colors.green.withValues(alpha: 0.25),
                            side: BorderSide(
                              color: c.userChoice == ConflictResolution.overwriteExisting ? Colors.green : Colors.grey.withValues(alpha: 0.4),
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => c.userChoice = ConflictResolution.overwriteExisting);
                              }
                            },
                          ),
                          ChoiceChip(
                            avatar: Icon(
                              Icons.edit_road_rounded,
                              size: 14,
                              color: c.userChoice == ConflictResolution.assignNewPhone ? Colors.orange[800] : Colors.grey[700],
                            ),
                            label: const Text('Change Phone Number', style: TextStyle(fontSize: 11)),
                            selected: c.userChoice == ConflictResolution.assignNewPhone,
                            selectedColor: Colors.orange.withValues(alpha: 0.25),
                            side: BorderSide(
                              color: c.userChoice == ConflictResolution.assignNewPhone ? Colors.orange : Colors.grey.withValues(alpha: 0.4),
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  c.userChoice = ConflictResolution.assignNewPhone;
                                  if (c.phoneController.text.isEmpty) {
                                    c.phoneController.text = '${c.originalPhone}_2';
                                  }
                                });
                              }
                            },
                          ),
                        ],
                      ),

                      if (c.userChoice == ConflictResolution.assignNewPhone) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: c.phoneController,
                          decoration: InputDecoration(
                            labelText: 'New Phone Number for Excel Customer: ${c.newName}',
                            hintText: 'Enter distinct mobile number',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.phone, size: 18),
                          ),
                          onChanged: (val) {
                            c.customNewPhone = val.trim();
                          },
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF005BAC),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            for (var c in widget.conflicts) {
              if (c.userChoice == ConflictResolution.assignNewPhone) {
                c.customNewPhone = c.phoneController.text.trim();
                if (c.customNewPhone.isEmpty) {
                  c.customNewPhone = '${c.originalPhone}_alt';
                }
              }
            }
            Navigator.of(context).pop();
            widget.onApplied();
          },
          child: const Text('Apply Choices'),
        ),
      ],
    );
  }
}

