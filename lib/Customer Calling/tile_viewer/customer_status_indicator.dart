import 'package:flutter/material.dart';

class CustomerStatusIndicator extends StatelessWidget {
  final bool called;
  final Color swappedColor;

  const CustomerStatusIndicator({
    Key? key,
    required this.called,
    required this.swappedColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: called
            ? swappedColor.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: called ? swappedColor : Colors.orange,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            called ? Icons.check_circle : Icons.pending,
            color: called ? swappedColor : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  called ? 'Call Completed' : 'Call Pending',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: called ? swappedColor : Colors.orange[700],
                  ),
                ),
                Text(
                  called ? 'Please add remarks below' : 'Tap the button above to call',
                  style: TextStyle(
                    fontSize: 14,
                    color: called ? swappedColor : Colors.orange[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
