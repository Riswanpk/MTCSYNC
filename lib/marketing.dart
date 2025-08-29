import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'camera_page.dart'; // Add this import

class MarketingFormPage extends StatefulWidget {
  final String username;
  final String userid;
  final String branch;

  const MarketingFormPage({
    super.key,
    required this.username,
    required this.userid,
    required this.branch,
  });

  @override
  State<MarketingFormPage> createState() => _MarketingFormPageState();
}

class _MarketingFormPageState extends State<MarketingFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _lastItemController = TextEditingController();
  DateTime? _lastItemDate;
  final _currentEnquiriesController = TextEditingController();
  final _confirmedOrderController = TextEditingController();
  final _upcomingEventsController = TextEditingController();
  DateTime? _upcomingEventDate;
  final _upcomingTrendsController = TextEditingController();
  final _feedbackController = TextEditingController();
  File? _cameraImage;
  String? _locationString;
  bool _isUploading = false;

  @override
  void dispose() {
    _shopNameController.dispose();
    _lastItemController.dispose();
    _currentEnquiriesController.dispose();
    _confirmedOrderController.dispose();
    _upcomingEventsController.dispose();
    _upcomingTrendsController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context, ValueChanged<DateTime?> onPicked) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    onPicked(picked);
  }

  Future<void> _openCamera() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CameraPage(),
      ),
    );
    if (result is Map && result['image'] != null && result['location'] != null) {
      setState(() {
        _cameraImage = result['image'];
        _locationString = result['location'];
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_cameraImage == null) return null;
    setState(() => _isUploading = true);
    try {
      final fileName = '${widget.userid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child('marketing_photos/$fileName');
      await ref.putFile(_cameraImage!);
      final url = await ref.getDownloadURL();
      setState(() => _isUploading = false);
      return url;
    } catch (e) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image upload failed: $e')),
      );
      return null;
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lastItemDate == null || _upcomingEventDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select all dates.')),
      );
      return;
    }
    if (_cameraImage == null || _locationString == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please take a photo with location.')),
      );
      return;
    }

    final imageUrl = await _uploadImage();
    if (imageUrl == null) return;

    try {
      await FirebaseFirestore.instance.collection('marketing').add({
        'username': widget.username,
        'userid': widget.userid,
        'branch': widget.branch,
        'shopName': _shopNameController.text,
        'lastItem': _lastItemController.text,
        'lastItemDate': _lastItemDate,
        'currentEnquiries': _currentEnquiriesController.text,
        'confirmedOrder': _confirmedOrderController.text,
        'upcomingEvents': _upcomingEventsController.text,
        'upcomingEventDate': _upcomingEventDate,
        'upcomingTrends': _upcomingTrendsController.text,
        'feedback': _feedbackController.text,
        'photoUrl': imageUrl,
        'location': _locationString, // Save location as a separate field
        'timestamp': FieldValue.serverTimestamp(), // Global server timestamp
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form submitted!')),
      );
      _formKey.currentState!.reset();
      setState(() {
        _lastItemDate = null;
        _upcomingEventDate = null;
        _cameraImage = null;
        _locationString = null;
        // Clear all controllers to reset the form fields
        _shopNameController.clear();
        _lastItemController.clear();
        _currentEnquiriesController.clear();
        _confirmedOrderController.clear();
        _upcomingEventsController.clear();
        _upcomingTrendsController.clear();
        _feedbackController.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketing Form'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _shopNameController,
                decoration: const InputDecoration(labelText: 'Shop Name'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastItemController,
                decoration: const InputDecoration(labelText: 'Last Item Purchased'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(_lastItemDate == null
                    ? 'Select Last Item Purchased Date/Month'
                    : 'Last Item Purchased Date: ${_lastItemDate!.year}-${_lastItemDate!.month.toString().padLeft(2, '0')}-${_lastItemDate!.day.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _pickDate(context, (date) {
                  setState(() => _lastItemDate = date);
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _currentEnquiriesController,
                decoration: const InputDecoration(labelText: 'Current Enquiries'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmedOrderController,
                decoration: const InputDecoration(labelText: 'Confirmed Order'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _upcomingEventsController,
                decoration: const InputDecoration(labelText: 'Upcoming Big Events Details'),
              ),
              ListTile(
                title: Text(_upcomingEventDate == null
                    ? 'Select Upcoming Event Date'
                    : 'Upcoming Event Date: ${_upcomingEventDate!.year}-${_upcomingEventDate!.month.toString().padLeft(2, '0')}-${_upcomingEventDate!.day.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.event),
                onTap: () => _pickDate(context, (date) {
                  setState(() => _upcomingEventDate = date);
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _upcomingTrendsController,
                decoration: const InputDecoration(labelText: 'Upcoming Trends'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _feedbackController,
                decoration: const InputDecoration(labelText: 'Feedback About Our Products and Services'),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Location Photo (Required):'),
                  const SizedBox(height: 8),
                  _cameraImage != null
                      ? Image.file(_cameraImage!, height: 120)
                      : const Text('No image taken.'),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Open Camera'),
                    onPressed: _isUploading ? null : _openCamera,
                  ),
                  if (_locationString != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Location: $_locationString',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  // Show the server timestamp (not editable, just viewing)
                  if (_cameraImage != null)
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('marketing')
                          .orderBy('timestamp', descending: true)
                          .limit(1)
                          .get()
                          .then((snap) {
                            if (snap.docs.isNotEmpty) {
                              return snap.docs.first as DocumentSnapshot<Object?>;
                            } else {
                              throw Exception('No documents found');
                            }
                          }),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 8.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }
                        if (snapshot.hasData && snapshot.data != null) {
                          final ts = snapshot.data!['timestamp'];
                          if (ts != null) {
                            final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Server Timestamp: ${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                              ),
                            );
                          }
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  const SizedBox(height: 12),
                  if (_isUploading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitForm,
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}