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
        .orderBy('timestamp', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text("This Month's Marketing Forms"),
        centerTitle: true,
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 3,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No forms submitted this month.",
                style: TextStyle(fontSize: 16, color: Colors.black54),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: Colors.black26,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF005BAC).withOpacity(0.1),
                    child: Icon(
                      formType == 'Premium Customer'
                          ? Icons.star
                          : formType == 'General Customer'
                              ? Icons.store
                              : Icons.hotel,
                      color: const Color(0xFF005BAC),
                    ),
                  ),
                  title: Text(
                    displayName.isNotEmpty ? displayName : 'No Name',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    formType,
                    style: const TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.black38),
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
        title: Text('$formType Details'),
        centerTitle: true,
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 3,
      ),
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
                ...filteredData.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${_beautifyKey(e.key)}:',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF005BAC),
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              _formatIfDate(e.value),
                              style: const TextStyle(fontSize: 16),
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