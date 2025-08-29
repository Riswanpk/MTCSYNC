import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'watermark_util.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  File? _capturedImage;
  String? _locationString;
  String? _dateTimeString;
  bool _isLoading = false; // Add this line

  Future<void> _takePhoto() async {
    setState(() {
      _isLoading = true; // Show loading indicator
    });
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (pickedFile != null) {
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
        _capturedImage = File(pickedFile.path);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator() // Show loading while processing
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
                      if (_locationString != null && _dateTimeString != null)
                        Text(
                          "${_locationString!}\n$_dateTimeString",
                          style: const TextStyle(fontSize: 14),
                          textAlign: TextAlign.left,
                        ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Use This Photo'),
                        onPressed: () async {
                          if (_capturedImage != null &&
                              _locationString != null &&
                              _dateTimeString != null) {
                            final watermarkText = "${_locationString!}\n$_dateTimeString";
                            final watermarkedFile = await addWatermark(
                              imageFile: _capturedImage!,
                              watermarkText: watermarkText,
                            );
                            Navigator.pop(context, {
                              'image': watermarkedFile,
                              'location': _locationString,
                            });
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
    );
  }
}
