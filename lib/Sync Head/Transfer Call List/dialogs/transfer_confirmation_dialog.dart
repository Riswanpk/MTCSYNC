import 'package:flutter/material.dart';
import '../models/transfer_constants.dart';

class TransferConfirmationDialog extends StatelessWidget {
  final Map<String, dynamic> sourceUser;
  final Map<String, dynamic> destUser;
  final List<Map<String, dynamic>> customersToTransfer;

  const TransferConfirmationDialog({
    super.key,
    required this.sourceUser,
    required this.destUser,
    required this.customersToTransfer,
  });

  static Future<bool?> show({
    required BuildContext context,
    required Map<String, dynamic> sourceUser,
    required Map<String, dynamic> destUser,
    required List<Map<String, dynamic>> customersToTransfer,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => TransferConfirmationDialog(
        sourceUser: sourceUser,
        destUser: destUser,
        customersToTransfer: customersToTransfer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourceName = (sourceUser['username'] ?? sourceUser['email'] ?? 'User A').toString();
    final sourceBranch = (sourceUser['branch'] ?? 'No Branch').toString();
    final destName = (destUser['username'] ?? destUser['email'] ?? 'User B').toString();
    final destBranch = (destUser['branch'] ?? 'No Branch').toString();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kTransferPrimaryBlue, Color(0xFF0288D1)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Confirm Transfer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kTransferPrimaryBlue.withValues(alpha: 0.08),
                      kTransferPrimaryGreen.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kTransferPrimaryBlue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: kTransferSourceAccent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_remove_rounded, size: 16, color: kTransferSourceAccent),
                        ),
                        const SizedBox(width: 10),
                        const Text('From: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Expanded(
                          child: Text(
                            '$sourceName ($sourceBranch)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Expanded(child: Divider()),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.grey),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: kTransferDestAccent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: kTransferDestAccent),
                        ),
                        const SizedBox(width: 10),
                        const Text('To: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Expanded(
                          child: Text(
                            '$destName ($destBranch)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: kTransferDestAccent,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Transferring ${customersToTransfer.length} customer(s) across ALL past months with complete call history and remarks.',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text('Selected Customers:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: kTransferPrimaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${customersToTransfer.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: kTransferPrimaryBlue),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: customersToTransfer.map((c) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 16, color: kTransferPrimaryGreen),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${c['name'] ?? 'Unknown'} (${c['contact1'] ?? c['contact'] ?? 'No phone'})',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.bolt_rounded, size: 18),
          label: const Text('Confirm Transfer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: kTransferPrimaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
}
