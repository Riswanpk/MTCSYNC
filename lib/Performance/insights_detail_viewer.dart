import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class InsightsDetailViewerPage extends StatefulWidget {
  final String userId;
  final String username;
  const InsightsDetailViewerPage({required this.userId, required this.username});

  @override
  State<InsightsDetailViewerPage> createState() => _InsightsDetailViewerPageState();
}

class _InsightsDetailViewerPageState extends State<InsightsDetailViewerPage> {
  // Removed performance graphics and widget code

  @override
  void initState() {
    super.initState();
  }

  Future<void> fetchWeeklyAverages() async {
    // Removed performance graphics and widget code
  }

  @override
  Widget build(BuildContext context) {
    // Removed performance graphics and widget code
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.username} - Monthly Performance'),
      ),
      body: Center(
        child: Text('Performance details have been removed.'),
      ),
    );
  }

  // Removed breakdown card widget
}
