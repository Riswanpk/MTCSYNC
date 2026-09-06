import 'package:flutter/material.dart';
import 'excel_uploader_models.dart';
import 'excel_parsing_service.dart';

class MissingPhoneDialog extends StatefulWidget {
  final List<MissingPhoneCustomer> missingPhones;
  final List<GroupedSale> groupedSales;
  final List<ParsedExcelRow> parsedRows;
  final List<ParsedCustomerItem> customerList;
  final VoidCallback onCompleted;

  const MissingPhoneDialog({
    super.key,
    required this.missingPhones,
    required this.groupedSales,
    required this.parsedRows,
    required this.customerList,
    required this.onCompleted,
  });

  @override
  State<MissingPhoneDialog> createState() => _MissingPhoneDialogState();
}

class _MissingPhoneDialogState extends State<MissingPhoneDialog> {
  @override
  Widget build(BuildContext context) {
    final allFilled = widget.missingPhones.every((m) => m.phoneController.text.trim().length >= 5);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.phone_missed_rounded, color: Colors.redAccent, size: 26),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Missing Phone Numbers',
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
              'The following customer(s) have no mobile number in the Excel sheet. DME requires a valid phone number for every customer. Please enter their phone numbers below:',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.missingPhones.length,
                separatorBuilder: (_, __) => const Divider(height: 20),
                itemBuilder: (context, idx) {
                  final m = widget.missingPhones[idx];
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m.branchName,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                            ),
                          ),
                        ],
                      ),
                      if (m.address.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(m.address, style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: m.phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Enter Mobile Number *',
                          hintText: 'e.g. 9876543210',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.phone_android_rounded, size: 18),
                          errorText: m.phoneController.text.trim().isEmpty ? 'Required' : null,
                        ),
                        onChanged: (val) {
                          m.assignedPhone = ExcelParsingService.cleanPhoneNumber(val.trim());
                          setState(() {});
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
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: allFilled ? const Color(0xFF005BAC) : Colors.grey,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final unfilled = widget.missingPhones
                .where((m) => ExcelParsingService.cleanPhoneNumber(m.phoneController.text.trim()).isEmpty)
                .toList();
            if (unfilled.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Please fill in phone numbers for all ${unfilled.length} customer(s).'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            // Propagate newly filled phone numbers to parsed rows and grouped sales
            for (var m in widget.missingPhones) {
              final cleanPh = ExcelParsingService.cleanPhoneNumber(m.phoneController.text.trim());
              m.assignedPhone = cleanPh;

              for (var s in widget.groupedSales) {
                if (s.party.toLowerCase() == m.partyName.toLowerCase() && s.branchName == m.branchName && s.phone.isEmpty) {
                  s.phone = cleanPh;
                }
              }
              for (var r in widget.parsedRows) {
                if (r.party.toLowerCase() == m.partyName.toLowerCase() && r.branchName == m.branchName && r.phone.isEmpty) {
                  r.phone = cleanPh;
                }
              }
              for (var c in widget.customerList) {
                if (c.partyName.toLowerCase() == m.partyName.toLowerCase() &&
                    c.branchName == m.branchName &&
                    (c.phone == 'Missing Phone' || c.phone == 'N/A' || c.phone.isEmpty)) {
                  c.phone = cleanPh;
                }
              }
            }

            widget.missingPhones.clear();
            Navigator.of(context).pop();
            widget.onCompleted();
          },
          child: const Text('Save Phone Numbers & Continue'),
        ),
      ],
    );
  }
}
