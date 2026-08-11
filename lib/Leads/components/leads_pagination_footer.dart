import 'package:flutter/material.dart';

class LeadsPaginationFooter extends StatelessWidget {
  final bool isLoading;
  final String searchQuery;
  final int currentPage;
  final bool canGoBack;
  final bool canGoNext;
  final VoidCallback onPreviousPressed;
  final VoidCallback onNextPressed;

  const LeadsPaginationFooter({
    super.key,
    required this.isLoading,
    required this.searchQuery,
    required this.currentPage,
    required this.canGoBack,
    required this.canGoNext,
    required this.onPreviousPressed,
    required this.onNextPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading || searchQuery.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: canGoBack ? onPreviousPressed : null,
          ),
          Text(
            '$currentPage',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: canGoNext ? onNextPressed : null,
          ),
        ],
      ),
    );
  }
}
