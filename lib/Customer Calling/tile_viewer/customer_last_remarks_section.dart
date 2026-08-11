import 'package:flutter/material.dart';

class CustomerLastRemarksSection extends StatelessWidget {
  final bool loadingLastRemarks;
  final List<Map<String, String>> pastRemarks;

  const CustomerLastRemarksSection({
    Key? key,
    required this.loadingLastRemarks,
    required this.pastRemarks,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (loadingLastRemarks) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (pastRemarks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: pastRemarks.map((entry) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry['monthYear']} Remarks',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                entry['remarks']!,
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}
