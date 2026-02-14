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
      .get();

  final todos = snapshot.docs.map((doc) => doc['title'] as String).toList();
  final todoText = todos.isNotEmpty ? todos.join('\n') : 'No todos';

  await HomeWidget.saveWidgetData<String>('todo_list', todoText);
  await HomeWidget.updateWidget(
    name: 'HomeWidgetProvider',
    iOSName: 'HomeWidgetProvider',
  );
}