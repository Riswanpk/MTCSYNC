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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Phone Duplication',
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
              'The same phone number is associated with different customer names. Select which name to keep or enter a separate phone number:',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.conflicts.length,
                separatorBuilder: (_, __) => const Divider(height: 24),
                itemBuilder: (context, idx) {
                  final c = widget.conflicts[idx];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Phone: ${c.originalPhone}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF005BAC)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '1: ${c.existingName}',
                              style: TextStyle(color: Colors.blue[900], fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Icon(Icons.compare_arrows, size: 16, color: Colors.grey),
                          Expanded(
                            child: Text(
                              '2: ${c.newName}',
                              style: TextStyle(color: Colors.green[800], fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 3 Choices: Keep Existing, Overwrite, or Assign New Phone
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            label: Text('Keep "${c.existingName}"', style: const TextStyle(fontSize: 12)),
                            selected: c.userChoice == ConflictResolution.keepExisting,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => c.userChoice = ConflictResolution.keepExisting);
                              }
                            },
                          ),
                          ChoiceChip(
                            label: Text('Keep "${c.newName}"', style: const TextStyle(fontSize: 12)),
                            selected: c.userChoice == ConflictResolution.overwriteExisting,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => c.userChoice = ConflictResolution.overwriteExisting);
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Change Phone Number', style: TextStyle(fontSize: 12)),
                            selected: c.userChoice == ConflictResolution.assignNewPhone,
                            selectedColor: Colors.orange.withValues(alpha: 0.2),
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
                            labelText: 'New Phone Number for ${c.newName}',
                            hintText: 'Enter distinct 10-digit mobile number',
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
