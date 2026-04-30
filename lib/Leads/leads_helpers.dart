import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Returns the current 12 PM–12 PM IST window as [windowStart, windowEnd].
List<DateTime> getCurrentISTWindowLeads() {
  tz.initializeTimeZones();
  final ist = tz.getLocation('Asia/Kolkata');
  final nowIST = tz.TZDateTime.now(ist);
  DateTime windowStart, windowEnd;
  if (nowIST.hour >= 12) {
    windowStart = tz.TZDateTime(ist, nowIST.year, nowIST.month, nowIST.day, 12);
    final tomorrow = nowIST.add(const Duration(days: 1));
    windowEnd = tz.TZDateTime(ist, tomorrow.year, tomorrow.month, tomorrow.day, 12);
  } else {
    final yesterday = nowIST.subtract(const Duration(days: 1));
    windowStart = tz.TZDateTime(ist, yesterday.year, yesterday.month, yesterday.day, 12);
    windowEnd = tz.TZDateTime(ist, nowIST.year, nowIST.month, nowIST.day, 12);
  }
  return [windowStart, windowEnd];
}

/// Creates a daily_report document only if one doesn't already exist
/// for this user+type in the current 12 PM–12 PM IST window.
Future<void> createDailyReportIfNeededLeads({
  required String userId,
  required String documentId,
  required String type,
}) async {
  final window = getCurrentISTWindowLeads();
  final existing = await FirebaseFirestore.instance
      .collection('daily_report')
      .where('userId', isEqualTo: userId)
      .where('type', isEqualTo: type)
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(window[0]))
      .where('timestamp', isLessThan: Timestamp.fromDate(window[1]))
      .limit(1)
      .get();
  if (existing.docs.isEmpty) {
    await FirebaseFirestore.instance.collection('daily_report').add({
      'timestamp': FieldValue.serverTimestamp(),
      'userId': userId,
      'documentId': documentId,
      'type': type,
    });
  }
}

/// Search customers by name OR phone within a branch.
Future<List<Map<String, dynamic>>> fetchCustomerSuggestions(String query, String branch) async {
  final snap = await FirebaseFirestore.instance
      .collection('customer')
      .where('branch', isEqualTo: branch)
      .limit(100)
      .get();
  return snap.docs
      .map((doc) => doc.data())
      .where((data) =>
          (data['name'] ?? '').toString().toLowerCase().contains(query.toLowerCase()) ||
          (data['phone'] ?? '').toString().toLowerCase().contains(query.toLowerCase()))
      .toList();
}

/// Search customers by name across ALL branches from Supabase dme_customers table.
/// Returns list of matching customers.
Future<List<Map<String, dynamic>>> fetchCustomersByName(String query) async {
  try {
    if (query.isEmpty) return [];
    
    final client = Supabase.instance.client;
    final response = await client
        .from('dme_customers')
        .select('id, name, phone, address')
        .ilike('name', '%$query%');
    
    return (response as List).map((e) => {
      'id': e['id'],
      'name': e['name'] ?? '',
      'phone': e['phone'] ?? '',
      'address': e['address'] ?? '',
    }).toList();
  } catch (e) {
    print('Error fetching customers by name: $e');
    return [];
  }
}

/// Search customers by phone across ALL branches (for DME users).
/// Returns the first matching customer or null if not found.
Future<Map<String, dynamic>?> fetchCustomerByPhone(String phone) async {
  try {
    // Normalize phone: extract last 10 digits
    final digits = RegExp(r'\d').allMatches(phone).map((m) => m.group(0)).join();
    if (digits.length < 10) return null;
    
    final normalizedPhone = digits.substring(digits.length - 10);
    
    final snap = await FirebaseFirestore.instance
        .collection('customer')
        .limit(100)
        .get();
    
    // Search across all customers for phone match
    for (final doc in snap.docs) {
      final data = doc.data();
      final customerPhone = data['phone'] ?? '';
      // Extract last 10 digits from customer phone
      final customerDigits = RegExp(r'\d').allMatches(customerPhone).map((m) => m.group(0)).join();
      final customerNormalized = customerDigits.length >= 10 
          ? customerDigits.substring(customerDigits.length - 10)
          : customerDigits;
      
      if (customerNormalized == normalizedPhone) {
        return data;
      }
    }
    
    return null;
  } catch (e) {
    print('Error fetching customer by phone: $e');
    return null;
  }
}

/// Load contacts from SharedPreferences cache.
Future<List<Contact>> getCachedContacts() async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString('contacts_cache');
  if (cached != null) {
    final List<dynamic> decoded = jsonDecode(cached);
    return decoded.map((c) => Contact.fromJson(c)).toList();
  }
  return [];
}

/// Format a raw phone string into Indian format (+91 XXXXX XXXXX).
String formatIndianPhone(String raw) {
  final digits = RegExp(r'\d').allMatches(raw).map((m) => m.group(0)).join();
  if (digits.length >= 10) {
    final tenDigits = digits.substring(digits.length - 10);
    return '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
  }
  return '+91 ';
}
