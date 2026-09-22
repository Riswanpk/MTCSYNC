import 'package:flutter/material.dart';
import '../../../Complaints/Dme/dme_register_complaint_page.dart';

class DmeReminderAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Map<String, dynamic> reminder;
  final List<Map<String, dynamic>> salesHistory;
  final bool isCompleted;
  final bool isCalledWithoutRemarks;
  final bool callMade;
  final VoidCallback onOpenRaiseRequest;

  const DmeReminderAppBar({
    super.key,
    required this.reminder,
    required this.salesHistory,
    required this.isCompleted,
    required this.isCalledWithoutRemarks,
    required this.callMade,
    required this.onOpenRaiseRequest,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (isCalledWithoutRemarks) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please enter remarks and tap "Save Remarks & Mark Completed" before leaving.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
      title: const Text('Reminder Details', style: TextStyle(fontSize: 18)),
      backgroundColor: const Color(0xFF005BAC),
      foregroundColor: Colors.white,
      actions: [
        if (isCompleted || isCalledWithoutRemarks || callMade)
          IconButton(
            icon: const Icon(Icons.report_problem_rounded, color: Colors.amber),
            tooltip: 'Raise Complaint',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DmeRegisterComplaintPage(
                    reminder: reminder,
                    initialSalesHistory: salesHistory,
                  ),
                ),
              );
            },
          ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.rate_review_outlined, size: 14),
            label: const Text('Request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF005BAC),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 1,
            ),
            onPressed: onOpenRaiseRequest,
          ),
        ),
      ],
    );
  }
}
