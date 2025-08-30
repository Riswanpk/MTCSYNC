import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HotelResortCustomerForm extends StatelessWidget {
  final String username;
  final String userid;
  final String branch;

  const HotelResortCustomerForm({
    super.key,
    required this.username,
    required this.userid,
    required this.branch,
  });

  Future<void> submitForm(String imageUrl) async {
    await FirebaseFirestore.instance.collection('marketing').add({
      'formType': 'Hotel / Resort Customer',
      // ...other fields...
      'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return const DefaultTextStyle(
      style: TextStyle(fontFamily: 'Electorize'),
      child: Center(
        child: Text('Hotel / Resort Customer Form (to be implemented)'),
      ),
    );
  }
}