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
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Marketing Forms"),
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
                "No forms submitted today.",
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
        title: Text('$formType Details'),
        centerTitle: true,
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 3,
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
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          formType,
                          style: const TextStyle(fontSize: 16, color: Colors.black54),
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
                                      color: Color(0xFF005BAC),
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    _isPhoneNumberKey(e.key) ? e.value.toString() : _formatIfDate(e.value),
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add To Leads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        title: const Text('Edit Form'),
        centerTitle: true,
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 3,
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
                backgroundColor: const Color(0xFF005BAC),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: const Text(
                'Save Changes',
                style: TextStyle(fontSize: 16, color: Colors.white),
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
