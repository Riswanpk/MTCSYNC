import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'camera_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../Misc/navigation_state.dart';
import 'image_upload_helper.dart';

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

  static const String DRAFT_KEY = 'premium_form_draft';

  @override
  State<PremiumCustomerForm> createState() => _PremiumCustomerFormState();
}

class _PremiumCustomerFormState extends State<PremiumCustomerForm> {
  final _formKey = GlobalKey<FormState>();
  final ImageUploadHelper _uploadHelper = ImageUploadHelper();

  // Controllers for text fields
  late TextEditingController _shopNameController;
  late TextEditingController _phoneNoController;
  late TextEditingController _currentEnquiriesController;
  late TextEditingController _confirmedOrderController;
  late TextEditingController _upcomingEventDetailsController;
  late TextEditingController _newProductSuggestionController;
  late TextEditingController _otherPurchasesReasonController;
  // Removed: _upcomingTrendsController, _feedbackController


  String shopName = '';
  String phoneNo = '';
  DateTime? lastItemPurchasedDate;
  String lastPurchasedItem = '';
  String currentEnquiries = '';
  String confirmedOrder = '';
  DateTime? upcomingEventDate;
  String upcomingEventDetails = '';
  String newProductSuggestion = '';
  // Removed: upcomingTrends, feedback
  File? _imageFile;
  bool isLoading = false;
  String? locationString;
  bool _photoError = false; // Add this line
  String? _otherPurchases; // 'yes' or 'no'

