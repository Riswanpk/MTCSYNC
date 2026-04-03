import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:home_widget/home_widget.dart';

Future<void> updateTodoWidgetFromFirestore() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // --- Todos ---
  final todoSnapshot = await FirebaseFirestore.instance
      .collection('todo')
      .where('email', isEqualTo: user.email)
      .where('status', isEqualTo: 'pending')
      .limit(20)
      .get();

  final todoCount = todoSnapshot.docs.isNotEmpty
      ? '${todoSnapshot.docs.length} tasks'
      : '0 tasks';

  final todoItems = todoSnapshot.docs
      .map((doc) => '${doc.id}|||${doc['title'] as String}')
      .join('\n\n\n');

  await HomeWidget.saveWidgetData<String>('todo_count', todoCount);
  await HomeWidget.saveWidgetData<String>(
    'todo_items',
    todoSnapshot.docs.isNotEmpty ? todoItems : null,
  );

  // --- Today's Leads ---
  final now = DateTime.now();
  final todayStr =
      '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';

  final leadsSnapshot = await FirebaseFirestore.instance
      .collection('follow_ups')
      .where('created_by', isEqualTo: user.uid)
      .limit(200)
      .get();

  final todayLeads = leadsSnapshot.docs.where((doc) {
    final data = doc.data();
    final reminder = data['reminder'] as String? ?? '';
    final status = data['status'] as String? ?? '';
    if (status == 'Sale' || status == 'Cancelled') return false;
    return reminder.startsWith(todayStr);
  }).toList();

  final leadsCount =
      todayLeads.isNotEmpty ? '${todayLeads.length} leads' : '0 leads';

  final leadsItems = todayLeads
      .map((doc) => '${doc.id}|||${doc.data()['name'] as String? ?? 'Unknown'}')
      .join('\n\n\n');

  await HomeWidget.saveWidgetData<String>('leads_today_count', leadsCount);
  await HomeWidget.saveWidgetData<String>(
    'leads_today_items',
    todayLeads.isNotEmpty ? leadsItems : null,
  );

  await HomeWidget.updateWidget(
    name: 'TodoWidgetProvider',
    iOSName: 'TodoWidgetProvider',
  );
}
