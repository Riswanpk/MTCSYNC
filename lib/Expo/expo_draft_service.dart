import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Draft representation of an in-progress Expo Order stored in local cache.
class ExpoOrderDraft {
  final String id;
  final String exhibitionId;
  final String exhibitionName;
  final String orderType;
  final String phone;
  final String shopName;
  final String customerName;
  final String place;
  final String district;
  final String state;
  final String? preferredBranch;
  final String preferredSalesman;
  final DateTime? deliveryDate;
  final DateTime? stallPickupDate;
  final String advanceText;
  final String paymentMode;
  final String? paymentProofPath;
  final int currentStep;
  final List<Map<String, dynamic>> items;
  final DateTime updatedAt;

  ExpoOrderDraft({
    required this.id,
    required this.exhibitionId,
    required this.exhibitionName,
    required this.orderType,
    required this.phone,
    required this.shopName,
    required this.customerName,
    required this.place,
    required this.district,
    required this.state,
    this.preferredBranch,
    this.preferredSalesman = 'N/A',
    this.deliveryDate,
    this.stallPickupDate,
    this.advanceText = '0',
    this.paymentMode = 'Cash',
    this.paymentProofPath,
    this.currentStep = 0,
    required this.items,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'exhibitionId': exhibitionId,
      'exhibitionName': exhibitionName,
      'orderType': orderType,
      'phone': phone,
      'shopName': shopName,
      'customerName': customerName,
      'place': place,
      'district': district,
      'state': state,
      'preferredBranch': preferredBranch,
      'preferredSalesman': preferredSalesman,
      'deliveryDate': deliveryDate?.toIso8601String(),
      'stallPickupDate': stallPickupDate?.toIso8601String(),
      'advanceText': advanceText,
      'paymentMode': paymentMode,
      'paymentProofPath': paymentProofPath,
      'currentStep': currentStep,
      'items': items,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ExpoOrderDraft.fromMap(Map<String, dynamic> map) {
    return ExpoOrderDraft(
      id: map['id'] ?? '',
      exhibitionId: map['exhibitionId'] ?? '',
      exhibitionName: map['exhibitionName'] ?? '',
      orderType: map['orderType'] ?? 'Spot Delivery',
      phone: map['phone'] ?? '',
      shopName: map['shopName'] ?? '',
      customerName: map['customerName'] ?? '',
      place: map['place'] ?? '',
      district: map['district'] ?? '',
      state: map['state'] ?? 'Kerala',
      preferredBranch: map['preferredBranch'],
      preferredSalesman: map['preferredSalesman'] ?? 'N/A',
      deliveryDate: map['deliveryDate'] != null
          ? DateTime.tryParse(map['deliveryDate'])
          : null,
      stallPickupDate: map['stallPickupDate'] != null
          ? DateTime.tryParse(map['stallPickupDate'])
          : null,
      advanceText: map['advanceText'] ?? '0',
      paymentMode: map['paymentMode'] ?? 'Cash',
      paymentProofPath: map['paymentProofPath'],
      currentStep: (map['currentStep'] as num?)?.toInt() ?? 0,
      items: (map['items'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [],
      updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Service managing drafts stored locally in SharedPreferences.
class ExpoDraftService {
  ExpoDraftService._();
  static final ExpoDraftService instance = ExpoDraftService._();

  static const String _draftsKeyPrefix = 'expo_order_drafts_v1';

  Future<List<ExpoOrderDraft>> getDrafts({String? exhibitionId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftsKeyPrefix);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List;
      final drafts = list
          .whereType<Map>()
          .map((m) => ExpoOrderDraft.fromMap(Map<String, dynamic>.from(m)))
          .toList();

      drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (exhibitionId != null && exhibitionId.isNotEmpty) {
        return drafts.where((d) => d.exhibitionId == exhibitionId).toList();
      }
      return drafts;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDraft(ExpoOrderDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getDrafts();

    final idx = drafts.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      drafts[idx] = draft;
    } else {
      drafts.insert(0, draft);
    }

    final raw = jsonEncode(drafts.map((d) => d.toMap()).toList());
    await prefs.setString(_draftsKeyPrefix, raw);
  }

  Future<void> deleteDraft(String draftId) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getDrafts();
    drafts.removeWhere((d) => d.id == draftId);
    final raw = jsonEncode(drafts.map((d) => d.toMap()).toList());
    await prefs.setString(_draftsKeyPrefix, raw);
  }
}

