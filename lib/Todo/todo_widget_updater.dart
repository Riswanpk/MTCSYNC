import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:home_widget/home_widget.dart';

Future<void> updateTodoWidgetFromFirestore() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final snapshot = await FirebaseFirestore.instance
      .collection('todo')
      .where('email', isEqualTo: user.email)
      .where('status', isEqualTo: 'pending')
      .limit(20)
      .get();

  final todoCount = snapshot.docs.isNotEmpty
      ? '${snapshot.docs.length} tasks'
      : '0 tasks';

  // Build structured data: "docId|||title\n\n\ndocId|||title..."
  final todoItems = snapshot.docs
      .map((doc) => '${doc.id}|||${doc['title'] as String}')
      .join('\n\n\n');

  await HomeWidget.saveWidgetData<String>('todo_count', todoCount);
  await HomeWidget.saveWidgetData<String>(
    'todo_items',
    snapshot.docs.isNotEmpty ? todoItems : null,
  );
  await HomeWidget.updateWidget(
    name: 'TodoWidgetProvider',
    iOSName: 'TodoWidgetProvider',
  );
}