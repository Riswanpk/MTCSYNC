import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'camera_page.dart'; // Add this import
import 'dart:io'; // Add this import
import 'package:flutter/services.dart'; // Add this import
import 'package:firebase_storage/firebase_storage.dart'; // Add this import
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../Navigation/navigation_state.dart';
import 'image_upload_helper.dart';

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

  static const String DRAFT_KEY = 'general_form_draft';

  @override
  State<GeneralCustomerForm> createState() => _GeneralCustomerFormState();
}

class _GeneralCustomerFormState extends State<GeneralCustomerForm> {
    final ImageUploadHelper _uploadHelper = ImageUploadHelper();
    String? _otherPurchases; // 'yes' or 'no'
    TextEditingController _otherPurchasesReasonController = TextEditingController();
    bool _otherPurchasesError = false;
    bool _otherPurchasesReasonError = false;
  // Controllers for text fields to manage state for drafts
  late TextEditingController _shopNameController;
  late TextEditingController _placeController;
  late TextEditingController _phoneNoController;
  late TextEditingController _customNatureOfBusinessController;
  late TextEditingController _currentEnquiriesController;
  late TextEditingController _confirmedOrderController;
  late TextEditingController _newProductSuggestionController;
  final _formKey = GlobalKey<FormState>();
  String shopName = '';
  String place = '';
  String phoneNo = '';
  String natureOfBusiness = '';
  String customNatureOfBusiness = ''; // Add this line
  String currentEnquiries = '';
  String confirmedOrder = '';
  String newProductSuggestion = '';
  bool isLoading = false;
  File? _imageFile;
  String? locationString;
  bool _photoError = false; // Add this line
  double _uploadProgress = 0.0; // Add this line

  InputDecoration _inputDecoration(String label, {bool required = false}) => InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: TextStyle(
          fontSize: 13,
          fontFamily: 'Electorize',
          fontWeight: FontWeight.w500,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white70
              : const Color(0xFF78909C),
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[900]
            : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: const Color(0xFFFF6B35).withValues(alpha: 0.15), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      );

