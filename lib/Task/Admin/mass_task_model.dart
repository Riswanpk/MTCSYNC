import 'package:cloud_firestore/cloud_firestore.dart';

class MassTaskGroup {
  final String massTaskId;
  final String title;
  final String description;
  final String assignedByName;
  final String assignedByEmail;
  final Timestamp? timestamp;
  final List<DocumentSnapshot> userTasks;

  MassTaskGroup({
    required this.massTaskId,
    required this.title,
    required this.description,
    required this.assignedByName,
    required this.assignedByEmail,
    required this.timestamp,
    required this.userTasks,
  });
}
