import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'camera_page.dart'; // Add this import
import 'dart:io'; // Add this import

class GeneralCustomerForm extends StatefulWidget {
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
  State<GeneralCustomerForm> createState() => _GeneralCustomerFormState();
}

class _GeneralCustomerFormState extends State<GeneralCustomerForm> {
  final _formKey = GlobalKey<FormState>();
  String shopName = '';
  String place = '';
  String phoneNo = '';
  String natureOfBusiness = '';
  String currentEnquiries = '';
  String confirmedOrder = '';
  String newProductSuggestion = '';
  bool isLoading = false;
  File? _imageFile;
  String? locationString;

  InputDecoration _inputDecoration(String label, {bool required = false}) => InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: const TextStyle(
          fontSize: 16,
          fontFamily: 'Electorize',
        ),
        filled: true,
        fillColor: const Color(0xFFF7F2F2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      );

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
    if (!_formKey.currentState!.validate() || natureOfBusiness.isEmpty) {
      setState(() {}); // Show error
      return;
    }
    setState(() => isLoading = true);

    await FirebaseFirestore.instance.collection('marketing').add({
      'formType': 'General Customer',
      'username': widget.username,
      'userid': widget.userid,
      'branch': widget.branch,
      'shopName': shopName,
      'place': place,
      'phoneNo': phoneNo,
      'natureOfBusiness': natureOfBusiness,
      'currentEnquiries': currentEnquiries,
      'confirmedOrder': confirmedOrder,
      'newProductSuggestion': newProductSuggestion,
      'locationString': locationString, // <-- Save location
      'timestamp': FieldValue.serverTimestamp(),
    });

    setState(() {
      isLoading = false;
      _imageFile = null;
      locationString = null;
      natureOfBusiness = '';
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
                    // SHOP NAME *
                    TextFormField(
                      decoration: _inputDecoration('SHOP NAME', required: true),
                      validator: (v) => v == null || v.isEmpty ? 'Enter shop name' : null,
                      onChanged: (v) => shopName = v,
                    ),
                    const SizedBox(height: 16),

                    // PLACE
                    TextFormField(
                      decoration: _inputDecoration('PLACE'),
                      onChanged: (v) => place = v,
                    ),
                    const SizedBox(height: 16),

                    // PHONE NO
                    TextFormField(
                      decoration: _inputDecoration('PHONE NO'),
                      keyboardType: TextInputType.phone,
                      onChanged: (v) => phoneNo = v,
                    ),
                    const SizedBox(height: 16),

                    // NATURE OF BUSINESS *
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'NATURE OF BUSINESS *',
                        style: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'Electorize',
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('EVENT', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'EVENT',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() => natureOfBusiness = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('CATERING', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'CATERING',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() => natureOfBusiness = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('RENTAL SERVICES', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'RENTAL SERVICES',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() => natureOfBusiness = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('AUDITORIUM', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'AUDITORIUM',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() => natureOfBusiness = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('OTHERS', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'OTHERS',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() => natureOfBusiness = v ?? ''),
                        ),
                      ],
                    ),
                    if (natureOfBusiness.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 8),
                        child: Text(
                          'Please select a nature of business',
                          style: TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Electorize'),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // CURRENT ENQUIRIES
                    TextFormField(
                      decoration: _inputDecoration('CURRENT ENQUIRIES'),
                      onChanged: (v) => currentEnquiries = v,
                    ),
                    const SizedBox(height: 16),

                    // CONFIRMED ORDER *
                    TextFormField(
                      decoration: _inputDecoration('CONFIRMED ORDER', required: true),
                      validator: (v) => v == null || v.isEmpty ? 'Enter confirmed order' : null,
                      onChanged: (v) => confirmedOrder = v,
                    ),
                    const SizedBox(height: 16),

                    // NEW PRODUCT SUGGESTION
                    TextFormField(
                      decoration: _inputDecoration('NEW PRODUCT SUGGESTION'),
                      onChanged: (v) => newProductSuggestion = v,
                    ),
                    const SizedBox(height: 16),

                    // Attach Shop Photo
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
                      onPressed: _submitForm,
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
            ),
    );
  }
}