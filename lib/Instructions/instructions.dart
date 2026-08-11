import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:intl/intl.dart';
import '../Navigation/user_cache_service.dart';
import '../Misc/firebase_storage_helper.dart';

class InstructionsPage extends StatefulWidget {
  const InstructionsPage({super.key});

  @override
  State<InstructionsPage> createState() => _InstructionsPageState();
}

class _InstructionsPageState extends State<InstructionsPage> {
  bool _isLoading = true;
  String _userRole = '';
  bool _isAdmin = false;

  final List<Map<String, String>> _availableRoles = const [
    {'label': 'Sales', 'value': 'sales'},
    {'label': 'Manager', 'value': 'manager'},
    {'label': 'Asst. Manager', 'value': 'asst_manager'},
    {'label': 'Sync Head', 'value': 'sync_head'},
    {'label': 'SME', 'value': 'sme'},
    {'label': 'DME User', 'value': 'dme_user'},
    {'label': 'DME Admin', 'value': 'dme_admin'},
    {'label': 'Supersale Admin', 'value': 'supersale_admin'},
    {'label': 'Core Team', 'value': 'core_team'},
  ];

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    await UserCacheService.instance.ensureLoaded();
    final role = (UserCacheService.instance.role ?? '').toLowerCase();
    setState(() {
      _userRole = role;
      _isAdmin = role == 'admin';
      _isLoading = false;
    });
  }

  void _openUploadDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UploadVideoSheet(availableRoles: _availableRoles),
    );
  }

  Future<void> _deleteVideo(String docId, String? storagePath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Video'),
        content: const Text('Are you sure you want to delete this instruction video?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (storagePath != null && storagePath.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(storagePath).delete();
        } catch (_) {
          // If deleted from default bucket fails, try candidates
          for (final storage in FirebaseStorageHelper.storageCandidates()) {
            try {
              await storage.ref(storagePath).delete();
              break;
            } catch (_) {}
          }
        }
      }
      await FirebaseFirestore.instance.collection('instruction_videos').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video deleted successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete video: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Instructions'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openUploadDialog,
              backgroundColor: const Color(0xFF005BAC),
              icon: const Icon(Icons.upload_file, color: Colors.white),
              label: const Text('Upload Video', style: TextStyle(color: Colors.white)),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('instruction_videos')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Error loading videos: ${snapshot.error}'),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                // Filter videos accessible by current user (if not admin)
                final filteredDocs = docs.where((doc) {
                  if (_isAdmin) return true;
                  final data = doc.data() as Map<String, dynamic>;
                  final targetRoles = List<String>.from(data['targetRoles'] ?? []);
                  if (targetRoles.isEmpty || targetRoles.contains('all')) return true;
                  return targetRoles.contains(_userRole);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.video_library_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No instruction videos available',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                        if (_isAdmin) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Tap "+ Upload Video" below to add a video instruction',
                            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                          ),
                        ]
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final title = data['title'] as String? ?? 'Instruction Video';
                    final videoUrl = data['videoUrl'] as String? ?? '';
                    final storagePath = data['storagePath'] as String?;
                    final targetRoles = List<String>.from(data['targetRoles'] ?? []);
                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                    final formattedDate = createdAt != null
                        ? DateFormat('dd MMM yyyy, hh:mm a').format(createdAt)
                        : '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_circle_fill, color: Color(0xFF005BAC), size: 36),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (formattedDate.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Uploaded: $formattedDate',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ),
                            if (_isAdmin && targetRoles.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: targetRoles.map((r) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue.shade200),
                                      ),
                                      child: Text(
                                        r.toUpperCase(),
                                        style: TextStyle(fontSize: 10, color: Colors.blue[800], fontWeight: FontWeight.w600),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.green, size: 30),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => VideoPlayerScreen(
                                      title: title,
                                      videoUrl: videoUrl,
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (_isAdmin)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _deleteVideo(doc.id, storagePath),
                              ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => VideoPlayerScreen(
                                title: title,
                                videoUrl: videoUrl,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _UploadVideoSheet extends StatefulWidget {
  final List<Map<String, String>> availableRoles;
  const _UploadVideoSheet({required this.availableRoles});

  @override
  State<_UploadVideoSheet> createState() => _UploadVideoSheetState();
}

class _UploadVideoSheetState extends State<_UploadVideoSheet> {
  final _titleController = TextEditingController();
  final Set<String> _selectedRoles = {'all'};
  PlatformFile? _selectedVideo;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedVideo = result.files.first;
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = result.files.first.name.split('.').first;
        }
      });
    }
  }

  Future<void> _uploadVideo() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a video name/title')),
      );
      return;
    }

    if (_selectedVideo == null || _selectedVideo!.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a video file to upload')),
      );
      return;
    }

    if (_selectedRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one visible role')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final file = File(_selectedVideo!.path!);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_selectedVideo!.name}';
      final storagePath = 'instruction_videos/$fileName';

      UploadTask? uploadTask;
      for (final storage in FirebaseStorageHelper.storageCandidates()) {
        try {
          final ref = storage.ref().child(storagePath);
          uploadTask = ref.putFile(file);
          break;
        } catch (_) {}
      }

      if (uploadTask == null) {
        final ref = FirebaseStorage.instance.ref().child(storagePath);
        uploadTask = ref.putFile(file);
      }

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (mounted) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      });

      final taskSnapshot = await uploadTask;
      final downloadUrl = await taskSnapshot.ref.getDownloadURL();

      final currentUser = UserCacheService.instance;
      await FirebaseFirestore.instance.collection('instruction_videos').add({
        'title': title,
        'videoUrl': downloadUrl,
        'storagePath': storagePath,
        'targetRoles': _selectedRoles.toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'uploadedBy': currentUser.email ?? currentUser.username ?? 'Admin',
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video uploaded successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Upload Video Instruction',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Video Title / Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _isUploading ? null : _pickVideo,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.video_call, color: Color(0xFF005BAC), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedVideo != null ? _selectedVideo!.name : 'Tap to select video file',
                        style: TextStyle(
                          fontSize: 14,
                          color: _selectedVideo != null ? Colors.black87 : Colors.grey[600],
                          fontWeight: _selectedVideo != null ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.attach_file, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Target User Roles (Who can see):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('ALL USERS'),
                  selected: _selectedRoles.contains('all'),
                  selectedColor: const Color(0xFF005BAC).withValues(alpha: 0.2),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedRoles.clear();
                        _selectedRoles.add('all');
                      } else {
                        _selectedRoles.remove('all');
                      }
                    });
                  },
                ),
                ...widget.availableRoles.map((roleObj) {
                  final key = roleObj['value']!;
                  final label = roleObj['label']!;
                  final isSelected = _selectedRoles.contains(key);

                  return FilterChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedRoles.remove('all');
                        if (selected) {
                          _selectedRoles.add(key);
                        } else {
                          _selectedRoles.remove(key);
                        }
                      });
                    },
                  );
                }),
              ],
            ),
            const SizedBox(height: 20),
            if (_isUploading) ...[
              LinearProgressIndicator(value: _uploadProgress > 0 ? _uploadProgress : null),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Uploading video... ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _uploadVideo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Upload & Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String title;
  final String videoUrl;

  const VideoPlayerScreen({
    super.key,
    required this.title,
    required this.videoUrl,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        allowMuting: true,
        showControls: true,
        aspectRatio: _videoPlayerController.value.aspectRatio > 0
            ? _videoPlayerController.value.aspectRatio
            : 16 / 9,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      setState(() {});
    } catch (e) {
      setState(() {
        _isError = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _isError
            ? Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Failed to play video:\n$_errorMessage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : _chewieController != null &&
                    _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}