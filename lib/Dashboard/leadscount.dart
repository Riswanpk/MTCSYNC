import 'package:cloud_firestore/cloud_firestore.dart';

class LeadCountService {
  static final _col = FirebaseFirestore.instance.collection('leadscount');

  // Increment total leads (global, not per branch)
  static Future<void> incrementLeadCount() async {
    final ref = _col.doc('all');
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?['totalLeads'] ?? 0) as int;
      tx.set(ref, {
        'totalLeads': current + 1,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  // Fetch total leads (global)
  static Future<int> getLeadCount() async {
    final snap = await _col.doc('all').get();
    return (snap.data()?['totalLeads'] ?? 0) as int;
  }
}