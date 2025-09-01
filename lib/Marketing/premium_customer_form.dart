import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'camera_page.dart';

class PremiumCustomerForm extends StatefulWidget {
  final String username;
  final String userid;
  final String branch;

  const PremiumCustomerForm({
    super.key,
    required this.username,
    required this.userid,
    required this.branch,
  });

  @override
  State<PremiumCustomerForm> createState() => _PremiumCustomerFormState();
}

class _PremiumCustomerFormState extends State<PremiumCustomerForm> {
  final _formKey = GlobalKey<FormState>();
  String shopName = '';
  DateTime? lastItemPurchasedDate;
  String lastPurchasedMonth = '';
  String lastPurchasedItem = '';
  String currentEnquiries = '';
  String confirmedOrder = '';
  DateTime? upcomingEventDate;
  String upcomingEventDetails = '';
  String newProductSuggestion = '';
  String upcomingTrends = '';
  String feedback = '';
  File? _imageFile;
  bool isLoading = false;
  String? locationString;

  Future<void> _openCamera() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraPage()),
    );
    if (result != null && result is Map && result['image'] != null) {
      setState(() {
        _imageFile = result['image'];
      });
    }
  }

  Future<void> _submitForm() async {
    // Validate the form first
    if (!_formKey.currentState!.validate()) return;

    // Custom validation for required fields that are not handled by Form validators
    if ((lastItemPurchasedDate == null && lastPurchasedMonth.trim().isEmpty) ||
        (upcomingEventDate == null || upcomingEventDetails.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields.')),
      );
      return;
    }

    setState(() => isLoading = true);

    String? imageUrl;
    if (_imageFile != null) {
      final ref = FirebaseStorage.instance
          .ref()
          .child('marketing')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(_imageFile!);
      imageUrl = await ref.getDownloadURL();
    }

    await FirebaseFirestore.instance.collection('marketing').add({
      'formType': 'Premium Customer',
      'username': widget.username,
      'userid': widget.userid,
      'branch': widget.branch,
      'shopName': shopName,
      'lastItemPurchasedDate': lastItemPurchasedDate,
      'lastPurchasedMonth': lastPurchasedMonth,
      'lastPurchasedItem': lastPurchasedItem,
      'currentEnquiries': currentEnquiries,
      'confirmedOrder': confirmedOrder,
      'upcomingEventDate': upcomingEventDate,
      'upcomingEventDetails': upcomingEventDetails,
      'newProductSuggestion': newProductSuggestion,
      'upcomingTrends': upcomingTrends,
      'feedback': feedback,
      'imageUrl': imageUrl,
      'locationString': locationString, // <-- Add this line
      'timestamp': FieldValue.serverTimestamp(),
    });

    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Form submitted successfully!')),
    );
    _formKey.currentState!.reset();
    setState(() {
      _imageFile = null;
      lastItemPurchasedDate = null;
      lastPurchasedMonth = '';
      upcomingEventDate = null;
      upcomingEventDetails = '';
      locationString = null; // <-- Reset
    });
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 16,
          fontFamily: 'Electorize', // Ensure Electorize is used for labels too
        ),
        filled: true,
        fillColor: const Color(0xFFF7F2F2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      );

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Electorize'),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'Premium Customer Visit Form',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontFamily: 'Electorize',
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // SHOP NAME
                    TextFormField(
                      decoration: _inputDecoration('SHOP NAME '),
                      validator: (v) => v == null || v.isEmpty ? 'Enter shop name' : null,
                      onChanged: (v) => shopName = v,
                    ),
                    const SizedBox(height: 10),

                    // LAST ITEM PURCHASED DATE/MONTH (Date Picker)
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: lastItemPurchasedDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() {
                                  lastItemPurchasedDate = picked;
                                  lastPurchasedMonth = '';
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: _inputDecoration('LAST ITEM PURCHASED DATE '),
                              child: Text(
                                lastItemPurchasedDate != null
                                    ? "${lastItemPurchasedDate!.day}/${lastItemPurchasedDate!.month}/${lastItemPurchasedDate!.year}"
                                    : 'Select date',
                                style: TextStyle(
                                  color: lastItemPurchasedDate != null ? Colors.black : Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // LAST PURCHASED ITEM
                    TextFormField(
                      decoration: _inputDecoration('LAST PURCHASED ITEM '),
                      validator: (v) => v == null || v.isEmpty ? 'Enter last purchased item' : null,
                      onChanged: (v) => lastPurchasedItem = v,
                    ),
                    const SizedBox(height: 10),

                    // CURRENT ENQUIRIES
                    TextFormField(
                      decoration: _inputDecoration('CURRENT ENQUIRIES '),
                      validator: (v) => v == null || v.isEmpty ? 'Enter current enquiries' : null,
                      onChanged: (v) => currentEnquiries = v,
                    ),
                    const SizedBox(height: 10),

                    // CONFIRMED ORDER
                    TextFormField(
                      decoration: _inputDecoration('CONFIRMED ORDER '),
                      validator: (v) => v == null || v.isEmpty ? 'Enter confirmed order' : null,
                      onChanged: (v) => confirmedOrder = v,
                    ),
                    const SizedBox(height: 10),

                    // UPCOMING BIG EVENTS DATE
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: upcomingEventDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          setState(() {
                            upcomingEventDate = picked;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: _inputDecoration('UPCOMING BIG EVENTS DATE '),
                        child: Text(
                          upcomingEventDate != null
                              ? "${upcomingEventDate!.day}/${upcomingEventDate!.month}/${upcomingEventDate!.year}"
                              : 'Select date',
                          style: TextStyle(
                            color: upcomingEventDate != null ? Colors.black : Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // UPCOMING BIG EVENTS DETAILS
                    TextFormField(
                      decoration: _inputDecoration('UPCOMING BIG EVENTS DETAILS '),
                      validator: (v) => v == null || v.isEmpty ? 'Enter event details' : null,
                      onChanged: (v) => upcomingEventDetails = v,
                    ),
                    const SizedBox(height: 10),

                    // NEW PRODUCT SUGGESTION
                    TextFormField(
                      decoration: _inputDecoration('NEW PRODUCT SUGGESTION '),
                      validator: (v) => v == null || v.isEmpty ? 'Enter new product suggestion' : null,
                      onChanged: (v) => newProductSuggestion = v,
                    ),
                    const SizedBox(height: 10),

                    // UPCOMING TRENDS
                    TextFormField(
                      decoration: _inputDecoration('UPCOMING TRENDS '),
                      validator: (v) => v == null || v.isEmpty ? 'Enter upcoming trends' : null,
                      onChanged: (v) => upcomingTrends = v,
                    ),
                    const SizedBox(height: 10),

                    // FEEDBACK ABOUT OUR PRODUCT AND SERVICES
                    TextFormField(
                      decoration: _inputDecoration('FEED BACK ABOUT OUR PRODUCT AND SERVICES '),
                      maxLines: 2,
                      validator: (v) => v == null || v.isEmpty ? 'Enter feedback' : null,
                      onChanged: (v) => feedback = v,
                    ),
                    const SizedBox(height: 20),

                    // CAMERA IMAGE
                    Text(
                      'Attach Shop Photo',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Electorize',
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _imageFile == null
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Take Photo'),
                            onPressed: _openCamera,
                          )
                        : Column(
                            children: [
                              Image.file(_imageFile!, height: 120),
                              TextButton(
                                onPressed: () => setState(() => _imageFile = null),
                                child: const Text('Remove Photo'),
                              ),
                            ],
                          ),
                    const SizedBox(height: 28),

                    ElevatedButton(
                      onPressed: () {
                        // Custom validation for date/month and event fields
                        if ((lastItemPurchasedDate == null && lastPurchasedMonth.trim().isEmpty) ||
                            (upcomingEventDate == null || upcomingEventDetails.trim().isEmpty)) {
                          setState(() {}); // To show error messages
                          return;
                        }
                        _submitForm();
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: const Text('Submit'),
                    ),
                  ],
                ),
              ),
          )
    );
  }
}