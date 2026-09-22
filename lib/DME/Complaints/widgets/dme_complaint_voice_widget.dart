import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mtcsync/DME/Misc/dme_config.dart';
import 'package:mtcsync/Misc/firebase_storage_helper.dart';

/// Widget to select, upload, and play an audio recording for a complaint.
/// Note: By explicit requirement, the word 'optional' is never displayed in the UI.
class DmeComplaintVoiceWidget extends StatefulWidget {
  final String? initialAudioUrl;
  final ValueChanged<String?> onAudioChanged;
  final ValueChanged<bool>? onUploadStateChanged;
  final bool readOnly;

  const DmeComplaintVoiceWidget({
    super.key,
    this.initialAudioUrl,
    required this.onAudioChanged,
    this.onUploadStateChanged,
    this.readOnly = false,
  });

  @override
  State<DmeComplaintVoiceWidget> createState() => _DmeComplaintVoiceWidgetState();
}

class _DmeComplaintVoiceWidgetState extends State<DmeComplaintVoiceWidget> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _audioUrl;
  String? _localFilePath;
  String? _fileName;
  bool _isUploading = false;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioUrl = widget.initialAudioUrl;

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
  }

  @override
  void didUpdateWidget(covariant DmeComplaintVoiceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAudioUrl != oldWidget.initialAudioUrl &&
        widget.initialAudioUrl != _audioUrl) {
      setState(() {
        _audioUrl = widget.initialAudioUrl;
      });
    }
  }

  @override
  void dispose() {
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickAudioFile() async {
    if (widget.readOnly || _isUploading) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.first;
        if (picked.path == null) return;

        setState(() {
          _localFilePath = picked.path;
          _fileName = picked.name;
        });

        await _uploadAudioFile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking audio: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadAudioFile() async {
    if (_localFilePath == null) return;
    setState(() => _isUploading = true);
    widget.onUploadStateChanged?.call(true);

    final file = File(_localFilePath!);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = _fileName?.split('.').last ?? 'mp3';
    final storagePath = 'complaints/voice_$timestamp.$extension';

    String? uploadedUrl;

    // 1. Try Supabase Storage
    try {
      final client = await DmeConfig.getClient();
      if (client != null) {
        final bytes = await file.readAsBytes();
        await client.storage.from('dme_complaints').uploadBinary(
          storagePath,
          bytes,
        );
        uploadedUrl = client.storage.from('dme_complaints').getPublicUrl(storagePath);
      }
    } catch (supabaseErr) {
      debugPrint('Supabase storage upload notice: $supabaseErr. Trying Firebase fallback...');
    }

    // 2. Fallback to Firebase Storage
    if (uploadedUrl == null || uploadedUrl.isEmpty) {
      try {
        Reference? ref;
        Object? lastError;
        for (final storage in FirebaseStorageHelper.storageCandidates()) {
          final candidateRef = storage.ref().child('dme_complaints/voice_$timestamp.$extension');
          try {
            await candidateRef.putFile(file);
            ref = candidateRef;
            break;
          } catch (e) {
            lastError = e;
            if (!FirebaseStorageHelper.isBucketNotFoundError(e)) rethrow;
          }
        }
        if (ref != null) {
          uploadedUrl = await ref.getDownloadURL();
        } else if (lastError != null) {
          throw lastError;
        }
      } catch (fbErr) {
        debugPrint('Firebase storage upload failed: $fbErr');
      }
    }

    if (!mounted) return;

    if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
      setState(() {
        _audioUrl = uploadedUrl;
        _isUploading = false;
      });
      widget.onAudioChanged(_audioUrl);
      widget.onUploadStateChanged?.call(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio recording attached successfully ✓'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      setState(() => _isUploading = false);
      widget.onUploadStateChanged?.call(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to upload audio. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      final source = _localFilePath != null && File(_localFilePath!).existsSync()
          ? DeviceFileSource(_localFilePath!)
          : (_audioUrl != null && _audioUrl!.isNotEmpty ? UrlSource(_audioUrl!) : null);

      if (source != null) {
        await _audioPlayer.play(source);
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasAudio = (_audioUrl != null && _audioUrl!.isNotEmpty) || _localFilePath != null;

    if (!hasAudio && widget.readOnly) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.mic_off_rounded, size: 20, color: Colors.grey),
            SizedBox(width: 8),
            Text('No audio record attached', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    if (!hasAudio) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132238) : const Color(0xFFF3F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFF005BAC).withValues(alpha: 0.2),
            width: 1.2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _isUploading ? null : _pickAudioFile,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isUploading) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF005BAC)),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Uploading audio...',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF005BAC)),
                    ),
                  ] else ...[
                    const Icon(Icons.mic_rounded, color: Color(0xFF005BAC), size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Attach Voice Record',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF005BAC),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Has audio — Player View
    final progress = (_duration.inMilliseconds > 0)
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132238) : const Color(0xFFEEF5FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF005BAC).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                  color: const Color(0xFF005BAC),
                  size: 38,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _togglePlayPause,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fileName ?? 'Voice Recording',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: isDark ? Colors.white12 : Colors.black12,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF005BAC)),
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.readOnly) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                  tooltip: 'Remove audio',
                  onPressed: () {
                    _audioPlayer.stop();
                    setState(() {
                      _audioUrl = null;
                      _localFilePath = null;
                      _fileName = null;
                      _isPlaying = false;
                      _position = Duration.zero;
                    });
                    widget.onAudioChanged(null);
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
