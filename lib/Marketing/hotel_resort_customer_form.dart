import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'camera_page.dart';
import 'dart:io';

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
  String shopName = '';
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

  // 🔹 Unified InputDecoration (used inside reusable textfield)
  InputDecoration _inputDecoration(String label, {bool required = false}) =>
      InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: const TextStyle(
          fontSize: 16,
          fontFamily: 'Electorize',
        ),
        border: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      );

  // 🔹 Reusable styled textfield with shadow & corners
  Widget _buildTextField({
    required String label,
    bool required = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Function(String)? onChanged,
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
        keyboardType: keyboardType,
        decoration: _inputDecoration(label, required: required),
        validator: validator,
        onChanged: onChanged,
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
    if (!_formKey.currentState!.validate() ||
        category.isEmpty ||
        date == null) {
      setState(() {}); // Show error
      return;
    }
    setState(() => isLoading = true);

    await FirebaseFirestore.instance.collection('marketing').add({
      'formType': 'Hotel / Resort Customer',
      'username': widget.username,
      'userid': widget.userid,
      'branch': widget.branch,
      'shopName': shopName,
      'date': date,
      'firmName': firmName,
      'place': place,
      'contactPerson': contactPerson,
      'contactNumber': contactNumber,
      'category': category,
      'currentEnquiry': currentEnquiry,
      'confirmedOrder': confirmedOrder,
      'newProductSuggestion': newProductSuggestion,
      'feedback1': feedback1,
      'feedback2': feedback2,
      'feedback3': feedback3,
      'feedback4': feedback4,
      'feedback5': feedback5,
      'anySuggestion': anySuggestion,
      'locationString': locationString,
      'timestamp': FieldValue.serverTimestamp(),
    });

    setState(() {
      isLoading = false;
      _imageFile = null;
      locationString = null;
      category = '';
      date = null;
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
                      label: 'SHOP NAME',
                      required: true,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Enter shop name' : null,
                      onChanged: (v) => shopName = v,
                    ),
                    _buildTextField(
                      label: 'FIRM NAME',
                      required: true,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Enter firm name' : null,
                      onChanged: (v) => firmName = v,
                    ),
                    _buildTextField(
                      label: 'PLACE',
                      required: true,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Enter place' : null,
                      onChanged: (v) => place = v,
                    ),
                    _buildTextField(
                      label: 'CONTACT PERSON NAME',
                      required: true,
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter contact person name'
                          : null,
                      onChanged: (v) => contactPerson = v,
                    ),
                    _buildTextField(
                      label: 'CONTACT NUMBER',
                      required: true,
                      keyboardType: TextInputType.phone,
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter contact number'
                          : null,
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
                          lastDate:
                              DateTime.now().add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          setState(() {
                            date = picked;
                          });
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
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
                            color: date != null
                                ? Colors.black
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    if (date == null)
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
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('RESORT'),
                          value: 'RESORT',
                          groupValue: category,
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('RESTAURANT'),
                          value: 'RESTAURANT',
                          groupValue: category,
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('AUDITORIUM'),
                          value: 'AUDITORIUM',
                          groupValue: category,
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('OTHERS'),
                          value: 'OTHERS',
                          groupValue: category,
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                      ],
                    ),
                    if (category.isEmpty)
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
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter current enquiry'
                          : null,
                      onChanged: (v) => currentEnquiry = v,
                    ),
                    _buildTextField(
                      label: 'CONFIRMED ORDER',
                      onChanged: (v) => confirmedOrder = v,
                    ),
                    _buildTextField(
                      label: 'NEW PRODUCT SUGGESTION',
                      required: true,
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter new product suggestion'
                          : null,
                      onChanged: (v) => newProductSuggestion = v,
                    ),

                    // FEEDBACK
                    _buildSectionTitle(
                        'Customer Feedback About Our Product & Service'),
                    _buildTextField(
                        label: '1', onChanged: (v) => feedback1 = v),
                    _buildTextField(
                        label: '2', onChanged: (v) => feedback2 = v),
                    _buildTextField(
                        label: '3', onChanged: (v) => feedback3 = v),
                    _buildTextField(
                        label: '4', onChanged: (v) => feedback4 = v),
                    _buildTextField(
                        label: '5', onChanged: (v) => feedback5 = v),

                    // ANY SUGGESTION
                    _buildSectionTitle('Any Suggestion'),
                    _buildTextField(
                        label: 'ANY SUGGESTION',
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
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
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
