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
                    const SizedBox(height: 12),
                    Text(
                      'General Customer Visit Form',
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
                        decoration: _inputDecoration('SHOP NAME', required: true),
                        validator: (v) => v == null || v.isEmpty ? 'Enter shop name' : null,
                        onChanged: (v) => shopName = v,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        decoration: _inputDecoration('PLACE'),
                        onChanged: (v) => place = v,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        decoration: _inputDecoration('PHONE NO'),
                        keyboardType: TextInputType.phone,
                        onChanged: (v) => phoneNo = v,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // SECTION: BUSINESS INFO
                    _buildSectionTitle('Business Information'),
                    const SizedBox(height: 10),
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
                        decoration: _inputDecoration('CURRENT ENQUIRIES'),
                        onChanged: (v) => currentEnquiries = v,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        decoration: _inputDecoration('CONFIRMED ORDER', required: true),
                        validator: (v) => v == null || v.isEmpty ? 'Enter confirmed order' : null,
                        onChanged: (v) => confirmedOrder = v,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        decoration: _inputDecoration('NEW PRODUCT SUGGESTION'),
                        onChanged: (v) => newProductSuggestion = v,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // SECTION: PHOTO
                    _buildSectionTitle('Attach Shop Photo'),
                    const SizedBox(height: 10),
                    _imageFile == null
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt),
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
                                child: Image.file(_imageFile!, height: 120, fit: BoxFit.cover),
                              ),
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
}