  Widget _buildFieldCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[900]
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B35).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
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
    _placeController = TextEditingController();
    _phoneNoController = TextEditingController(text: '+91 ');
    _customNatureOfBusinessController = TextEditingController();
    _currentEnquiriesController = TextEditingController();
    _confirmedOrderController = TextEditingController();
    _newProductSuggestionController = TextEditingController();
    _otherPurchasesReasonController = TextEditingController();
    _loadDraft();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _placeController.dispose();
    _phoneNoController.dispose();
    _customNatureOfBusinessController.dispose();
    _currentEnquiriesController.dispose();
    _confirmedOrderController.dispose();
    _newProductSuggestionController.dispose();
    _otherPurchasesReasonController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _toDraftMap() {
    return {
      'shopName': _shopNameController.text,
      'place': _placeController.text,
      'phoneNo': _phoneNoController.text,
      'natureOfBusiness': natureOfBusiness,
      'customNatureOfBusiness': _customNatureOfBusinessController.text,
      'currentEnquiries': _currentEnquiriesController.text,
      'confirmedOrder': _confirmedOrderController.text,
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
      await prefs.setString(GeneralCustomerForm.DRAFT_KEY, draftJson);
    } catch (e) {
      debugPrint('Error saving draft: $e');
    }
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? draftJson = prefs.getString(GeneralCustomerForm.DRAFT_KEY);

      if (draftJson == null) return;

      final Map<String, dynamic> draftData = jsonDecode(draftJson);

      if (!mounted) return;
      setState(() {
        _shopNameController.text = draftData['shopName'] ?? '';
        _placeController.text = draftData['place'] ?? '';
        _phoneNoController.text = _formatIndianPhone(draftData['phoneNo'] ?? '');
        natureOfBusiness = draftData['natureOfBusiness'] ?? '';
        _customNatureOfBusinessController.text = draftData['customNatureOfBusiness'] ?? '';
        _currentEnquiriesController.text = draftData['currentEnquiries'] ?? '';
        _confirmedOrderController.text = draftData['confirmedOrder'] ?? '';
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
    await prefs.remove(GeneralCustomerForm.DRAFT_KEY);
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
    bool otherPurchasesInvalid = _otherPurchases == null;
    bool otherPurchasesReasonInvalid = false;
    if (_otherPurchases == 'yes' && _otherPurchasesReasonController.text.trim().isEmpty) {
      otherPurchasesReasonInvalid = true;
    }
    setState(() {
      _otherPurchasesError = otherPurchasesInvalid;
      _otherPurchasesReasonError = otherPurchasesReasonInvalid;
      _photoError = _imageFile == null;
    });
    if (_formKey.currentState?.validate() != true || natureOfBusiness.isEmpty || _imageFile == null || otherPurchasesInvalid || otherPurchasesReasonInvalid) {
      return;
    }

    _formKey.currentState?.save();
    shopName = _shopNameController.text;
    place = _placeController.text;
    phoneNo = _phoneNoController.text;
    customNatureOfBusiness = _customNatureOfBusinessController.text;
    currentEnquiries = _currentEnquiriesController.text;
    confirmedOrder = _confirmedOrderController.text;
    newProductSuggestion = _newProductSuggestionController.text;
    String otherPurchases = _otherPurchases ?? '';
    String otherPurchasesReason = _otherPurchasesReasonController.text;

    setState(() {
      isLoading = true;
      _photoError = false;
      _uploadProgress = 0.0;
    });

    try {
      // Use the pre-uploaded image URL (upload started when photo was taken)
      String? imageUrl = await _uploadHelper.getUploadResult();

      // Submit marketing form only (lead creation removed)
      await FirebaseFirestore.instance.collection('marketing').add({
        'formType': 'General Customer',
        'username': widget.username,
        'userid': widget.userid,
        'branch': widget.branch,
        'shopName': shopName,
        'place': place,
        'phoneNo': phoneNo,
        'natureOfBusiness': natureOfBusiness == 'OTHERS' && customNatureOfBusiness.isNotEmpty
            ? customNatureOfBusiness
            : natureOfBusiness,
        'currentEnquiries': currentEnquiries,
        'confirmedOrder': confirmedOrder,
        'newProductSuggestion': newProductSuggestion,
        'locationString': locationString,
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'otherPurchases': otherPurchases,
        'otherPurchasesReason': otherPurchases == 'yes' ? otherPurchasesReason : null,
      });

      await _clearDraft();
      // Clear navigation state since form was successfully submitted
      await NavigationState.clearState();
      _uploadHelper.reset();

      if (!mounted) return;

      setState(() {
        isLoading = false;
        _uploadProgress = 0.0;
        _imageFile = null;
        locationString = null;
        natureOfBusiness = '';
        customNatureOfBusiness = '';
        _shopNameController.clear();
        _placeController.clear();
        _phoneNoController.text = '+91 ';
        _customNatureOfBusinessController.clear();
        _currentEnquiriesController.clear();
        _confirmedOrderController.clear();
        _newProductSuggestionController.clear();
        _otherPurchases = null;
        _otherPurchasesReasonController.clear();
      });

      _formKey.currentState?.reset();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form submitted successfully!')),
      );
    } catch (e) {
      debugPrint('Error submitting form: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
        _uploadProgress = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error submitting form. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Electorize'),
      child: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  if (_uploadProgress > 0 && _uploadProgress < 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(value: _uploadProgress),
                    ),
                  if (_uploadProgress > 0 && _uploadProgress < 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Uploading photo... ${(_uploadProgress * 100).toStringAsFixed(0)}%'),
                    ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFFFF6B35).withValues(alpha: 0.12),
                            const Color(0xFFFF8F65).withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.storefront_outlined, color: Color(0xFFFF6B35), size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Flexible(
                            child: Text(
                              'General Marketing\nVisit Form',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Electorize',
                                color: Color(0xFF2D3436),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // SECTION: CUSTOMER INFO
                    _buildSectionTitle('Customer Information', Icons.person_outline),
                    const SizedBox(height: 8),
                    _buildFieldCard(
                      child: TextFormField(
                        controller: _shopNameController,
                        decoration: _inputDecoration('SHOP NAME', required: true),
                        validator: (v) => v == null || v.isEmpty ? 'Enter shop name' : null,
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    _buildFieldCard(
                      child: TextFormField(
                        controller: _placeController,
                        decoration: _inputDecoration('PLACE', required: true),
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    _buildFieldCard(
                      child: TextFormField(
                        controller: _phoneNoController,
                        decoration: _inputDecoration('PHONE NO', required: true).copyWith(
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste),
                            tooltip: 'Paste from clipboard',
                            onPressed: () async {
                              final clipboardData = await Clipboard.getData('text/plain');
                              if (clipboardData?.text != null) {
                                final formatted = _formatIndianPhone(clipboardData!.text!);
                                if (formatted != '+91 ') {
                                  setState(() {
                                    _phoneNoController.text = formatted;
                                    _phoneNoController.selection =
                                        TextSelection.fromPosition(
                                      TextPosition(offset: formatted.length),
                                    );
                                  });
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Clipboard does not contain a valid 10-digit number')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v == null || v.trim() == '+91 ' || v.trim().isEmpty) {
                            return 'Enter phone number';
                          }
                          final digits = v.replaceAll(RegExp(r'\D'), '');
                          if (digits.length != 12) return 'Enter a valid 10-digit number after +91';
                          return null;
                        },
                        onChanged: (val) {
                          _saveDraft();
                          if (!val.startsWith('+91 ')) {
                            _phoneNoController.text = '+91 ';
                            _phoneNoController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _phoneNoController.text.length),
                            );
                            return;
                          }
                          String raw = val.replaceAll('+91 ', '').replaceAll(' ', '');
                          if (raw.length > 10) raw = raw.substring(0, 10);
                          String formatted = raw.length > 5
                              ? '+91 ${raw.substring(0, 5)} ${raw.substring(5)}'
                              : '+91 $raw';
                          if (_phoneNoController.text != formatted) {
                            _phoneNoController.text = formatted;
                            _phoneNoController.selection = TextSelection.fromPosition(
                              TextPosition(offset: formatted.length),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    // SECTION: BUSINESS INFO
                    _buildSectionTitle('Business Information', Icons.business_outlined),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'NATURE OF BUSINESS ',
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'Electorize',
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('EVENT', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'EVENT',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() {
                            natureOfBusiness = v ?? '';
                            customNatureOfBusiness = '';
                            _saveDraft();
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('CATERING', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'CATERING',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() {
                            natureOfBusiness = v ?? '';
                            customNatureOfBusiness = '';
                            _saveDraft();
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('RENTAL SERVICES', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'RENTAL SERVICES',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() {
                            natureOfBusiness = v ?? '';
                            customNatureOfBusiness = '';
                            _saveDraft();
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('RESTAURANT', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'RESTAURANT',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() {
                            natureOfBusiness = v ?? '';
                            customNatureOfBusiness = '';
                            _saveDraft();
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('AUDITORIUM & HALLS', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'AUDITORIUM & HALLS',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() {
                            natureOfBusiness = v ?? '';
                            customNatureOfBusiness = '';
                            _saveDraft();
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('DECORATION', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'DECORATION',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() {
                            natureOfBusiness = v ?? '';
                            customNatureOfBusiness = '';
                            _saveDraft();
                          }),
                        ),
                        RadioListTile<String>(
                          title: const Text('OTHERS', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'OTHERS',
                          groupValue: natureOfBusiness,
                          onChanged: (v) => setState(() {
                            natureOfBusiness = v ?? '';
                            _saveDraft();
                          }),
                        ),
                        if (natureOfBusiness == 'OTHERS')
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: TextFormField(
                              controller: _customNatureOfBusinessController,
                              decoration: _inputDecoration('Please specify', required: true),
                              onChanged: (v) => customNatureOfBusiness = v,
                              validator: (v) {
                                if (natureOfBusiness == 'OTHERS' && (v == null || v.isEmpty)) {
                                  return 'Please specify nature of business';
                                }
                                return null;
                              },
                            ),
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
                    // SECTION: OTHER PURCHASES
                    _buildSectionTitle('Other Purchases', Icons.shopping_bag_outlined),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text(
                        'Do you make regular purchases apart from Malabar?',
                        style: TextStyle(
                          fontSize: 15,
                          fontFamily: 'Electorize',
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Yes', style: TextStyle(fontFamily: 'Electorize')),
                            value: 'yes',
                            groupValue: _otherPurchases,
                            onChanged: (v) {
                              setState(() {
                                _otherPurchases = v;
                                _otherPurchasesError = false;
                                _saveDraft();
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('No', style: TextStyle(fontFamily: 'Electorize')),
                            value: 'no',
                            groupValue: _otherPurchases,
                            onChanged: (v) {
                              setState(() {
                                _otherPurchases = v;
                                _otherPurchasesError = false;
                                _saveDraft();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_otherPurchasesError)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 8),
                        child: Text(
                          'Please select Yes or No',
                          style: TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Electorize'),
                        ),
                      ),
                    if (_otherPurchases == 'yes')
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFieldCard(
                              child: TextFormField(
                                controller: _otherPurchasesReasonController,
                                decoration: _inputDecoration('REASON FOR OUTSIDE PURCHASING', required: true),
                                onChanged: (v) {
                                  setState(() {
                                    _otherPurchasesReasonError = false;
                                  });
                                  _saveDraft();
                                },
                              ),
                            ),
                            if (_otherPurchasesReasonError)
                              const Padding(
                                padding: EdgeInsets.only(left: 8, top: 4),
                                child: Text(
                                  'Please enter a reason',
                                  style: TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Electorize'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    // SECTION: ORDERS & ENQUIRIES
                    _buildSectionTitle('Orders & Enquiries', Icons.receipt_long_outlined),
                    const SizedBox(height: 8),
                    _buildFieldCard(
                      child: TextFormField(
                        controller: _currentEnquiriesController,
                        decoration: _inputDecoration('CURRENT ENQUIRIES', required: true),
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    _buildFieldCard(
                      child: TextFormField(
                        controller: _confirmedOrderController,
                        decoration: _inputDecoration('CONFIRMED ORDER'),
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    _buildFieldCard(
                      child: TextFormField(
                        controller: _newProductSuggestionController,
                        decoration: _inputDecoration('REMARKS & SUGGESTIONS'),
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // SECTION: PHOTO
                    _buildSectionTitle('Attach Shop Photo', Icons.camera_alt_outlined),
                    const SizedBox(height: 8),
                    _imageFile == null
                        ? Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
                                width: 1.5,
                                strokeAlign: BorderSide.strokeAlignInside,
                              ),
                              color: const Color(0xFFFF6B35).withValues(alpha: 0.04),
                            ),
                            child: InkWell(
                              onTap: _openCamera,
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Column(
                                  children: [
                                    Icon(Icons.add_a_photo_outlined, color: const Color(0xFFFF6B35), size: 32),
                                    const SizedBox(height: 8),
                                    const Text('Tap to take photo', style: TextStyle(color: Color(0xFFFF6B35), fontFamily: 'Electorize', fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(_imageFile!, height: 140, fit: BoxFit.cover),
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
                    const SizedBox(height: 28),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF6B35), Color(0xFFFF8F65)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF6B35).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _submitForm,
                        icon: const Icon(Icons.send_rounded, size: 20),
                        label: const Text('Submit Form'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title, [IconData? icon]) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFFFF6B35)),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF2D3436),
              letterSpacing: 0.3,
              fontFamily: 'Electorize',
            ),
          ),
        ],
      ),
    );
  }
}