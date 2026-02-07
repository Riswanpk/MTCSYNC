import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'camera_page.dart';
import 'dart:io';
import 'package:flutter/services.dart'; // Add this import
import 'package:firebase_storage/firebase_storage.dart'; // Add this import
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../Misc/navigation_state.dart';

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

  static const String DRAFT_KEY = 'hotel_form_draft';

  @override
  State<HotelResortCustomerForm> createState() =>
      _HotelResortCustomerFormState();
}

class _HotelResortCustomerFormState extends State<HotelResortCustomerForm> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for text fields
  late TextEditingController _firmNameController;
  late TextEditingController _placeController;
  late TextEditingController _contactPersonController;
  late TextEditingController _contactNumberController;
  late TextEditingController _currentEnquiryController;
  late TextEditingController _confirmedOrderController;
  late TextEditingController _newProductSuggestionController;
  late TextEditingController _anySuggestionController;
  late TextEditingController _customCategoryController;


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
  bool _contactNumberError = false;
  bool _contactPersonError = false;
  bool _categoryError = false;
  bool _currentEnquiryError = false; // This was already here, but ensure it's not affected by date removal
  bool _customCategoryError = false; // <-- Add this line

  // No _feedbackRatingError needed as it's not a required field.
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
    TextEditingController? controller,
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
        controller: controller,
        keyboardType: keyboardType,
        decoration: _inputDecoration(label, required: required, error: error, errorText: errorText),
        validator: validator,
        onChanged: (v) {
          _saveDraft();
          if (onChanged != null) onChanged(v);
          setState(() {
            if (label == 'FIRM NAME') _firmNameError = v.trim().isEmpty;
            if (label == 'PLACE') _placeError = v.trim().isEmpty;
            if (label == 'CONTACT PERSON NAME') _contactPersonError = v.trim().isEmpty;
            if (label == 'CONTACT NUMBER') _contactNumberError = v.trim().isEmpty || v.length != 10;
            if (label == 'CURRENT ENQUIRY') _currentEnquiryError = v.trim().isEmpty; // This was already here, but ensure it's not affected by date removal
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
        _photoError = false;
      });
      _saveDraft();
    }
  }

  @override
  void initState() {
    super.initState();
    _firmNameController = TextEditingController();
    _placeController = TextEditingController();
    _contactPersonController = TextEditingController();
    _contactNumberController = TextEditingController();
    _currentEnquiryController = TextEditingController();
    _confirmedOrderController = TextEditingController();
    _newProductSuggestionController = TextEditingController();
    _anySuggestionController = TextEditingController();
    _customCategoryController = TextEditingController();
    _loadDraft();
  }

  @override
  void dispose() {
    _firmNameController.dispose();
    _placeController.dispose();
    _contactPersonController.dispose();
    _contactNumberController.dispose();
    _currentEnquiryController.dispose();
    _confirmedOrderController.dispose();
    _newProductSuggestionController.dispose();
    _anySuggestionController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _toDraftMap() {
    return {
      'firmName': _firmNameController.text,
      'place': _placeController.text,
      'contactPerson': _contactPersonController.text,
      'contactNumber': _contactNumberController.text,
      'category': category,
      'customCategory': _customCategoryController.text,
      'currentEnquiry': _currentEnquiryController.text,
      'confirmedOrder': _confirmedOrderController.text,
      'newProductSuggestion': _newProductSuggestionController.text,
      'feedbackRating': feedbackRating,
      'anySuggestion': _anySuggestionController.text,
      'locationString': locationString,
    };
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> draftData = _toDraftMap();

    if (_imageFile != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = path.basename(_imageFile!.path);
      final savedImage = await _imageFile!.copy('${appDir.path}/$fileName');
      draftData['imagePath'] = savedImage.path;
    } else {
      draftData.remove('imagePath');
    }

    String draftJson = jsonEncode(draftData);
    await prefs.setString(HotelResortCustomerForm.DRAFT_KEY, draftJson);
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final String? draftJson = prefs.getString(HotelResortCustomerForm.DRAFT_KEY);

    if (draftJson == null) return;

    final Map<String, dynamic> draftData = jsonDecode(draftJson);

    setState(() {
      _firmNameController.text = draftData['firmName'] ?? '';
      _placeController.text = draftData['place'] ?? '';
      _contactPersonController.text = draftData['contactPerson'] ?? '';
      _contactNumberController.text = draftData['contactNumber'] ?? '';
      category = draftData['category'] ?? '';
      _customCategoryController.text = draftData['customCategory'] ?? '';
      _currentEnquiryController.text = draftData['currentEnquiry'] ?? '';
      _confirmedOrderController.text = draftData['confirmedOrder'] ?? '';
      _newProductSuggestionController.text = draftData['newProductSuggestion'] ?? '';
      feedbackRating = draftData['feedbackRating'] ?? 0;
      _anySuggestionController.text = draftData['anySuggestion'] ?? '';
      locationString = draftData['locationString'];

      if (draftData['imagePath'] != null) {
        final imageFile = File(draftData['imagePath']);
        if (imageFile.existsSync()) {
          _imageFile = imageFile;
        }
      }
    });
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(HotelResortCustomerForm.DRAFT_KEY);
  }

  Future<void> _submitForm() async {
    // Update state variables from controllers before validation
    firmName = _firmNameController.text;
    place = _placeController.text;
    contactPerson = _contactPersonController.text;
    contactNumber = _contactNumberController.text;
    customCategory = _customCategoryController.text;
    currentEnquiry = _currentEnquiryController.text;
    confirmedOrder = _confirmedOrderController.text;
    newProductSuggestion = _newProductSuggestionController.text;
    anySuggestion = _anySuggestionController.text;

    setState(() {
      _firmNameError = firmName.trim().isEmpty;
      _placeError = place.trim().isEmpty;
      _contactNumberError = contactNumber.trim().isEmpty || contactNumber.length != 10;
      _categoryError = category.isEmpty; // This was already here, but ensure it's not affected by date removal
      _customCategoryError = category == 'OTHERS' && customCategory.trim().isEmpty; // <-- Add this line
      _currentEnquiryError = currentEnquiry.trim().isEmpty; // This was already here, but ensure it's not affected by date removal
      _photoError = _imageFile == null;
    });

    bool hasError =_firmNameError ||
        _placeError ||
        _contactNumberError ||
        _categoryError || // This was already here, but ensure it's not affected by date removal
        _customCategoryError || // <-- Add this line
        _currentEnquiryError || // This was already here, but ensure it's not affected by date removal
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

    await _clearDraft();
    
    // Clear navigation state since form was successfully submitted
    await NavigationState.clearState();

    setState(() {
      isLoading = false;
      _imageFile = null;
      locationString = null;
      category = '';
      customCategory = ''; // <-- Reset custom field
      feedbackRating = 0;
      firmName = '';
      place = '';
      contactPerson = '';
      contactNumber = '';
      currentEnquiry = '';
      confirmedOrder = '';
      newProductSuggestion = '';
      anySuggestion = '';
      _firmNameController.clear();
      _placeController.clear();
      _contactPersonController.clear();
      _contactNumberController.clear();
      _currentEnquiryController.clear();
      _confirmedOrderController.clear();
      _newProductSuggestionController.clear();
      _anySuggestionController.clear();
      _customCategoryController.clear();
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
                      'Hotel/Resort Visit Form',
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
                      controller: _firmNameController,
                      onChanged: (v) => firmName = v,
                    ),
                    _buildTextField(
                      label: 'PLACE',
                      required: true,
                      error: _placeError,
                      errorText: 'Enter place',
                      controller: _placeController,
                      onChanged: (v) => place = v,
                    ),
                    _buildTextField(
                      label: 'CONTACT PERSON NAME',
                      required: true,
                      error: _contactPersonError,
                      errorText: 'Enter contact person name',
                      controller: _contactPersonController,
                      onChanged: (v) => contactPerson = v,
                    ),
                    _buildTextField(
                      label: 'CONTACT NUMBER',
                      controller: _contactNumberController,
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
                      onChanged: (v) => contactNumber = v,
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
                            _saveDraft();
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
                            _saveDraft();
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
                            _saveDraft();
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
                            _saveDraft();
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('OTHERS'),
                          value: 'OTHERS',
                          groupValue: category,
                          onChanged: (v) => setState(() {
                            category = v ?? '';
                            _categoryError = false;
                            _saveDraft();
                          }),
                        ),
                        if (category == 'OTHERS')
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: TextFormField( // This is not using _buildTextField, so needs manual controller
                              controller: _customCategoryController,
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
                                  _saveDraft();
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
                      controller: _currentEnquiryController,
                    ),
                    _buildTextField(
                      label: 'CONFIRMED ORDER',
                      controller: _confirmedOrderController,
                      onChanged: (v) => confirmedOrder = v,
                    ),
                    _buildTextField(
                      label: 'NEW PRODUCT SUGGESTION',
                      controller: _newProductSuggestionController,
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
                                    _saveDraft();
                                  });
                                },
                              ),
                            ],
                          );
                        }),
                      ),
                    ),

                    // ANY SUGGESTION
                    _buildSectionTitle('Any Suggestion'),
                    _buildTextField(
                        label: 'ANY SUGGESTION',
                        controller: _anySuggestionController,
                        onChanged: (v) => anySuggestion = v,
                    ),

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
                    if (_imageFile != null)
                      TextButton(
                        onPressed: () {
                          setState(() => _imageFile = null);
                          _saveDraft();
                        },
                        child: const Text('Remove Photo'),
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
