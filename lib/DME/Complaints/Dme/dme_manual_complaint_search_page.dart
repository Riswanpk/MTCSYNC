import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mtcsync/DME/Misc/dme_config.dart';
import 'dme_register_complaint_page.dart';

class DmeManualComplaintSearchPage extends StatefulWidget {
  const DmeManualComplaintSearchPage({super.key});

  @override
  State<DmeManualComplaintSearchPage> createState() => _DmeManualComplaintSearchPageState();
}

class _DmeManualComplaintSearchPageState extends State<DmeManualComplaintSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isLoading = false;
          _hasSearched = false;
        });
      }
      return;
    }

    final client = await DmeConfig.getClient();
    if (client == null) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final res = await client
          .from('dme_customers')
          .select('id, name, phone, address, primary_branch, salesman, dme_customer_branches(branch_id, category_id, customer_type_id)')
          .or('name.ilike.%$cleanQuery%,phone.ilike.%$cleanQuery%')
          .order('name', ascending: true)
          .limit(30);

      if (mounted) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching customers: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Customer for Complaint'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? const Color(0xFF0F1B2B) : Colors.white,
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by customer name or phone number...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF005BAC)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_searchResults.isEmpty && _hasSearched)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No customers found for "${_searchController.text}"',
                      style: const TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else if (_searchResults.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_search_rounded, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    const Text(
                      'Type a name or phone number above\nto search customer and register complaint',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _searchResults.length,
                separatorBuilder: (context, i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final cust = _searchResults[index];
                  final name = cust['name']?.toString() ?? 'Unknown';
                  final phone = cust['phone']?.toString() ?? '';
                  final address = cust['address']?.toString() ?? '';
                  final branch = cust['primary_branch']?.toString() ?? '';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF005BAC),
                      child: Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phone,
                          style: const TextStyle(color: Color(0xFF005BAC), fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        if (address.isNotEmpty)
                          Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                    trailing: branch.isNotEmpty
                        ? Chip(
                            label: Text(
                              branch,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                            ),
                            backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.1),
                            padding: EdgeInsets.zero,
                          )
                        : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DmeRegisterComplaintPage(customer: cust),
                        ),
                      );
                      if (result == true && mounted) {
                        Navigator.pop(context, true);
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
