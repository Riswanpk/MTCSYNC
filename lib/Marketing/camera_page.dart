import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'watermark_util.dart';
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
        quality: 30, // Adjust quality as needed (0-100, 85 is a good balance)
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
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);

      if (pickedFile != null) {
        final compressedImageFile = await _compressImage(File(pickedFile.path));
        if (compressedImageFile == null) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          return;
        }

        // Keep asking for location until granted (with max retries to avoid infinite loop)
        LocationPermission permission;
        int retries = 0;
        const maxRetries = 3;
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        while (!serviceEnabled && retries < maxRetries) {
          retries++;
          await Geolocator.openLocationSettings();
          if (!mounted) return;
          serviceEnabled = await Geolocator.isLocationServiceEnabled();
        }
        if (!serviceEnabled) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are required. Please enable them.')),
          );
          setState(() => _isLoading = false);
          return;
        }

        retries = 0;
        permission = await Geolocator.checkPermission();
        while ((permission == LocationPermission.denied || permission == LocationPermission.deniedForever) && retries < maxRetries) {
          retries++;
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission is required!')),
            );
          }
        }
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          return;
        }

        final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        
        String locationText;
        try {
          final placemarks =
              await placemarkFromCoordinates(position.latitude, position.longitude);
          if (placemarks.isNotEmpty) {
            final placemark = placemarks.first;
            locationText =
                "${placemark.locality ?? ''}, ${placemark.administrativeArea ?? ''}, ${placemark.country ?? ''}\nLat ${position.latitude.toStringAsFixed(6)}, Long ${position.longitude.toStringAsFixed(6)}";
          } else {
            locationText =
                "Lat ${position.latitude.toStringAsFixed(6)}, Long ${position.longitude.toStringAsFixed(6)}";
          }
        } catch (e) {
          debugPrint('Error getting placemark: $e');
          locationText =
              "Lat ${position.latitude.toStringAsFixed(6)}, Long ${position.longitude.toStringAsFixed(6)}";
        }

        final now = DateTime.now();
        if (!mounted) return;
        setState(() {
          _capturedImage = compressedImageFile;
          _locationString = locationText;
          _dateTimeString =
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
              "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error in _takePhoto: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error taking photo: ${e.toString().length > 80 ? e.toString().substring(0, 80) : e}')),
      );
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
                                try {
                                  final watermarkText = "${_locationString!}\n$_dateTimeString";
                                  // Process watermark in background to avoid blocking UI
                                  final watermarkedFile = await addWatermark(
                                    imageFile: _capturedImage!,
                                    watermarkText: watermarkText,
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    _isUploading = false;
                                  });
                                  // Return the image and location to the previous page
                                  Navigator.pop(context, {
                                    'image': watermarkedFile,
                                    'location': _locationString,
                                  });
                                } catch (e) {
                                  debugPrint('Error adding watermark: $e');
                                  if (!mounted) return;
                                  setState(() {
                                    _isUploading = false;
                                  });
                                  // Return image without watermark if watermarking fails
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Could not add watermark, using original image')),
                                  );
                                  Navigator.pop(context, {
                                    'image': _capturedImage,
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Processing image...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
