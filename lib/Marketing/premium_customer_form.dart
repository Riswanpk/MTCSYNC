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
  bool _photoError = false; // Add this line

  Future<void> _openCamera() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraPage()),
    );
    if (result != null && result is Map && result['image'] != null) {
      setState(() {
        _imageFile = result['image'];
        locationString = result['location']; // <-- Capture location here
      });
    }
  }

  Future<void> _submitForm() async {
    // Validate the form first
    if (!_formKey.currentState!.validate() || _imageFile == null) {
      setState(() {
        _photoError = _imageFile == null;
      });
      return;
    }

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
          fontSize: 12,
          fontFamily: 'Electorize',
        ),
        filled: true,
        fillColor: const Color.fromARGB(255, 241, 235, 188),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(22), // only top-right rounded
            topLeft: Radius.circular(0),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(0),
          ),
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
                  const SizedBox(height: 12),
                  Text(
                    'Premium Customer Visit Form',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Electorize',
                      color: Color(0xFF1E3D59),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // SECTION: CUSTOMER INFO
                  _buildSectionTitle('Customer Information'),
                  const SizedBox(height: 10),
                  // --- Shop Name with shadow and same size as other boxes ---
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 255, 255, 255),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(22),
                        topLeft: Radius.circular(0),
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      decoration: _inputDecoration('Shop Name'),
                      validator: (v) => v == null || v.isEmpty ? 'Enter shop name' : null,
                      onChanged: (v) => shopName = v,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // SECTION: PURCHASE HISTORY
                  _buildSectionTitle('Purchase History'),
                  const SizedBox(height: 10),
                  _buildDatePickerField(
                    label: 'Last Item Purchased Date',
                    date: lastItemPurchasedDate,
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
                  ),
                  const SizedBox(height: 15),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 255, 255, 255),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(22),
                        topLeft: Radius.circular(0),
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      decoration: _inputDecoration('Last Purchased Item'),
                      validator: (v) => v == null || v.isEmpty ? 'Enter last purchased item' : null,
                      onChanged: (v) => lastPurchasedItem = v,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // SECTION: ORDERS & ENQUIRIES
                  _buildSectionTitle('Orders & Enquiries'),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 194, 235, 241),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(22),
                        topLeft: Radius.circular(0),
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      decoration: _inputDecoration('Current Enquiries'),
                      validator: (v) => v == null || v.isEmpty ? 'Enter current enquiries' : null,
                      onChanged: (v) => currentEnquiries = v,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 194, 235, 241),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(22),
                        topLeft: Radius.circular(0),
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      decoration: _inputDecoration('Confirmed Order'),
                      validator: (v) => v == null || v.isEmpty ? 'Enter confirmed order' : null,
                      onChanged: (v) => confirmedOrder = v,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // SECTION: UPCOMING EVENTS
                  _buildSectionTitle('Upcoming Events'),
                  const SizedBox(height: 10),
                  _buildDatePickerField(
                    label: 'Upcoming Big Events Date',
                    date: upcomingEventDate,
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
                  ),
                  const SizedBox(height: 15),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 255, 255, 255),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(22),
                        topLeft: Radius.circular(0),
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      decoration: _inputDecoration('Upcoming Big Events Details'),
                      validator: (v) => v == null || v.isEmpty ? 'Enter event details' : null,
                      onChanged: (v) => upcomingEventDetails = v,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // SECTION: FEEDBACK & SUGGESTIONS
                  _buildSectionTitle('Feedback & Suggestions'),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 194, 235, 241),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(22),
                        topLeft: Radius.circular(0),
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      decoration: _inputDecoration('New Product Suggestion'),
                      validator: (v) => v == null || v.isEmpty ? 'Enter new product suggestion' : null,
                      onChanged: (v) => newProductSuggestion = v,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 194, 235, 241),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(22),
                        topLeft: Radius.circular(0),
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      decoration: _inputDecoration('Upcoming Trends'),
                      validator: (v) => v == null || v.isEmpty ? 'Enter upcoming trends' : null,
                      onChanged: (v) => upcomingTrends = v,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 194, 235, 241),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(22),
                        topLeft: Radius.circular(0),
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      decoration: _inputDecoration('Feedback About Our Product & Services'),
                      maxLines: 3,
                      validator: (v) => v == null || v.isEmpty ? 'Enter feedback' : null,
                      onChanged: (v) => feedback = v,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // SECTION: PHOTO
                  _buildSectionTitle('Attach Shop Photo'),
                  const SizedBox(height: 10),
                  _imageFile == null
                      ? OutlinedButton.icon(
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Take Photo'),
                          onPressed: _openCamera,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(22),
                                topLeft: Radius.circular(0),
                                bottomLeft: Radius.circular(22),
                                bottomRight: Radius.circular(0),
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_imageFile!, height: 150, fit: BoxFit.cover),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _imageFile = null),
                              child: const Text('Remove Photo'),
                            ),
                          ],
                        ),
                  if (_photoError)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Please attach a shop photo',
                        style: TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'Electorize'),
                      ),
                    ),
                  const SizedBox(height: 30),

                  // SUBMIT BUTTON
                  ElevatedButton(
                    onPressed: () {
                      if ((lastItemPurchasedDate == null && lastPurchasedMonth.trim().isEmpty) ||
                          (upcomingEventDate == null || upcomingEventDetails.trim().isEmpty)) {
                        setState(() {});
                        return;
                      }
                      _submitForm();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3D59),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(22),
                          topLeft: Radius.circular(0),
                          bottomLeft: Radius.circular(22),
                          bottomRight: Radius.circular(0),
                        ),
                      ),
                      elevation: 3,
                    ),
                    child: const Text('Submit'),
                  ),
                ],
              ),
            ),
          ),
  );
}

// --- Helpers for section titles and date fields ---
Widget _buildSectionTitle(String title) {
  return Text(
    title,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Color(0xFF34495E),
    ),
  );
}

Widget _buildDatePickerField({
  required String label,
  required DateTime? date,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    child: InputDecorator(
      decoration: _inputDecoration(label),
      child: Text(
        date != null
            ? "${date.day}/${date.month}/${date.year}"
            : 'Select date',
        style: TextStyle(
          color: date != null ? Colors.black : Colors.grey[600],
        ),
      ),
    ),
  );
}
}