  // Add error flags for all fields
  bool _shopNameError = false;
  bool _phoneNoError = false;
  bool _currentEnquiriesError = false;
  bool _confirmedOrderError = false;
  bool _otherPurchasesError = false;
  bool _otherPurchasesReasonError = false;

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
      // Start uploading immediately while user fills the rest of the form
      _uploadHelper.cancel(); // cancel any previous upload
      _uploadHelper.startUpload(_imageFile!);
      _saveDraft();
    }
  }

  @override
  void initState() {
    super.initState();
    _shopNameController = TextEditingController();
    _phoneNoController = TextEditingController();
    _currentEnquiriesController = TextEditingController();
    _confirmedOrderController = TextEditingController();
    _upcomingEventDetailsController = TextEditingController();
    _newProductSuggestionController = TextEditingController();
    _otherPurchasesReasonController = TextEditingController();
    // Removed: _upcomingTrendsController, _feedbackController
    _loadDraft();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _phoneNoController.dispose();
    _currentEnquiriesController.dispose();
    _confirmedOrderController.dispose();
    _upcomingEventDetailsController.dispose();
    _newProductSuggestionController.dispose();
    _otherPurchasesReasonController.dispose();
    // Removed: _upcomingTrendsController, _feedbackController
    super.dispose();
  }

  Map<String, dynamic> _toDraftMap() {
    return {
      'shopName': _shopNameController.text,
      'phoneNo': _phoneNoController.text,
      'lastItemPurchasedDate': lastItemPurchasedDate?.toIso8601String(),
      'currentEnquiries': _currentEnquiriesController.text,
      'confirmedOrder': _confirmedOrderController.text,
      'upcomingEventDate': upcomingEventDate?.toIso8601String(),
      'upcomingEventDetails': _upcomingEventDetailsController.text,
      'newProductSuggestion': _newProductSuggestionController.text,
      'locationString': locationString,
      'otherPurchases': _otherPurchases,
      'otherPurchasesReason': _otherPurchasesReasonController.text,
    };
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> draftData = _toDraftMap();

      if (_imageFile != null && _imageFile!.existsSync()) {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = path.basename(_imageFile!.path);
        final savedImage = await _imageFile!.copy('${appDir.path}/$fileName');
        draftData['imagePath'] = savedImage.path;
      } else {
        draftData.remove('imagePath');
      }

      String draftJson = jsonEncode(draftData);
      await prefs.setString(PremiumCustomerForm.DRAFT_KEY, draftJson);
    } catch (e) {
      debugPrint('Error saving draft: $e');
    }
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? draftJson = prefs.getString(PremiumCustomerForm.DRAFT_KEY);

      if (draftJson == null) return;

      final Map<String, dynamic> draftData = jsonDecode(draftJson);

      if (!mounted) return;
      setState(() {
        _shopNameController.text = draftData['shopName'] ?? '';
        _phoneNoController.text = draftData['phoneNo'] ?? '';
        lastItemPurchasedDate = draftData['lastItemPurchasedDate'] != null ? DateTime.parse(draftData['lastItemPurchasedDate']) : null;
        _currentEnquiriesController.text = draftData['currentEnquiries'] ?? '';
        _confirmedOrderController.text = draftData['confirmedOrder'] ?? '';
        upcomingEventDate = draftData['upcomingEventDate'] != null ? DateTime.parse(draftData['upcomingEventDate']) : null;
        _upcomingEventDetailsController.text = draftData['upcomingEventDetails'] ?? '';
        _newProductSuggestionController.text = draftData['newProductSuggestion'] ?? '';
        locationString = draftData['locationString'];
        _otherPurchases = draftData['otherPurchases'];
        _otherPurchasesReasonController.text = draftData['otherPurchasesReason'] ?? '';

        if (draftData['imagePath'] != null) {
          final imageFile = File(draftData['imagePath']);
          if (imageFile.existsSync()) {
            _imageFile = imageFile;
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading draft: $e');
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PremiumCustomerForm.DRAFT_KEY);
  }

  Future<void> _submitForm() async {
    // Update state variables from controllers before validation
    shopName = _shopNameController.text;
    phoneNo = _phoneNoController.text;
    currentEnquiries = _currentEnquiriesController.text;
    confirmedOrder = _confirmedOrderController.text;
    upcomingEventDetails = _upcomingEventDetailsController.text;
    newProductSuggestion = _newProductSuggestionController.text;
    // Removed: upcomingTrends, feedback

    bool otherPurchasesInvalid = _otherPurchases == null;
    bool otherPurchasesReasonInvalid = false;
    if (_otherPurchases == 'yes' && _otherPurchasesReasonController.text.trim().isEmpty) {
      otherPurchasesReasonInvalid = true;
    }

    // Validate all fields manually
    setState(() {
      _shopNameError = shopName.trim().isEmpty;
      _phoneNoError = phoneNo.trim().isEmpty || phoneNo.trim().length != 10;
      _currentEnquiriesError = currentEnquiries.trim().isEmpty;
      _confirmedOrderError = confirmedOrder.trim().isEmpty;
      _photoError = _imageFile == null;
      _otherPurchasesError = otherPurchasesInvalid;
      _otherPurchasesReasonError = otherPurchasesReasonInvalid;
    });

    bool hasError = _shopNameError ||
        _phoneNoError ||
        _currentEnquiriesError ||
        _confirmedOrderError ||
        _photoError ||
        otherPurchasesInvalid ||
        otherPurchasesReasonInvalid;

    if (hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields.')),
      );
      // Do NOT reset the form or clear fields!
      return;
    }

    setState(() => isLoading = true);

    try {
      // Use the pre-uploaded image URL (upload started when photo was taken)
      String? imageUrl = await _uploadHelper.getUploadResult();

      String otherPurchases = _otherPurchases ?? '';
      String otherPurchasesReason = _otherPurchasesReasonController.text;

      await FirebaseFirestore.instance.collection('marketing').add({
        'formType': 'Premium Customer',
        'username': widget.username,
        'userid': widget.userid,
        'branch': widget.branch,
        'shopName': shopName,
        'phoneNo': phoneNo,
        'lastItemPurchasedDate': lastItemPurchasedDate,
        'lastPurchasedItem': lastPurchasedItem,
        'currentEnquiries': currentEnquiries,
        'confirmedOrder': confirmedOrder,
        'upcomingEventDate': upcomingEventDate,
        'upcomingEventDetails': upcomingEventDetails,
        'newProductSuggestion': newProductSuggestion,
        'imageUrl': imageUrl,
        'locationString': locationString,
        'timestamp': FieldValue.serverTimestamp(),
        'otherPurchases': otherPurchases,
        'otherPurchasesReason': otherPurchases == 'yes' ? otherPurchasesReason : null,
      });

      await _clearDraft();
      
      // Clear navigation state since form was successfully submitted
      await NavigationState.clearState();
      _uploadHelper.reset();

      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form submitted successfully!')),
      );

      // Reset the form and all fields
      _formKey.currentState?.reset();
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

        _shopNameController.clear();
        _phoneNoController.clear();
        _currentEnquiriesController.clear();
        _confirmedOrderController.clear();
        _upcomingEventDetailsController.clear();
        _newProductSuggestionController.clear();
        _otherPurchases = null;
        _otherPurchasesReasonController.clear();

        // Reset all error flags
        _shopNameError = false;
        _phoneNoError = false;
        _currentEnquiriesError = false;
        _confirmedOrderError = false;
        _photoError = false;
      });
    } catch (e) {
      debugPrint('Error submitting form: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error submitting form. Please try again.')),
      );
    }
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
            : const Color.fromARGB(255, 238, 232, 205),
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
                        color: Color.fromARGB(255, 255, 192, 18),
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
                        controller: _shopNameController,
                        decoration: _inputDecoration(
                          'Shop Name',
                          error: _shopNameError,
                          errorText: 'Enter shop name',
                        ),
                        onChanged: (v) {
                          _saveDraft();
                          setState(() {
                            shopName = v;
                            if (v.trim().isNotEmpty) _shopNameError = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    // --- Phone Number ---
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
                        controller: _phoneNoController,
                        decoration: _inputDecoration(
                          'Phone Number',
                          error: _phoneNoError,
                          errorText: 'Phone number must be 10 digits',
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        onChanged: (v) {
                          _saveDraft();
                          setState(() {
                            phoneNo = v;
                            if (v.trim().length == 10) _phoneNoError = false;
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
                        controller: _currentEnquiriesController,
                        decoration: _inputDecoration(
                          'Current Enquiries',
                          error: _currentEnquiriesError,
                          errorText: 'Enter current enquiries',
                        ),
                        onChanged: (v) {
                          _saveDraft();
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
                        controller: _confirmedOrderController,
                        decoration: _inputDecoration(
                          'Confirmed Order',
                          error: _confirmedOrderError,
                          errorText: 'Enter confirmed order',
                        ),
                        onChanged: (v) {
                          _saveDraft();
                          setState(() {
                            confirmedOrder = v;
                            if (v.trim().isNotEmpty) _confirmedOrderError = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // OTHER PURCHASES
                    _buildSectionTitle('Other Purchases'),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text(
                        'Did this customer purchase from another company? *',
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'Electorize',
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Yes'),
                            value: 'yes',
                            groupValue: _otherPurchases,
                            onChanged: (value) {
                              setState(() {
                                _otherPurchases = value;
                                _otherPurchasesError = false;
                              });
                              _saveDraft();
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('No'),
                            value: 'no',
                            groupValue: _otherPurchases,
                            onChanged: (value) {
                              setState(() {
                                _otherPurchases = value;
                                _otherPurchasesError = false;
                              });
                              _saveDraft();
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_otherPurchasesError)
                      const Padding(
                        padding: EdgeInsets.only(left: 16, top: 4),
                        child: Text(
                          'Please select an option',
                          style: TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'Electorize'),
                        ),
                      ),
                    if (_otherPurchases == 'yes')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
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
                                color: Colors.black.withOpacity(0.08),
                                spreadRadius: 1,
                                blurRadius: 8,
                                offset: const Offset(2, 4),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _otherPurchasesReasonController,
                            decoration: _inputDecoration(
                              'Reason for Other Purchase',
                              error: _otherPurchasesReasonError,
                              errorText: 'Enter reason',
                            ),
                            onChanged: (v) {
                              setState(() {
                                _otherPurchasesReasonError = v.trim().isEmpty;
                              });
                              _saveDraft();
                            },
                          ),
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
                            _saveDraft();
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
                        controller: _upcomingEventDetailsController,
                        decoration: _inputDecoration('Upcoming Big Events Details'),
                        onChanged: (v) {
                          _saveDraft();
                          setState(() {
                            upcomingEventDetails = v;
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
                        controller: _newProductSuggestionController,
                        decoration: _inputDecoration('New Product Suggestion'),
                        onChanged: (v) {
                          _saveDraft();
                          setState(() {
                            newProductSuggestion = v;
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
                                onPressed: () {
                                  setState(() => _imageFile = null);
                                  _saveDraft();
                                },
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