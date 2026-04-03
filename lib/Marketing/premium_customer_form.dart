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
import '../Navigation/navigation_state.dart';
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
    _phoneNoController = TextEditingController(text: '+91 ');
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
        _phoneNoController.text = _formatIndianPhone(draftData['phoneNo'] ?? '');
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

  String _formatIndianPhone(String raw) {
    final digits = RegExp(r'\d').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.length >= 10) {
      final tenDigits = digits.substring(digits.length - 10);
      return '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
    }
    return '+91 ';
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
      _phoneNoError = phoneNo.replaceAll(RegExp(r'\D'), '').length != 12;
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
        _phoneNoController.text = '+91 ';
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
        labelStyle: TextStyle(
          fontSize: 13,
          fontFamily: 'Electorize',
          color: const Color(0xFFD4AF37).withValues(alpha: 0.7),
          letterSpacing: 0.5,
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E2C)
            : const Color(0xFFFAF6EE),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(22),
            topLeft: Radius.circular(0),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(0),
          ),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(22),
            topLeft: Radius.circular(0),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(0),
          ),
          borderSide: BorderSide(color: const Color(0xFFD4AF37).withValues(alpha: 0.25), width: 1),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(22),
            topLeft: Radius.circular(0),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(0),
          ),
          borderSide: BorderSide(color: Color(0xFFD4AF37), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        errorText: error ? errorText : null,
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'Electorize'),
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
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFFD4AF37), Color(0xFFF5D060), Color(0xFFD4AF37)],
                      ).createShader(bounds),
                      child: const Text(
                        'Premium Customer Visit Form',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Electorize',
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 60,
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD4AF37), Color(0xFFF5D060)],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

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
                            color: Colors.grey.withValues(alpha: 0.3),
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
                            color: Colors.grey.withValues(alpha: 0.3),
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
                          errorText: 'Enter a valid 10-digit number after +91',
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste),
                            tooltip: 'Paste from clipboard',
                            onPressed: () async {
                              final clipboardData =
                                  await Clipboard.getData('text/plain');
                              if (clipboardData?.text != null) {
                                final formatted =
                                    _formatIndianPhone(clipboardData!.text!);
                                if (formatted != '+91 ') {
                                  setState(() {
                                    _phoneNoController.text = formatted;
                                    _phoneNoController.selection =
                                        TextSelection.fromPosition(
                                      TextPosition(offset: formatted.length),
                                    );
                                    phoneNo = formatted;
                                    _phoneNoError = false;
                                  });
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Clipboard does not contain a valid 10-digit number')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                        onChanged: (val) {
                          if (!val.startsWith('+91 ')) {
                            _phoneNoController.text = '+91 ';
                            _phoneNoController.selection =
                                TextSelection.fromPosition(
                              TextPosition(
                                  offset: _phoneNoController.text.length),
                            );
                            setState(() => phoneNo = '+91 ');
                            return;
                          }
                          String raw =
                              val.replaceAll('+91 ', '').replaceAll(' ', '');
                          if (raw.length > 10) raw = raw.substring(0, 10);
                          String formatted = raw.length > 5
                              ? '+91 ${raw.substring(0, 5)} ${raw.substring(5)}'
                              : '+91 $raw';
                          if (_phoneNoController.text != formatted) {
                            _phoneNoController.text = formatted;
                            _phoneNoController.selection =
                                TextSelection.fromPosition(
                              TextPosition(offset: formatted.length),
                            );
                          }
                          _saveDraft();
                          setState(() {
                            phoneNo = formatted;
                            if (_phoneNoError &&
                                formatted
                                        .replaceAll(RegExp(r'\D'), '')
                                        .length ==
                                    12) {
                              _phoneNoError = false;
                            }
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
                            color: Colors.grey.withValues(alpha: 0.3),
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
                            color: Colors.grey.withValues(alpha: 0.3),
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
                                color: Colors.black.withValues(alpha: 0.08),
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
                            color: Colors.grey.withValues(alpha: 0.3),
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
                            color: Colors.grey.withValues(alpha: 0.3),
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
                            icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFFD4AF37)),
                            label: const Text('Take Photo', style: TextStyle(color: Color(0xFFD4AF37), letterSpacing: 0.5)),
                            onPressed: _openCamera,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  topRight: Radius.circular(22),
                                  bottomLeft: Radius.circular(22),
                                ),
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.3), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: Image.file(_imageFile!, height: 160, fit: BoxFit.cover),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() => _imageFile = null);
                                  _saveDraft();
                                },
                                icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                                label: const Text('Remove Photo', style: TextStyle(color: Colors.redAccent)),
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
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(22),
                          bottomLeft: Radius.circular(22),
                        ),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD4AF37), Color(0xFFF5D060), Color(0xFFD4AF37)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: const Color(0xFF1A1A2E),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(22),
                              bottomLeft: Radius.circular(22),
                            ),
                          ),
                        ),
                        child: const Text('Submit'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFD4AF37), Color(0xFFF5D060)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF2C1810),
              letterSpacing: 0.8,
              fontFamily: 'Electorize',
            ),
          ),
        ],
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  date != null
                      ? "${date.day}/${date.month}/${date.year}"
                      : 'Select date',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
                Icon(Icons.calendar_today_outlined,
                    size: 20,
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
        if (error && errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'Electorize'),
            ),
          ),
      ],
    );
  }
}