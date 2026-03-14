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

/// Simple data class to hold location result
class _LocationResult {
  final Position position;
  _LocationResult(this.position);
}

class _CameraPageState extends State<CameraPage> {
  File? _capturedImage;
  String? _locationString;
  String? _dateTimeString;
  bool _isLoading = false;
  bool _isUploading = false;

  /// Gets the device location. Returns null if location unavailable.
  /// Uses medium accuracy — sufficient for watermark text, much faster than high.
  Future<_LocationResult?> _getLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('Location service enabled: $serviceEnabled');
      if (!serviceEnabled) {
        debugPrint('Location service is not enabled');
        return null;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('Initial permission status: $permission');
      
      // If denied, request permission once
      if (permission == LocationPermission.denied) {
        debugPrint('Requesting location permission...');
        permission = await Geolocator.requestPermission();
        debugPrint('Permission after request: $permission');
      }
      
      // If still denied or permanently denied, return null
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied: $permission');
        return null;
      }

      debugPrint('Attempting to get current position...');
      // Get position - use last known location as fallback for speed
      Position? position;
      try {
        // Try to get last known position first (instant)
        position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          debugPrint('Using last known position: lat=${position.latitude}, lon=${position.longitude}');
          return _LocationResult(position);
        }
      } catch (e) {
        debugPrint('Could not get last known position: $e');
      }
      
      // If no last known position, get current position with adequate timeout for GPS fix
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 20), // GPS can take 10-15s for initial fix
        );
        debugPrint('Got current position: lat=${position.latitude}, lon=${position.longitude}');
        return _LocationResult(position);
      } catch (timeoutError) {
        debugPrint('Timeout getting current position: $timeoutError');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  Future<File?> _compressImage(File imageFile) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String targetPath =
          p.join(tempDir.path, "${DateTime.now().millisecondsSinceEpoch}.jpg");

      // Compress the image — smaller dimensions = faster upload
      final XFile? compressedXFile =
          await FlutterImageCompress.compressAndGetFile(
        imageFile.absolute.path,
        targetPath,
        quality: 25, // Aggressive compression for fast upload
        minWidth: 800, // 800px is sufficient for marketing visit photos
        minHeight: 800,
        format: CompressFormat.jpeg,
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
        // --- OPTIMIZATION: Run compression and location fetch in parallel ---
        final compressionFuture = _compressImage(File(pickedFile.path));
        final locationFuture = _getLocation().timeout(
          const Duration(seconds: 25), // Allow enough time for GPS fix
          onTimeout: () {
            debugPrint('Location fetch timed out after 25 seconds');
            return null;
          },
        );

        final results = await Future.wait([compressionFuture, locationFuture]);
        final compressedImageFile = results[0] as File?;
        final locationResult = results[1] as _LocationResult?;

        if (compressedImageFile == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to process image. Please try again.')),
          );
          setState(() => _isLoading = false);
          return;
        }

        // GPS is MANDATORY - cannot proceed without location
        if (locationResult == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ GPS location is required. Please:\n• Go outdoors or near a window\n• Wait for GPS signal to lock\n• Ensure Location is High Accuracy mode'),
              duration: Duration(seconds: 7),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isLoading = false);
          return;
        }

        final position = locationResult.position;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cameraIconColor = isDark ? Colors.white : Colors.black;
    final cameraTextColor = isDark ? Colors.white : Colors.black;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera', style: TextStyle(fontFamily: 'Electorize', fontWeight: FontWeight.bold, letterSpacing: 1)),
        centerTitle: true,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Colors.white, Color(0xFFF5F5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
          ),
        ),
      ),
      backgroundColor: isDark ? const Color(0xFF0F0F1A) : Colors.white,
      body: Stack(
        children: [
          Center(
            child: _isLoading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 56, height: 56,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(const Color.fromARGB(255, 0, 0, 0)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Acquiring GPS location...', style: TextStyle(color: Colors.grey.shade400, fontFamily: 'Electorize', fontSize: 14)),
                      const SizedBox(height: 8),
                      Text('Please wait up to 20 seconds', style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Electorize', fontSize: 12)),
                    ],
                  )
                : _capturedImage == null
                    ? GestureDetector(
                        onTap: _takePhoto,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isDark
                                ? const LinearGradient(
                                    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : const LinearGradient(
                                    colors: [Colors.white, Color(0xFFF5F5F5)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                            border: Border.all(color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.5), width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? Colors.white.withOpacity(0.15)
                                    : const Color.fromARGB(255, 4, 4, 4).withOpacity(0.15),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt_rounded, size: 56, color: cameraIconColor),
                              const SizedBox(height: 12),
                              Text('Tap to Capture', style: TextStyle(fontFamily: 'Electorize', color: cameraTextColor, fontSize: 14, letterSpacing: 0.5)),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.3), width: 1.5),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8)),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.file(_capturedImage!, height: 300, fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                    gradient: isDark
                                      ? const LinearGradient(colors: [Color(0xFF009688), Color(0xFF00796B)])
                                      : const LinearGradient(colors: [Color(0xFF80CBC4), Color(0xFFB2DFDB)]),
                                  boxShadow: [
                                    BoxShadow(color: const Color(0xFF009688).withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4)),
                                  ],
                                ),
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                                  label: const Text('Use This Photo', style: TextStyle(fontFamily: 'Electorize', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
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
                                        // Re-compress after watermarking — the watermark library
                                        // may output a much larger file (decoded/re-encoded pixels).
                                        // This re-compression is the #1 upload speed optimization.
                                        final reCompressed = await _compressImage(watermarkedFile);
                                        final finalFile = reCompressed ?? watermarkedFile;
                                        if (!mounted) return;
                                        setState(() {
                                          _isUploading = false;
                                        });
                                        // Return the image and location to the previous page
                                        Navigator.pop(context, {
                                          'image': finalFile,
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
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.camera_alt_rounded, color: cameraIconColor),
                                label: Text('Retake', style: TextStyle(fontFamily: 'Electorize', fontSize: 15, color: cameraTextColor)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: cameraIconColor.withOpacity(0.5), width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: _takePhoto,
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
          if (_isUploading)
            Container(
              color: isDark ? const Color(0xCC0F0F1A) : Colors.white.withOpacity(0.85),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 56, height: 56,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(const Color.fromARGB(255, 0, 0, 0)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Processing image...',
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontFamily: 'Electorize', letterSpacing: 0.5),
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
