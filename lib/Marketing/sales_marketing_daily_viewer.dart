import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../Leads/leadsform.dart';

class SalesMarketingDailyViewer extends StatelessWidget {
  final String userId;

  const SalesMarketingDailyViewer({super.key, required this.userId});

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
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final query = FirebaseFirestore.instance
        .collection('marketing')
        .where('userid', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('timestamp', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Marketing Forms", style: TextStyle(fontFamily: 'Electorize', fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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
      backgroundColor: const Color(0xFFF0F2F5),
      body: FutureBuilder<QuerySnapshot>(
        future: query.get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                "No forms submitted today.",
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white38
                      : Colors.black38,
                  fontFamily: 'Electorize',
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
                        builder: (context) => MarketingFormDetailsPage(
                          docId: docs[index].id,
                          formData: data,
                          formType: formType,
                          displayName: displayName,
                        ),
                      ),
                    );
                  },
                ),
              )
              );
            },
          );
        },
      ),
    );
  }
}

class MarketingFormDetailsPage extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> formData;
  final String formType;
  final String displayName;

  const MarketingFormDetailsPage({
    super.key,
    required this.docId,
    required this.formData,
    required this.formType,
    required this.displayName,
  });

  bool _isPhoneNumberKey(String key) {
    final lowerKey = key.toLowerCase();
    return lowerKey.contains('phone') || lowerKey.contains('contact');
  }

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

  @override
  Widget build(BuildContext context) {
    final filteredData = Map.of(formData)
      ..remove('locationString')
      ..remove('imageUrl')
      ..remove('userid')
      ..remove('timestamp');

    // Helper to format phone number as +91 XXXXX YYYYY
    String formatIndianPhone(String raw) {
      final digits = RegExp(r'\d').allMatches(raw ?? '').map((m) => m.group(0)).join();
      if (digits.length >= 10) {
        final tenDigits = digits.substring(digits.length - 10);
        return '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
      }
      return '+91 ';
    }

    // Extract values for leads
    final String name = formData['shopName']?.toString() ?? '';
    final String address = formData['place']?.toString() ?? '';
    final String phoneRaw = formData['phoneNo']?.toString() ?? '';
    final String phone = formatIndianPhone(phoneRaw);

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
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => EditMarketingFormPage(
                    docId: docId,
                    formData: Map.of(filteredData)
                      ..remove('username')
                      ..remove('userid'),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A1A2E),
                                      fontSize: 14,
                                      fontFamily: 'Electorize',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    _isPhoneNumberKey(e.key) ? e.value.toString() : _formatIfDate(e.value),
                                    style: const TextStyle(fontSize: 15, fontFamily: 'Electorize', color: Color(0xFF444E5C)),
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add To Leads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Electorize')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: const Color(0xFF1A1A2E).withOpacity(0.3),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => FollowUpForm(
                        key: UniqueKey(),
                        initialName: name,
                        initialPhone: phone,
                        initialAddress: address,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _beautifyKey(String key) {
    return key
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp(r'^[a-z]'), (m) => m.group(0)!.toUpperCase())
        .trim();
  }
}

class EditMarketingFormPage extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> formData;

  const EditMarketingFormPage({super.key, required this.docId, required this.formData});

  @override
  State<EditMarketingFormPage> createState() => _EditMarketingFormPageState();
}

class _EditMarketingFormPageState extends State<EditMarketingFormPage> {
  late Map<String, TextEditingController> controllers;
  late Map<String, dynamic> fieldTypes;

  @override
  void initState() {
    super.initState();
    controllers = {};
    fieldTypes = {};

    widget.formData.forEach((key, value) {
      final lowerKey = key.toLowerCase();
      if (lowerKey.contains('phone') || lowerKey.contains('contact')) {
        controllers[key] = TextEditingController(text: value?.toString() ?? '');
        fieldTypes[key] = 'phone';
        return;
      }
      if (value is Timestamp || value is DateTime) {
        final dt = value is Timestamp ? value.toDate() : value;
        controllers[key] = TextEditingController(text: DateFormat('dd MMM yyyy').format(dt));
        fieldTypes[key] = 'date';
      } else if (value is String) {
        try {
          final dt = DateTime.parse(value);
          controllers[key] = TextEditingController(text: DateFormat('dd MMM yyyy').format(dt));
          fieldTypes[key] = 'date';
        } catch (_) {
          controllers[key] = TextEditingController(text: value);
          fieldTypes[key] = 'text';
        }
      } else {
        controllers[key] = TextEditingController(text: value?.toString() ?? '');
        fieldTypes[key] = 'text';
      }
    });
  }

  Future<void> _pickDate(BuildContext context, String key) async {
    DateTime? initialDate;
    try {
      initialDate = DateFormat('dd MMM yyyy').parse(controllers[key]!.text);
    } catch (_) {
      initialDate = DateTime.now();
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        controllers[key]!.text = DateFormat('dd MMM yyyy').format(picked);
      });
    }
  }

  @override
  void dispose() {
    for (var c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Form', style: TextStyle(fontFamily: 'Electorize', fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ...controllers.entries.map((entry) {
              final key = entry.key;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: TextFormField(
                  controller: entry.value,                  readOnly: fieldTypes[key] == 'date',
                  keyboardType: fieldTypes[key] == 'phone' ? TextInputType.phone : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: _beautifyKey(key),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: fieldTypes[key] == 'date'
                        ? const Icon(Icons.calendar_today_rounded)
                        : fieldTypes[key] == 'phone'
                            ? const Icon(Icons.phone_rounded)
                            : const Icon(Icons.edit_rounded),
                  ),
                  onTap: fieldTypes[key] == 'date'
                      ? () => _pickDate(context, key)
                      : null,
                ),
              );
            }),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final updatedData = <String, dynamic>{};

                controllers.forEach((key, controller) {
                  if (fieldTypes[key] == 'phone') {
                    updatedData[key] = controller.text;
                  } else if (fieldTypes[key] == 'date') {
                    try {
                      final dt = DateFormat('dd MMM yyyy').parse(controller.text);
                      updatedData[key] = Timestamp.fromDate(dt);
                    } catch (_) {
                      updatedData[key] = controller.text;
                    }
                  } else {
                    updatedData[key] = controller.text;
                  }
                });

                await FirebaseFirestore.instance
                    .collection('marketing')
                    .doc(widget.docId)
                    .update(updatedData);

                if (context.mounted) Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
                shadowColor: const Color(0xFF1A1A2E).withOpacity(0.3),
              ),
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: const Text(
                'Save Changes',
                style: TextStyle(fontSize: 16, color: Colors.white, fontFamily: 'Electorize'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _beautifyKey(String key) {
    return key
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp(r'^[a-z]'), (m) => m.group(0)!.toUpperCase())
        .trim();
  }
}
