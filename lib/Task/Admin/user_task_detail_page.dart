import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'video_player_dialog.dart';

class UserTaskDetailPage extends StatelessWidget {
  final DocumentSnapshot taskDoc;
  const UserTaskDetailPage({super.key, required this.taskDoc});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = taskDoc.data() as Map<String, dynamic>;
    final String title = data['title'] ?? '';
    final String description = data['description'] ?? '';
    final String status = data['status'] ?? 'pending';
    final String note = data['note'] ?? '';
    final String assignedToName = data['assigned_to_name'] ?? 'Unknown';
    final String assignedToEmail = data['assigned_to_email'] ?? '';
    final Timestamp? completedTs = data['completed_at'] as Timestamp?;
    final String completedDateStr = completedTs != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(completedTs.toDate())
        : '';
    final bool isCompleted = status == 'completed';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text('$assignedToName\'s Task'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF005BAC), Color(0xFF00897B)],
            ),
          ),
        ),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          color: isDark ? const Color(0xFF16253B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignedToName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            assignedToEmail,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: !isCompleted
                            ? Colors.amber.withValues(alpha: 0.15)
                            : Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isCompleted ? Colors.amber : Colors.green,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        !isCompleted ? 'Pending' : 'Completed',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: !isCompleted ? Colors.amber : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text(
                  'Task Name',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Description',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description.isNotEmpty ? description : 'No description provided.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                if (isCompleted) ...[
                  const Divider(height: 24),
                  if (completedDateStr.isNotEmpty) ...[
                    Text(
                      'Completed At',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      completedDateStr,
                      style: const TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Completion Note',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F1A2B) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      note.isNotEmpty ? '"$note"' : 'No completion note provided.',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                  if (data['attachments'] != null && (data['attachments'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Attachments:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: (data['attachments'] as List).length,
                        itemBuilder: (context, idx) {
                          final att = (data['attachments'] as List)[idx];
                          final String url = att['url'] ?? '';
                          final String type = att['type'] ?? 'image';

                          return GestureDetector(
                            onTap: () {
                              if (type == 'video') {
                                showDialog(
                                  context: context,
                                  barrierColor: Colors.black87,
                                  builder: (context) => InAppVideoPlayerDialog(videoUrl: url),
                                );
                              } else {
                                showDialog(
                                  context: context,
                                  builder: (context) => Dialog(
                                    backgroundColor: Colors.transparent,
                                    insetPadding: const EdgeInsets.all(12),
                                    child: Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        InteractiveViewer(
                                          child: Image.network(url),
                                        ),
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: CircleAvatar(
                                            backgroundColor: Colors.black54,
                                            child: IconButton(
                                              icon: const Icon(Icons.close, color: Colors.white),
                                              onPressed: () => Navigator.pop(context),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: type == 'video'
                                      ? Colors.orangeAccent.withValues(alpha: 0.7)
                                      : (isDark ? Colors.white24 : Colors.black12),
                                  width: type == 'video' ? 1.5 : 1,
                                ),
                                color: isDark ? Colors.white10 : Colors.black12,
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (type == 'image')
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            const Center(child: Icon(Icons.broken_image)),
                                      ),
                                    )
                                  else
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.orangeAccent.withValues(alpha: 0.9),
                                            ),
                                            child: const Icon(
                                              Icons.play_arrow_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (type == 'video')
                                    Positioned(
                                      bottom: 4,
                                      left: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orangeAccent,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'VIDEO',
                                          style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
