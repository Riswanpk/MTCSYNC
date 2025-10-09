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
  bool _lastPurchaseError = false;
  bool _upcomingEventError = false;

  // Add error flags for all fields
  bool _shopNameError = false;
  bool _lastPurchasedItemError = false;
  bool _currentEnquiriesError = false;
  bool _confirmedOrderError = false;
  bool _upcomingEventDetailsError = false;
  bool _newProductSuggestionError = false;
  bool _upcomingTrendsError = false;
  bool _feedbackError = false;

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
    // Validate all fields manually
    setState(() {
      _shopNameError = shopName.trim().isEmpty;
      _lastPurchaseError = (lastItemPurchasedDate == null );
      _lastPurchasedItemError = lastPurchasedItem.trim().isEmpty;
      _currentEnquiriesError = currentEnquiries.trim().isEmpty;
      _confirmedOrderError = confirmedOrder.trim().isEmpty;
      _upcomingEventError = (upcomingEventDate == null);
      _upcomingEventDetailsError = upcomingEventDetails.trim().isEmpty;
      _newProductSuggestionError = newProductSuggestion.trim().isEmpty;
      _upcomingTrendsError = upcomingTrends.trim().isEmpty;
      _feedbackError = feedback.trim().isEmpty;
      _photoError = _imageFile == null;
    });

    bool hasError = _shopNameError ||
        _lastPurchaseError ||
        _lastPurchasedItemError ||
        _currentEnquiriesError ||
        _confirmedOrderError ||
        _upcomingEventError ||
        _upcomingEventDetailsError ||
        _newProductSuggestionError ||
        _upcomingTrendsError ||
        _feedbackError ||
        _photoError;

    if (hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields.')),
      );
      // Do NOT reset the form or clear fields!
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
      'lastPurchasedItem': lastPurchasedItem,
      'currentEnquiries': currentEnquiries,
      'confirmedOrder': confirmedOrder,
      'upcomingEventDate': upcomingEventDate,
      'upcomingEventDetails': upcomingEventDetails,
      'newProductSuggestion': newProductSuggestion,
      'upcomingTrends': upcomingTrends,
      'feedback': feedback,
      'imageUrl': imageUrl,
      'locationString': locationString,
      'timestamp': FieldValue.serverTimestamp(),
    });

    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Form submitted successfully!')),
    );

    // Reset the form and all fields
    _formKey.currentState!.reset();
    setState(() {
      _imageFile = null;
      lastItemPurchasedDate = null;
      upcomingEventDate = null;
      upcomingEventDetails = '';
      locationString = null;
      shopName = '';
      lastPurchasedItem = '';
      currentEnquiries = '';
      confirmedOrder = '';
      newProductSuggestion = '';
      upcomingTrends = '';
      feedback = '';
      // Reset all error flags
      _shopNameError = false;
      _lastPurchaseError = false;
      _lastPurchasedItemError = false;
      _currentEnquiriesError = false;
      _confirmedOrderError = false;
      _upcomingEventError = false;
      _upcomingEventDetailsError = false;
      _newProductSuggestionError = false;
      _upcomingTrendsError = false;
      _feedbackError = false;
      _photoError = false;
    });
  }

  InputDecoration _inputDecoration(String label, {bool error = false, String? errorText}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontFamily: 'Electorize',
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[900]
            : const Color.fromARGB(255, 241, 235, 188),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(22),
            topLeft: Radius.circular(0),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(0),
          ),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        errorText: error ? errorText : null,
        errorStyle: const TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'Electorize'),
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
                        initialValue: shopName,
                        decoration: _inputDecoration(
                          'Shop Name',
                          error: _shopNameError,
                          errorText: 'Enter shop name',
                        ),
                        onChanged: (v) {
                          setState(() {
                            shopName = v;
                            if (v.trim().isNotEmpty) _shopNameError = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // SECTION: PURCHASE HISTORY
                    _buildSectionTitle('Purchase History'),
                    const SizedBox(height: 10),
                    _buildDatePickerField(
                      label: 'Last Item Purchased Date',
                      date: lastItemPurchasedDate,
                      error: _lastPurchaseError,
                      errorText: 'Please select last purchase date or month',
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
                            _lastPurchaseError = false;
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
                        initialValue: lastPurchasedItem,
                        decoration: _inputDecoration(
                          'Last Purchased Item',
                          error: _lastPurchasedItemError,
                          errorText: 'Enter last purchased item',
                        ),
                        onChanged: (v) {
                          setState(() {
                            lastPurchasedItem = v;
                            if (v.trim().isNotEmpty) _lastPurchasedItemError = false;
                          });
                        },
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
                        initialValue: currentEnquiries,
                        decoration: _inputDecoration(
                          'Current Enquiries',
                          error: _currentEnquiriesError,
                          errorText: 'Enter current enquiries',
                        ),
                        onChanged: (v) {
                          setState(() {
                            currentEnquiries = v;
                            if (v.trim().isNotEmpty) _currentEnquiriesError = false;
                          });
                        },
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
                        initialValue: confirmedOrder,
                        decoration: _inputDecoration(
                          'Confirmed Order',
                          error: _confirmedOrderError,
                          errorText: 'Enter confirmed order',
                        ),
                        onChanged: (v) {
                          setState(() {
                            confirmedOrder = v;
                            if (v.trim().isNotEmpty) _confirmedOrderError = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // SECTION: UPCOMING EVENTS
                    _buildSectionTitle('Upcoming Events'),
                    const SizedBox(height: 10),
                    _buildDatePickerField(
                      label: 'Upcoming Big Events Date',
                      date: upcomingEventDate,
                      error: _upcomingEventError,
                      errorText: 'Please select upcoming event date',
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
                            _upcomingEventError = false;
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
                        initialValue: upcomingEventDetails,
                        decoration: _inputDecoration(
                          'Upcoming Big Events Details',
                          error: _upcomingEventDetailsError,
                          errorText: 'Enter event details',
                        ),
                        onChanged: (v) {
                          setState(() {
                            upcomingEventDetails = v;
                            if (v.trim().isNotEmpty) _upcomingEventDetailsError = false;
                          });
                        },
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
                        initialValue: newProductSuggestion,
                        decoration: _inputDecoration(
                          'New Product Suggestion',
                          error: _newProductSuggestionError,
                          errorText: 'Enter new product suggestion',
                        ),
                        onChanged: (v) {
                          setState(() {
                            newProductSuggestion = v;
                            if (v.trim().isNotEmpty) _newProductSuggestionError = false;
                          });
                        },
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
                        initialValue: upcomingTrends,
                        decoration: _inputDecoration(
                          'Upcoming Trends',
                          error: _upcomingTrendsError,
                          errorText: 'Enter upcoming trends',
                        ),
                        onChanged: (v) {
                          setState(() {
                            upcomingTrends = v;
                            if (v.trim().isNotEmpty) _upcomingTrendsError = false;
                          });
                        },
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
                        initialValue: feedback,
                        maxLines: 3,
                        decoration: _inputDecoration(
                          'Feedback About Our Product & Services',
                          error: _feedbackError,
                          errorText: 'Enter feedback',
                        ),
                        onChanged: (v) {
                          setState(() {
                            feedback = v;
                            if (v.trim().isNotEmpty) _feedbackError = false;
                          });
                        },
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
                      onPressed: _submitForm,
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
    bool error = false,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          child: InputDecorator(
            decoration: _inputDecoration(label, error: error, errorText: errorText),
            child: Text(
              date != null
                  ? "${date.day}/${date.month}/${date.year}"
                  : 'Select date',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
        ),
        if (error && errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'Electorize'),
            ),
          ),
      ],
    );
  }
}