import 'package:flutter/material.dart';

class TodoInstructionsPage extends StatelessWidget {
  const TodoInstructionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ToDo Instructions'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'ToDo Feature Guide',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),

          // Add Task
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Color(0xFF8CC63F)),
            title: const Text('Add Task'),
            subtitle: const Text(
              'Tap the "+" button to add a new task. Fill in the title, description, priority, and reminder date/time. Managers can assign tasks to sales users.',
            ),
          ),

          // Edit Task
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text('Edit Task'),
            subtitle: const Text(
              'Tap the edit icon on a task to update its details. Editing and saving a task will also record it as done for the daily report interval.',
            ),
          ),

          // Mark as Done
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text('Mark as Done'),
            subtitle: const Text(
              'Swipe right or tap "DONE" to mark a task as completed. Completed tasks move to the "Completed" tab.',
            ),
          ),

          // Delete Task
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete Task'),
            subtitle: const Text(
              'Swipe left and tap the delete icon to remove a task. You can also clear all tasks using the delete sweep icon in the app bar.',
            ),
          ),

          // Assignments (Manager)
          ListTile(
            leading: const Icon(Icons.group, color: Colors.deepPurple),
            title: const Text('Assignments (Manager Only)'),
            subtitle: const Text(
              'Managers can assign tasks to sales users in their branch. Assigned users receive notifications for new tasks.',
            ),
          ),

          // Tabs
          ListTile(
            leading: const Icon(Icons.tab, color: Colors.orange),
            title: const Text('Tabs'),
            subtitle: const Text(
              'Switch between "Pending", "Completed", and (for managers) "Others" to view your own and others\' tasks.',
            ),
          ),

          // Reminders & Notifications
          ListTile(
            leading: const Icon(Icons.alarm, color: Colors.teal),
            title: const Text('Reminders & Notifications'),
            subtitle: const Text(
              'Set a reminder for each task. You will receive a notification at the scheduled time.',
            ),
          ),

          // Daily Report Logic
          ListTile(
            leading: const Icon(Icons.analytics, color: Colors.indigo),
            title: const Text('Daily Report Logic'),
            subtitle: const Text(
              'Creating or editing a task between 12pm-11:59am (next day) records it as done for the daily report. Deleting a task also records it if within this interval.',
            ),
          ),

          // Drafts
          ListTile(
            leading: const Icon(Icons.drafts, color: Colors.brown),
            title: const Text('Drafts'),
            subtitle: const Text(
              'If you leave the form without saving, your input is saved as a draft. You can load the draft when you return.',
            ),
          ),

          // Others Tab (Manager)
          ListTile(
            leading: const Icon(Icons.people, color: Colors.purple),
            title: const Text('Others Tab (Manager Only)'),
            subtitle: const Text(
              'Managers can view and filter tasks assigned to other users in their branch.',
            ),
          ),

          

          const SizedBox(height: 24),
          const Text(
            'For more help, contact your administrator.',
            style: TextStyle(fontSize: 15, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}