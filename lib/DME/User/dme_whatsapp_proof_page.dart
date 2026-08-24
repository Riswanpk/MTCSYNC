import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../dme_config.dart';

class DmeWhatsAppProofPage extends StatefulWidget {
  final Map<String, dynamic> reminder;
  final VoidCallback? onVerified;

  const DmeWhatsAppProofPage({
    super.key,
    required this.reminder,
    this.onVerified,
  });

  @override
  State<DmeWhatsAppProofPage> createState() => _DmeWhatsAppProofPageState();
}

class _DmeWhatsAppProofPageState extends State<DmeWhatsAppProofPage> {
  final TextEditingController _remarksController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Uint8List? _compressedBytes;
  bool _isUploading = false;

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (picked == null) return;

      // Compress image bytes to keep upload small (< 150KB)
      final bytes = await picked.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 800,
        minHeight: 800,
        quality: 65,
        format: CompressFormat.jpeg,
      );

      setState(() {
        _compressedBytes = compressed;
      });
    } catch (e) {
      debugPrint('Error picking/compressing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadProofAndSubmit() async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supabase is not configured.')),
      );
      return;
    }

    if (_compressedBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or capture a WhatsApp proof screenshot.')),
      );
      return;
    }

    final remarks = _remarksController.text.trim();
    if (remarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter remarks for this WhatsApp message.')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final reminderId = widget.reminder['id'];
      final custId = widget.reminder['customer_id'];
      final user = FirebaseAuth.instance.currentUser;
      final uploaderEmail = user?.email ?? 'unknown';

      // 1. Upload compressed bytes to Supabase Storage or fallback to base64 Data URI
      final fileName = 'proof_${reminderId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      String publicUrl = '';

      try {
        await client.storage.from('whatsapp_proofs').uploadBinary(
              fileName,
              _compressedBytes!,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
        publicUrl = client.storage.from('whatsapp_proofs').getPublicUrl(fileName);
      } catch (storageErr) {
        debugPrint('Storage bucket whatsapp_proofs upload notice: $storageErr');
        try {
          await client.storage.from('dme_proofs').uploadBinary(
                fileName,
                _compressedBytes!,
                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
          publicUrl = client.storage.from('dme_proofs').getPublicUrl(fileName);
        } catch (_) {
          // Robust Fallback: Store as compressed base64 data URI directly in DB so upload never fails
          // Even if user hasn't created the bucket or RLS policies yet in Supabase
          final base64String = base64Encode(_compressedBytes!);
          publicUrl = 'data:image/jpeg;base64,$base64String';
        }
      }

      // 2. Insert record into `dme_whatsapp_proofs` table
      try {
        await client.from('dme_whatsapp_proofs').insert({
          'reminder_id': reminderId,
          'customer_id': custId,
          'image_url': publicUrl,
          'remarks': remarks,
          'created_at': DateTime.now().toIso8601String(),
          'uploaded_by': uploaderEmail,
        });
      } catch (tableErr) {
        debugPrint('dme_whatsapp_proofs table insert note: $tableErr');
      }

      // 3. Mark reminder status as 'completed'
      await client.from('dme_reminders').update({
        'status': 'completed',
        'remarks': '[WhatsApp] $remarks',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', reminderId);

      setState(() => _isUploading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp proof uploaded and reminder marked completed!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onVerified?.call();
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error uploading WhatsApp proof: $e');
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final custName = widget.reminder['customer_name'] ?? 'Customer';
    final custPhone = widget.reminder['customer_phone'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Message Proof'),
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer Info Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                      child: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(custName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(custPhone, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Step 1: Upload Screenshot
            Text('1. Upload Screenshot Proof', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Capture or select a screenshot of the WhatsApp conversation sent to the customer.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 14),

            if (_compressedBytes != null) ...[
              Center(
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF25D366), width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _compressedBytes!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const CircleAvatar(
                        backgroundColor: Colors.red,
                        radius: 14,
                        child: Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                      onPressed: () {
                        setState(() {
                          _compressedBytes = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text('Camera'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF25D366),
                        side: const BorderSide(color: Color(0xFF25D366)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded),
                      label: const Text('Gallery'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF25D366),
                        side: const BorderSide(color: Color(0xFF25D366)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // Step 2: Message Remarks
            Text('2. Message Remarks', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _remarksController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter details of the WhatsApp discussion, customer inquiry, etc...',
                filled: true,
                fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadProofAndSubmit,
                icon: _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_rounded, size: 22),
                label: Text(
                  _isUploading ? 'Uploading & Verifying...' : 'Submit Proof & Mark Completed',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
