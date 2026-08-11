import 'package:flutter/material.dart';

Color getScreeningStatusColor(String status) {
  switch (status) {
    case 'pending':
      return const Color(0xFFFFC107);
    case 'called':
      return const Color(0xFF2196F3);
    case 'promoted':
      return const Color(0xFF4CAF50);
    case 'rejected':
      return const Color(0xFFF44336);
    default:
      return Colors.grey;
  }
}

Color getPriorityColor(String priority) {
  switch (priority) {
    case 'High':
      return const Color(0xFFF44336);
    case 'Medium':
      return const Color(0xFFFFA500);
    case 'Low':
      return const Color(0xFF4CAF50);
    default:
      return Colors.grey;
  }
}

String screeningStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Pending';
    case 'called':
      return 'Called';
    case 'promoted':
      return 'Promoted';
    case 'rejected':
      return 'Rejected';
    default:
      return 'Pending';
  }
}

Color getFilterColor(String filter, Color brandPrimary) {
  switch (filter) {
    case 'Pending':
      return const Color(0xFFFFC107);
    case 'Called':
      return const Color(0xFF2196F3);
    case 'Promoted':
      return const Color(0xFF4CAF50);
    case 'Rejected':
      return const Color(0xFFF44336);
    case 'All':
      return brandPrimary;
    default:
      return Colors.grey;
  }
}

IconData getFilterIcon(String filter) {
  switch (filter) {
    case 'Pending':
      return Icons.hourglass_empty_rounded;
    case 'Called':
      return Icons.phone_callback_rounded;
    case 'Promoted':
      return Icons.check_circle_rounded;
    case 'Rejected':
      return Icons.cancel_rounded;
    case 'All':
      return Icons.all_inclusive_rounded;
    default:
      return Icons.circle;
  }
}

IconData getStatusIcon(String status) {
  switch (status) {
    case 'pending':
      return Icons.hourglass_empty_rounded;
    case 'called':
      return Icons.phone_callback_rounded;
    case 'promoted':
      return Icons.check_circle_rounded;
    case 'rejected':
      return Icons.cancel_rounded;
    default:
      return Icons.circle;
  }
}
