import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'watermark_util.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  File? _capturedImage;
  String? _locationString;
  String? _dateTimeString;
  bool _isLoading = false;
  bool _isUploading = false; // <-- Add this line

  Future<File?> _compressImage(File imageFile) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String targetPath =
          p.join(tempDir.path, "${DateTime.now().millisecondsSinceEpoch}.jpg");

      // Compress the image
      final XFile? compressedXFile =
          await FlutterImageCompress.compressAndGetFile(
        imageFile.absolute.path,
        targetPath,
        quality: 40, // Adjust quality as needed (0-100, 85 is a good balance)
        minWidth: 1080, // Resize to a maximum width of 1080px
        minHeight:
            1080, // Maintain aspect ratio by setting a min height as well
        format: CompressFormat.jpeg, // Specify output format
      );

      if (compressedXFile != null) {
        return File(compressedXFile.path);
      }
      return null;
    } catch (e) {
      debugPrint("Error compressing image: $e");
      return null;
    }
  }

  Future<void> _takePhoto() async {
    setState(() {
      _isLoading = true; // Show loading indicator
    });
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      final compressedImageFile = await _compressImage(File(pickedFile.path));
      if (compressedImageFile == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Keep asking for location until granted
      LocationPermission permission;
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      while (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      }
      permission = await Geolocator.checkPermission();
      while (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          // Optionally show a dialog or snackbar to inform the user
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required!')),
          );
        }
      }

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      final placemark = placemarks.first;
      final locationText =
          "${placemark.locality}, ${placemark.administrativeArea}, ${placemark.country}\nLat ${position.latitude.toStringAsFixed(6)}, Long ${position.longitude.toStringAsFixed(6)}";
      final now = DateTime.now();
      if (!mounted) return;
      setState(() {
        _capturedImage = compressedImageFile;
        _locationString = locationText;
        _dateTimeString =
            "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
            "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
        _isLoading = false; // Hide loading indicator
      });
    } else {
      if (!mounted) return;
      setState(() {
        _isLoading = false; // Hide loading indicator if cancelled
      });
    }
  }

  Future<void> _submitForm() async {
    // Your existing form submission logic
    await FirebaseFirestore.instance.collection('marketing').add({
      // ...other fields...
      'locationString': _locationString,
      // ...other fields...
    });
  }

  Future<void> _openCamera() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraPage()),
    );
    if (result != null && result is Map && result['image'] != null) {
      setState(() {
        _capturedImage = result['image'];
        _locationString = result['location']; // <-- Capture location
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: Stack(
        children: [
          Center(
            child: _isLoading
                ? const CircularProgressIndicator()
                : _capturedImage == null
                    ? ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Take Photo'),
                        onPressed: _takePhoto,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.file(_capturedImage!, height: 300),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.save),
                            label: const Text('Use This Photo'),
                            onPressed: () async {
                              if (_capturedImage != null &&
                                  _locationString != null &&
                                  _dateTimeString != null) {
                                setState(() {
                                  _isUploading = true;
                                });
                                final watermarkText = "${_locationString!}\n$_dateTimeString";
                                final watermarkedFile = await addWatermark(
                                  imageFile: _capturedImage!,
                                  watermarkText: watermarkText,
                                );
                                setState(() {
                                  _isUploading = false;
                                });
                                // Return the image and location to the previous page
                                if (mounted) {
                                  Navigator.pop(context, {
                                    'image': watermarkedFile,
                                    'location': _locationString,
                                  });
                                }
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Retake'),
                            onPressed: _takePhoto,
                          ),
                        ],
                      ),
          ),
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
