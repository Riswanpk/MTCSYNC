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
        labelStyle: const TextStyle(
          fontSize: 13,
          fontFamily: 'Electorize',
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[900]
            : const Color(0xFFF7F2F2),
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
        locationString = result['location']; // <-- Capture location here
      });
      _saveDraft();
    }
  }

  @override
  void initState() {
    super.initState();
    _shopNameController = TextEditingController();
    _placeController = TextEditingController();
    _phoneNoController = TextEditingController();
    _customNatureOfBusinessController = TextEditingController();
    _currentEnquiriesController = TextEditingController();
    _confirmedOrderController = TextEditingController();
    _newProductSuggestionController = TextEditingController();
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
    await prefs.setString(GeneralCustomerForm.DRAFT_KEY, draftJson);
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final String? draftJson = prefs.getString(GeneralCustomerForm.DRAFT_KEY);

    if (draftJson == null) return;

    final Map<String, dynamic> draftData = jsonDecode(draftJson);

    setState(() {
      _shopNameController.text = draftData['shopName'] ?? '';
      _placeController.text = draftData['place'] ?? '';
      _phoneNoController.text = draftData['phoneNo'] ?? '';
      natureOfBusiness = draftData['natureOfBusiness'] ?? '';
      _customNatureOfBusinessController.text = draftData['customNatureOfBusiness'] ?? '';
      _currentEnquiriesController.text = draftData['currentEnquiries'] ?? '';
      _confirmedOrderController.text = draftData['confirmedOrder'] ?? '';
      _newProductSuggestionController.text = draftData['newProductSuggestion'] ?? '';
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
    await prefs.remove(GeneralCustomerForm.DRAFT_KEY);
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || natureOfBusiness.isEmpty || _imageFile == null) {
      setState(() {
        _photoError = _imageFile == null;
      });
      return;
    }

    _formKey.currentState!.save();
    shopName = _shopNameController.text;
    place = _placeController.text;
    phoneNo = _phoneNoController.text;
    customNatureOfBusiness = _customNatureOfBusinessController.text;
    currentEnquiries = _currentEnquiriesController.text;
    confirmedOrder = _confirmedOrderController.text;
    newProductSuggestion = _newProductSuggestionController.text;

    setState(() {
      isLoading = true;
      _photoError = false;
      _uploadProgress = 0.0;
    });

    String? imageUrl;
    if (_imageFile != null) {
      try {
        final ref = FirebaseStorage.instance
            .ref()
            .child('marketing')
            .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
        final uploadTask = ref.putFile(_imageFile!);

        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / (snapshot.totalBytes == 0 ? 1 : snapshot.totalBytes);
          });
        });

        await uploadTask;
        imageUrl = await ref.getDownloadURL();
      } catch (e) {
        imageUrl = null;
      }
    }

    // Submit marketing form
    final marketingDoc = await FirebaseFirestore.instance.collection('marketing').add({
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
    });

    // --- INSTANT LEAD CREATION ---
    final reminderDate = DateTime.now().add(const Duration(days: 15));
    final leadDoc = await FirebaseFirestore.instance.collection('follow_ups').add({
      'date': DateTime.now(), // Use current date for the lead
      'name': shopName,
      'address': place, // Use place as address
      'phone': phoneNo,
      'comments': currentEnquiries,
      'priority': 'Low',
      'status': 'In Progress',
      'reminder': reminderDate.toIso8601String(),
      'branch': widget.branch,
      'created_by': widget.userid,
      'created_at': FieldValue.serverTimestamp(),
      'source': 'marketing',
      'marketing_doc_id': marketingDoc.id,
    });

    // Schedule local notification using basic_channel
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'basic_channel',
        title: 'Follow-Up Reminder',
        body: 'Reminder for $shopName',
        notificationLayout: NotificationLayout.Default,
        payload: {
          'docId': leadDoc.id,
          'type': 'lead',
        },
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'EDIT_FOLLOWUP',
          label: 'Edit',
          autoDismissible: true,
        ),
      ],
      schedule: NotificationCalendar(
        year: reminderDate.year,
        month: reminderDate.month,
        day: reminderDate.day,
        hour: 9, // Default to 9 AM
        minute: 0,
        second: 0,
        millisecond: 0,
        timeZone: await AwesomeNotifications().getLocalTimeZoneIdentifier(),
        preciseAlarm: true,
      ),
    );

    await _clearDraft();

    setState(() {
      isLoading = false;
      _uploadProgress = 0.0;
      _imageFile = null;
      locationString = null;
      natureOfBusiness = '';
      customNatureOfBusiness = '';
      _shopNameController.clear();
      _placeController.clear();
      _phoneNoController.clear();
      _customNatureOfBusinessController.clear();
      _currentEnquiriesController.clear();
      _confirmedOrderController.clear();
      _newProductSuggestionController.clear();
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
                    Text(
                      'General Marketing Visit Form',
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
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : const Color.fromARGB(255, 247, 242, 242),
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
                        decoration: _inputDecoration('SHOP NAME', required: true),
                        validator: (v) => v == null || v.isEmpty ? 'Enter shop name' : null,
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : const Color.fromARGB(255, 247, 242, 242),
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
                        controller: _placeController,
                        decoration: _inputDecoration('PLACE', required: true),
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : const Color.fromARGB(255, 247, 242, 242),
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
                        decoration: _inputDecoration('PHONE NO', required: true),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter phone number';
                          if (v.length != 10) return 'Phone number must be 10 digits';
                          return null;
                        },
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // SECTION: BUSINESS INFO
                    _buildSectionTitle('Business Information'),
                    const SizedBox(height: 10),
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
                          title: const Text('AUDITORIUM', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'AUDITORIUM',
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
                    // SECTION: ORDERS & ENQUIRIES
                    _buildSectionTitle('Orders & Enquiries'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : const Color.fromARGB(255, 247, 242, 242),
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
                        decoration: _inputDecoration('CURRENT ENQUIRIES',required: true),
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : const Color.fromARGB(255, 247, 242, 242),
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
                        decoration: _inputDecoration('CONFIRMED ORDER'),
                        onChanged: (v) => _saveDraft(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : const Color.fromARGB(255, 247, 242, 242),
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
                        decoration: _inputDecoration('NEW PRODUCT SUGGESTION'),
                        onChanged: (v) => _saveDraft(),
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
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(192, 31, 113, 255),
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
//aaa