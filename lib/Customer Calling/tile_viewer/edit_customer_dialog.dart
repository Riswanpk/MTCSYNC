import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> editCustomerDialog({
  required BuildContext context,
  required Map<String, dynamic> customer,
  required Map<String, dynamic> widgetCustomer,
  required Function(Map<String, dynamic> updatedFields) onUpdated,
}) async {
  final nameController = TextEditingController(text: customer['name'] ?? '');
  final addressController = TextEditingController(text: customer['address'] ?? '');
  final contact1Controller = TextEditingController(text: customer['contact1'] ?? customer['contact'] ?? '');
  final contact2Controller = TextEditingController(text: customer['contact2'] ?? '');
  final formKey = GlobalKey<FormState>();
  bool loading = false;
  String? error;

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Customer'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(error!, style: const TextStyle(color: Colors.red)),
                  ),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Customer Name'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter address' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: contact1Controller,
                  decoration: const InputDecoration(labelText: 'Contact Number 1'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter contact';
                    if (v.length != 10) return 'Enter exactly 10 digits';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: contact2Controller,
                  decoration: const InputDecoration(labelText: 'Contact Number 2 (optional)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length != 10) return 'Enter exactly 10 digits';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => loading = true);
                      try {
                        final updated = {
                          'name': nameController.text.trim(),
                          'address': addressController.text.trim(),
                          'contact1': contact1Controller.text.trim(),
                          'contact2': contact2Controller.text.trim(),
                          'contact': contact1Controller.text.trim(),
                        };
                        onUpdated(updated);

                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null && user.email != null) {
                          final docId = user.email!.toLowerCase();
                          final now = DateTime.now();
                          final months = [
                            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                          ];
                          final monthYear = "${months[now.month - 1]} ${now.year}";
                          final docRef = FirebaseFirestore.instance
                              .collection('customer_target')
                              .doc(monthYear)
                              .collection('users')
                              .doc(docId);
                          final doc = await docRef.get();
                          if (doc.exists && doc.data()?['customers'] != null) {
                            List customers = List.from(doc.data()!['customers']);
                            int idx = customers.indexWhere((c) =>
                                (c['name'] == widgetCustomer['name'] &&
                                 (c['contact1'] ?? c['contact']) == (widgetCustomer['contact1'] ?? widgetCustomer['contact'])));
                            if (idx != -1) {
                              customers[idx]['name'] = nameController.text.trim();
                              customers[idx]['address'] = addressController.text.trim();
                              customers[idx]['contact1'] = contact1Controller.text.trim();
                              customers[idx]['contact2'] = contact2Controller.text.trim();
                              customers[idx]['contact'] = contact1Controller.text.trim();
                              await docRef.update({'customers': customers});
                            }
                          }
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setState(() {
                            error = 'Failed to update: $e';
                            loading = false;
                          });
                        }
                      }
                    },
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
}
