import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'camera_page.dart';
import 'dart:io';
import 'package:flutter/services.dart'; // Add this import
import 'package:firebase_storage/firebase_storage.dart'; // Add this import

class HotelResortCustomerForm extends StatefulWidget {
  final String username;
  final String userid;
  final String branch;

  const HotelResortCustomerForm({
    super.key,
    required this.username,
    required this.userid,
    required this.branch,
  });

  @override
  State<HotelResortCustomerForm> createState() =>
      _HotelResortCustomerFormState();
}

class _HotelResortCustomerFormState extends State<HotelResortCustomerForm> {
  final _formKey = GlobalKey<FormState>();
  DateTime? date;
  String firmName = '';
  String place = '';
  String contactPerson = '';
  String contactNumber = '';
  String category = '';
  String currentEnquiry = '';
  String confirmedOrder = '';
  String newProductSuggestion = '';
  String feedback1 = '';
  String feedback2 = '';
  String feedback3 = '';
  String feedback4 = '';
  String feedback5 = '';
  String anySuggestion = '';
  bool isLoading = false;
  File? _imageFile;
  String? locationString;
  bool _photoError = false;
  int feedbackRating = 0;
  String customCategory = ''; // <-- Add this line

  // Error flags for each field
  bool _firmNameError = false;
  bool _placeError = false;
  bool _contactPersonError = false;
  bool _contactNumberError = false;
  bool _dateError = false;
  bool _categoryError = false;
  bool _currentEnquiryError = false;
  bool _newProductSuggestionError = false;
  bool _feedbackRatingError = false;
  bool _customCategoryError = false; // <-- Add this line

