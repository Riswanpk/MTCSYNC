import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Manages background image pre-uploading so the upload happens while
/// the user fills in the rest of the form, not at submit time.
class ImageUploadHelper {
  Future<String?>? _uploadFuture;
  String? _cachedUrl;
  bool _cancelled = false;
  UploadTask? _activeUploadTask;

  /// Start uploading the image immediately in the background.
  /// Call this as soon as the camera returns an image.
  void startUpload(File imageFile) {
    _cancelled = false;
    _cachedUrl = null;
    _uploadFuture = _doUpload(imageFile);
  }

  Future<String?> _doUpload(File imageFile) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('marketing')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      _activeUploadTask = ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      await _activeUploadTask;

      if (_cancelled) return null;

      final url = await ref.getDownloadURL();
      _cachedUrl = url;
      return url;
    } catch (e) {
      debugPrint('Background upload error: $e');
      return null;
    }
  }

  /// Get the upload result. If already finished, returns immediately.
  /// If still in progress, waits for it to complete.
  /// If no upload was started, returns null.
  Future<String?> getUploadResult() async {
    if (_cachedUrl != null) return _cachedUrl;
    if (_uploadFuture == null) return null;
    return await _uploadFuture;
  }

  /// Whether an upload is in progress (started but not yet resolved).
  bool get isUploading => _uploadFuture != null && _cachedUrl == null;

  /// Cancel/reset. Call when user retakes photo or form is reset.
  void cancel() {
    _cancelled = true;
    _activeUploadTask?.cancel();
    _activeUploadTask = null;
    _uploadFuture = null;
    _cachedUrl = null;
  }

  /// Reset everything (e.g., after successful submit).
  void reset() {
    cancel();
  }
}
