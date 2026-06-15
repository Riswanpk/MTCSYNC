import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';
import 'firebase_storage_helper.dart';

class VoiceFileUploadWidget extends StatefulWidget {
  final Function(String? fileUrl) onFileUploaded;
  final Function(bool isUploading)? onUploadStateChanged;
  final bool enabled;
  final String? initialFileUrl;
  final String uploadPath; // Path in Firebase Storage (e.g., 'complaints/voice_notes')

  const VoiceFileUploadWidget({
    super.key,
    required this.onFileUploaded,
    this.onUploadStateChanged,
    this.enabled = true,
    this.initialFileUrl,
    required this.uploadPath,
  });

  @override
  State<VoiceFileUploadWidget> createState() => _VoiceFileUploadWidgetState();
}

class _VoiceFileUploadWidgetState extends State<VoiceFileUploadWidget> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  String? _selectedFilePath;
  String? _uploadedFileUrl;
  bool _isUploading = false;
  bool _isPlaying = false;
  double _playbackProgress = 0.0;
  String? _fileName;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _uploadedFileUrl = widget.initialFileUrl;
    _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
    _audioPlayer.onDurationChanged.listen((Duration duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });
    _audioPlayer.onPositionChanged.listen((Duration pos) {
      if (mounted && _duration != null) {
        setState(() => 
          _playbackProgress = _duration!.inMilliseconds > 0
              ? pos.inMilliseconds / _duration!.inMilliseconds
              : 0.0
        );
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedFilePath = file.path;
          _fileName = file.name;
        });
        // Auto-upload immediately after selection
        await _uploadFile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFilePath == null || _selectedFilePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a voice file first')),
      );
      return;
    }

    setState(() => _isUploading = true);
    widget.onUploadStateChanged?.call(true);

    try {
      final file = File(_selectedFilePath!);
      final fileName = _fileName ?? DateTime.now().millisecondsSinceEpoch.toString();
      Reference? ref;
      Object? lastError;

      for (final storage in FirebaseStorageHelper.storageCandidates()) {
        final candidateRef = storage
            .ref()
            .child('${widget.uploadPath}/$fileName');
        try {
          await candidateRef.putFile(file);
          ref = candidateRef;
          break;
        } catch (e) {
          lastError = e;
          if (!FirebaseStorageHelper.isBucketNotFoundError(e)) rethrow;
        }
      }

      if (ref == null) {
        throw lastError ?? Exception('Unable to upload voice file to any storage bucket');
      }

      final downloadUrl = await ref.getDownloadURL();

      setState(() {
        _uploadedFileUrl = downloadUrl;
        _selectedFilePath = null;
        _fileName = null;
      });

      widget.onFileUploaded(downloadUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice file uploaded successfully ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading file: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
        widget.onUploadStateChanged?.call(false);
      }
    }
  }

  Future<void> _playAudio(String url) async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(UrlSource(url));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    }
  }

  Future<void> _removeFile() async {
    setState(() {
      _uploadedFileUrl = null;
      _selectedFilePath = null;
      _fileName = null;
      _playbackProgress = 0.0;
    });
    await _audioPlayer.stop();
    widget.onFileUploaded(null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mic,
                color: Colors.blue[600],
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Voice Note (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // If file already uploaded, show playback controls
          if (_uploadedFileUrl != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[600], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Voice file uploaded',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _playAudio(_uploadedFileUrl!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[600],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isPlaying ? 'Playing...' : 'Play',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _removeFile,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red[300]!),
                          ),
                          child: Icon(
                            Icons.delete_outline,
                            color: Colors.red[600],
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isPlaying) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _playbackProgress,
                        minHeight: 4,
                        backgroundColor: Colors.blue[200],
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (_selectedFilePath != null && !_isUploading) ...[
            // File selected but not uploaded yet
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.audiotrack, color: Colors.orange[600], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _fileName ?? 'File selected',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[700],
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _uploadFile,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.blue[600],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.upload, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Upload',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _selectedFilePath = null),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.close,
                            color: Colors.grey[700],
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (!_isUploading) ...[
            // No file selected - show upload area
            GestureDetector(
              onTap: widget.enabled ? _pickFile : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.enabled ? Colors.blue[300]! : Colors.grey[300]!,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.upload_file,
                      size: 32,
                      color: widget.enabled ? Colors.blue[600] : Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to upload voice file',
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.enabled ? Colors.blue[600] : Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'MP3, M4A, WAV, etc.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Uploading
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  const SizedBox(
                    height: 32,
                    width: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Uploading voice file...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
