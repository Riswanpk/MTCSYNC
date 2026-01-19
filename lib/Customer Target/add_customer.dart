import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class AddCustomerPage extends StatefulWidget {
  @override
  State<AddCustomerPage> createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends State<AddCustomerPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _contactCtrl = TextEditingController();
  final TextEditingController _contact2Ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _addCustomer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Not logged in");

      final now = DateTime.now();
      final monthYear = "${_monthName(now.month)} ${now.year}";
      final docRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(user.email);

      final docSnap = await docRef.get();
      List customers = [];
      if (docSnap.exists && docSnap.data()?['customers'] != null) {
        customers = List.from(docSnap.data()!['customers']);
      }
      customers.add({
        'name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'contact1': _contactCtrl.text.trim(),
        'contact2': _contact2Ctrl.text.trim(),
        'callMade': false,
        'remarks': '',
      });
      await docRef.set({
        'user': user.email,
        'customers': customers,
        'updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = "Failed to add: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // Helper to get month name
  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Customer', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF8CC63F),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Customer Name'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Address'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter address' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactCtrl,
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _contact2Ctrl,
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
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _addCustomer,
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add Customer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8CC63F),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
