import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../Sync Head/sync_head_editing_approval.dart';

Future<void> editCustomerDialog({
  required BuildContext context,
  required Map<String, dynamic> customer,
  required Map<String, dynamic> widgetCustomer,
  required Function(Map<String, dynamic> updatedFields) onUpdated,
}) async {
  if (customer['pendingEditing'] == true || customer['pendingDeletion'] == true) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This customer is already pending approval and cannot be edited.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  final nameController = TextEditingController(text: customer['name'] ?? '');
  final addressController = TextEditingController(text: customer['address'] ?? '');
  final contact1Controller = TextEditingController(text: customer['contact1'] ?? customer['contact'] ?? '');
  final contact2Controller = TextEditingController(text: customer['contact2'] ?? '');
  final formKey = GlobalKey<FormState>();

  await showDialog(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        title: const Text('Edit Customer'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final newName = nameController.text.trim();
              final newAddress = addressController.text.trim();
              final newContact1 = contact1Controller.text.trim();
              final newContact2 = contact2Controller.text.trim();

              final oldName = (customer['name'] ?? '').toString().trim();
              final oldAddress = (customer['address'] ?? '').toString().trim();
              final oldContact1 =
                  (customer['contact1'] ?? customer['contact'] ?? '').toString().trim();
              final oldContact2 = (customer['contact2'] ?? '').toString().trim();

              final bool hasChanges = newName != oldName ||
                  newAddress != oldAddress ||
                  newContact1 != oldContact1 ||
                  newContact2 != oldContact2;

              if (!hasChanges) {
                Navigator.pop(dialogCtx);
                return;
              }

              Navigator.pop(dialogCtx);

              final updatedFields = {
                'name': newName,
                'address': newAddress,
                'contact1': newContact1,
                'contact2': newContact2,
                'contact': newContact1,
              };

              final user = FirebaseAuth.instance.currentUser;
              final docId = user?.email?.toLowerCase();

              final success = await SyncHeadEditingApprovalService.requestCustomerEdit(
                context: context,
                customer: customer,
                updatedFields: updatedFields,
                widgetCustomer: widgetCustomer,
                docId: docId,
              );

              if (success) {
                onUpdated({'pendingEditing': true});
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005BAC),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
