import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SalesMarketingMonthlyViewer extends StatelessWidget {
  final String userId;

  const SalesMarketingMonthlyViewer({super.key, required this.userId});

  String _getFormType(Map<String, dynamic> data) {
    if (data.containsKey('firmName')) return 'Hotel/Resort Customer';
    if (data.containsKey('natureOfBusiness')) return 'General Customer';
    return 'Premium Customer';
  }

  String _getDisplayName(Map<String, dynamic> data) {
    if (data.containsKey('shopName')) return data['shopName'] ?? '';
    if (data.containsKey('firmName')) return data['firmName'] ?? '';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final query = FirebaseFirestore.instance
        .collection('marketing')
        .where('userid', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .orderBy('timestamp', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(
        title: const Text("This Month's Marketing Forms", style: TextStyle(fontFamily: 'Electorize', fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        centerTitle: true,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F0F1E)
          : const Color(0xFFF0F2F5),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                "No forms submitted this month.",
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.black54,
                ),
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final formType = _getFormType(data);
              final displayName = _getDisplayName(data);

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 3,
                shadowColor: (formType == 'Premium Customer'
                        ? const Color(0xFFD4AF37)
                        : formType == 'General Customer'
                            ? const Color(0xFFFF6B35)
                            : const Color(0xFF009688))
                    .withOpacity(0.15),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border(
                      left: BorderSide(
                        color: formType == 'Premium Customer'
                            ? const Color(0xFFD4AF37)
                            : formType == 'General Customer'
                                ? const Color(0xFFFF6B35)
                                : const Color(0xFF009688),
                        width: 4,
                      ),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: (formType == 'Premium Customer'
                              ? const Color(0xFFD4AF37)
                              : formType == 'General Customer'
                                  ? const Color(0xFFFF6B35)
                                  : const Color(0xFF009688))
                          .withOpacity(0.12),
                      child: Icon(
                        formType == 'Premium Customer'
                            ? Icons.workspace_premium_rounded
                            : formType == 'General Customer'
                                ? Icons.storefront_rounded
                                : Icons.hotel_rounded,
                        color: formType == 'Premium Customer'
                            ? const Color(0xFFD4AF37)
                            : formType == 'General Customer'
                                ? const Color(0xFFFF6B35)
                                : const Color(0xFF009688),
                      ),
                    ),
                    title: Text(
                      displayName.isNotEmpty ? displayName : 'No Name',
                      style: const TextStyle(
                        fontFamily: 'Electorize',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      formType,
                      style: TextStyle(
                        fontFamily: 'Electorize',
                        color: formType == 'Premium Customer'
                            ? const Color(0xFFD4AF37)
                            : formType == 'General Customer'
                                ? const Color(0xFFFF6B35)
                                : const Color(0xFF009688),
                        fontSize: 12,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: (formType == 'Premium Customer'
                              ? const Color(0xFFD4AF37)
                              : formType == 'General Customer'
                                  ? const Color(0xFFFF6B35)
                                  : const Color(0xFF009688))
                          .withOpacity(0.6),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => MonthlyMarketingFormDetailsPage(
                            formData: data,
                            formType: formType,
                            displayName: displayName,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class MonthlyMarketingFormDetailsPage extends StatelessWidget {
  final Map<String, dynamic> formData;
  final String formType;
  final String displayName;

  const MonthlyMarketingFormDetailsPage({
    super.key,
    required this.formData,
    required this.formType,
    required this.displayName,
  });

  String _formatIfDate(dynamic value) {
    if (value is Timestamp) {
      return DateFormat('dd MMM yyyy').format(value.toDate());
    }
    if (value is DateTime) {
      return DateFormat('dd MMM yyyy').format(value);
    }
    if (value is String) {
      try {
        return DateFormat('dd MMM yyyy').format(DateTime.parse(value));
      } catch (_) {}
    }
    return value.toString();
  }

  bool _isPhoneNumberKey(String key) {
    final lowerKey = key.toLowerCase();
    return lowerKey.contains('phone') || lowerKey.contains('contact');
  }

  String _formatIndianPhone(String raw) {
    final digits = RegExp(r'\d').allMatches(raw ?? '').map((m) => m.group(0)).join();
    if (digits.length >= 10) {
      final tenDigits = digits.substring(digits.length - 10);
      return '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
    }
    return '+91 ';
  }

  String _beautifyKey(String key) {
    return key
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp(r'^[a-z]'), (m) => m.group(0)!.toUpperCase())
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final filteredData = Map.of(formData)
      ..removeWhere((key, value) => ['locationString', 'imageUrl', 'userid', 'timestamp'].contains(key));

    return Scaffold(
      appBar: AppBar(
        title: Text('$formType Details', style: const TextStyle(fontFamily: 'Electorize', fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        centerTitle: true,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F0F1E)
          : const Color(0xFFF0F2F5),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Card(
          elevation: 3,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: ListView(
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    displayName.isNotEmpty ? displayName : 'No Name',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Electorize'),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    formType,
                    style: const TextStyle(fontSize: 14, fontFamily: 'Electorize', color: Color(0xFF16213E)),
                  ),
                ),
                const Divider(height: 32, thickness: 1.2),
                ...filteredData.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${_beautifyKey(e.key)}:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white70
                                    : const Color(0xFF1A1A2E),
                                fontSize: 14,
                                fontFamily: 'Electorize',
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              _isPhoneNumberKey(e.key)
                                  ? _formatIndianPhone(e.value?.toString() ?? '')
                                  : _formatIfDate(e.value),
                              style: TextStyle(
                                fontSize: 15,
                                fontFamily: 'Electorize',
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white54
                                    : const Color(0xFF444E5C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}