  // 🔹 Unified InputDecoration (used inside reusable textfield)
  InputDecoration _inputDecoration(
    String label, {
    bool required = false,
    bool error = false,
    String? errorText,
  }) =>
      InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: const TextStyle(
          fontSize: 16,
          fontFamily: 'Electorize',
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[900]
            : const Color.fromARGB(255, 255, 255, 255),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        errorText: error ? errorText : null,
        errorStyle: const TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'Electorize'),
      );

  // 🔹 Reusable styled textfield with shadow & corners
  Widget _buildTextField({
    required String label,
    bool required = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Function(String)? onChanged,
    List<TextInputFormatter>? inputFormatters, // Add this line
    bool error = false,
    String? errorText,
    String? initialValue,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 255, 255),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(22),
          bottomLeft: Radius.circular(22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        decoration: _inputDecoration(label, required: required, error: error, errorText: errorText),
        validator: validator,
        onChanged: (v) {
          if (onChanged != null) onChanged(v);
          setState(() {
            if (label == 'FIRM NAME') _firmNameError = v.trim().isEmpty;
            if (label == 'PLACE') _placeError = v.trim().isEmpty;
            if (label == 'CONTACT PERSON NAME') _contactPersonError = v.trim().isEmpty;
            if (label == 'CONTACT NUMBER') _contactNumberError = v.trim().isEmpty || v.length != 10;
            if (label == 'CURRENT ENQUIRY') _currentEnquiryError = v.trim().isEmpty;
            if (label == 'NEW PRODUCT SUGGESTION') _newProductSuggestionError = v.trim().isEmpty;
          });
        },
        inputFormatters: inputFormatters, // Add this line
      ),
    );
  }

  Future<void> _openCamera() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraPage()),
    );
    if (result != null && result is Map && result['image'] != null) {
      setState(() {
        _imageFile = result['image'];
        locationString = result['location'];
      });
    }
  }

  Future<void> _submitForm() async {
    setState(() {
      _firmNameError = firmName.trim().isEmpty;
      _placeError = place.trim().isEmpty;
      _contactPersonError = contactPerson.trim().isEmpty;
      _contactNumberError = contactNumber.trim().isEmpty || contactNumber.length != 10;
      _dateError = date == null;
      _categoryError = category.isEmpty;
      _customCategoryError = category == 'OTHERS' && customCategory.trim().isEmpty; // <-- Add this line
      _currentEnquiryError = currentEnquiry.trim().isEmpty;
      _newProductSuggestionError = newProductSuggestion.trim().isEmpty;
      _feedbackRatingError = feedbackRating == 0;
      _photoError = _imageFile == null;
    });

    bool hasError =_firmNameError ||
        _placeError ||
        _contactPersonError ||
        _contactNumberError ||
        _dateError ||
        _categoryError ||
        _customCategoryError || // <-- Add this line
        _currentEnquiryError ||
        _newProductSuggestionError ||
        _feedbackRatingError ||
        _photoError;

    if (hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields.')),
      );
      return;
    }

    setState(() {
      isLoading = true;
      _photoError = false;
    });

    String? imageUrl;
    if (_imageFile != null) {
      try {
        final ref = FirebaseStorage.instance
            .ref()
            .child('marketing')
            .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_imageFile!);
        imageUrl = await ref.getDownloadURL();
      } catch (e) {
        imageUrl = null;
      }
    }

    await FirebaseFirestore.instance.collection('marketing').add({
      'formType': 'Hotel / Resort Customer',
      'username': widget.username,
      'userid': widget.userid,
      'branch': widget.branch,
      'date': date,
      'firmName': firmName,
      'place': place,
      'contactPerson': contactPerson,
      'contactNumber': contactNumber,
      'category': category == 'OTHERS' && customCategory.trim().isNotEmpty
          ? customCategory
          : category, // <-- Save custom category if OTHERS
      'currentEnquiry': currentEnquiry,
      'confirmedOrder': confirmedOrder,
      'newProductSuggestion': newProductSuggestion,
      'anySuggestion': anySuggestion,
      'locationString': locationString,
      'feedbackRating': feedbackRating,
      'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });

    setState(() {
      isLoading = false;
      _imageFile = null;
      locationString = null;
      category = '';
      customCategory = ''; // <-- Reset custom field
      date = null;
      feedbackRating = 0;
      firmName = '';
      place = '';
      contactPerson = '';
      contactNumber = '';
      currentEnquiry = '';
      confirmedOrder = '';
      newProductSuggestion = '';
      anySuggestion = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Form submitted successfully!')),
    );
    _formKey.currentState!.reset();
  }

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
                      'Hotel/Resort Customer Visit Form',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Electorize',
                        color: Color(0xFF1E3D59),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // SECTION: CUSTOMER INFO
                    _buildSectionTitle('Customer Information'),
                    _buildTextField(
                      label: 'FIRM NAME',
                      required: true,
                      error: _firmNameError,
                      errorText: 'Enter firm name',
                      initialValue: firmName,
                      onChanged: (v) => firmName = v,
                    ),
                    _buildTextField(
                      label: 'PLACE',
                      required: true,
                      error: _placeError,
                      errorText: 'Enter place',
                      initialValue: place,
                      onChanged: (v) => place = v,
                    ),
                    _buildTextField(
                      label: 'CONTACT PERSON NAME',
                      required: true,
                      error: _contactPersonError,
                      errorText: 'Enter contact person name',
                      initialValue: contactPerson,
                      onChanged: (v) => contactPerson = v,
                    ),
                    _buildTextField(
                      label: 'CONTACT NUMBER',
                      required: true,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      error: _contactNumberError,
                      errorText: contactNumber.isEmpty
                          ? 'Enter phone number'
                          : (contactNumber.length != 10 ? 'Phone number must be 10 digits' : null),
                      initialValue: contactNumber,
                      onChanged: (v) => contactNumber = v,
                    ),

                    // DATE
                    _buildSectionTitle('Visit Date'),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          setState(() {
                            date = picked;
                            _dateError = false;
                          });
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black
                              : Colors.white,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(22),
                            bottomLeft: Radius.circular(22),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              spreadRadius: 1,
                              blurRadius: 8,
                              offset: const Offset(2, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          date != null
                              ? "${date!.day}/${date!.month}/${date!.year}"
                              : 'Select date',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                    ),
                    if (_dateError)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 12),
                        child: Text(
                          'Please select a date',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontFamily: 'Electorize'),
                        ),
                      ),

                    // CATEGORY
                    _buildSectionTitle('Category'),
                    Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('HOTEL'),
                          value: 'HOTEL',
                          groupValue: category,
                          onChanged: (v) => setState(() {
                            category = v ?? '';
                            _categoryError = false;
                            customCategory = '';
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('RESORT'),
                          value: 'RESORT',
                          groupValue: category,
                          onChanged: (v) => setState(() {
                            category = v ?? '';
                            _categoryError = false;
                            customCategory = '';
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('RESTAURANT'),
                          value: 'RESTAURANT',
                          groupValue: category,
                          onChanged: (v) => setState(() {
                            category = v ?? '';
                            _categoryError = false;
                            customCategory = '';
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('AUDITORIUM'),
                          value: 'AUDITORIUM',
                          groupValue: category,
                          onChanged: (v) => setState(() {
                            category = v ?? '';
                            _categoryError = false;
                            customCategory = '';
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('OTHERS'),
                          value: 'OTHERS',
                          groupValue: category,
                          onChanged: (v) => setState(() {
                            category = v ?? '';
                            _categoryError = false;
                          }),
                        ),
                        if (category == 'OTHERS')
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: TextFormField(
                              decoration: _inputDecoration(
                                'Please specify',
                                required: true,
                                error: _customCategoryError,
                                errorText: 'Please specify category',
                              ),
                              onChanged: (v) {
                                setState(() {
                                  customCategory = v;
                                  if (v.trim().isNotEmpty) _customCategoryError = false;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                    if (_categoryError)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 12),
                        child: Text(
                          'Please select a category',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontFamily: 'Electorize'),
                        ),
                      ),

                    // ORDERS & ENQUIRIES
                    _buildSectionTitle('Orders & Enquiries'),
                    _buildTextField(
                      label: 'CURRENT ENQUIRY',
                      required: true,
                      error: _currentEnquiryError,
                      errorText: 'Enter current enquiry',
                      initialValue: currentEnquiry,
                      onChanged: (v) => currentEnquiry = v,
                    ),
                    _buildTextField(
                      label: 'CONFIRMED ORDER',
                      initialValue: confirmedOrder,
                      onChanged: (v) => confirmedOrder = v,
                    ),
                    _buildTextField(
                      label: 'NEW PRODUCT SUGGESTION',
                      required: true,
                      error: _newProductSuggestionError,
                      errorText: 'Enter new product suggestion',
                      initialValue: newProductSuggestion,
                      onChanged: (v) => newProductSuggestion = v,
                    ),

                    // FEEDBACK
                    _buildSectionTitle('Customer Feedback About Our Product & Service'),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (index) {
                          final starNumber = index + 1;
                          return Column(
                            children: [
                              Text('$starNumber', style: const TextStyle(fontSize: 15)),
                              IconButton(
                                icon: Icon(
                                  feedbackRating >= starNumber
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: feedbackRating >= starNumber
                                      ? Colors.amber
                                      : Colors.grey,
                                  size: 32,
                                ),
                                onPressed: () {
                                  setState(() {
                                    feedbackRating = starNumber;
                                    _feedbackRatingError = false;
                                  });
                                },
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                    if (_feedbackRatingError)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 8),
                        child: Text(
                          'Please select a rating',
                          style: TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'Electorize'),
                        ),
                      ),

                    // ANY SUGGESTION
                    _buildSectionTitle('Any Suggestion'),
                    _buildTextField(
                        label: 'ANY SUGGESTION',
                        initialValue: anySuggestion,
                        onChanged: (v) => anySuggestion = v),

                    // PHOTO
                    _buildSectionTitle('Attach Shop Photo'),
                    const SizedBox(height: 10),
                    _imageFile == null
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Take Photo'),
                            onPressed: _openCamera,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(
                                  color: Color(0xFF1E3D59), width: 1.2),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  topRight: Radius.circular(22),
                                  bottomLeft: Radius.circular(22),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(22),
                                bottomLeft: Radius.circular(22),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 8,
                                  offset: const Offset(2, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(22),
                                bottomLeft: Radius.circular(22),
                              ),
                              child: Image.file(_imageFile!,
                                  height: 150, fit: BoxFit.cover),
                            ),
                          ),
                    if (_photoError)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Please attach a shop photo',
                          style: TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'Electorize'),
                        ),
                      ),
                    const SizedBox(height: 28),

                    // SUBMIT BUTTON
                    ElevatedButton(
                      onPressed: _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3D59),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(22),
                            bottomLeft: Radius.circular(22),
                          ),
                        ),
                        elevation: 6,
                        shadowColor: Colors.black.withOpacity(0.25),
                      ),
                      child: const Text('Submit'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFF34495E),
        ),
      ),
    );
  }
}
