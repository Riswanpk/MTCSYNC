import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GeneralCustomerForm extends StatelessWidget {
  final String username;
  final String userid;
  final String branch;

  const GeneralCustomerForm({
    super.key,
    required this.username,
    required this.userid,
    required this.branch,
  });

  @override
  Widget build(BuildContext context) {
    return const DefaultTextStyle(
      style: TextStyle(fontFamily: 'Electorize'),
      child: Center(
        child: Text('General Customer Form (to be implemented)'),
      ),
    );
  }

  Future<void> submitForm(String imageUrl) async {
    // Example for your submit logic:
    await FirebaseFirestore.instance.collection('marketing').add({
      'formType': 'General Customer',
      // ...other fields...
      'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}