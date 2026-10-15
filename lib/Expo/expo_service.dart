import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../Misc/firebase_storage_helper.dart';
import '../Navigation/user_cache_service.dart';

/// Data model representing an Exhibition created by an Admin.
class Exhibition {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String location;
  final List<String> selectedUserIds;
  final List<Map<String, dynamic>> selectedUsers;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  const Exhibition({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.location,
    required this.selectedUserIds,
    required this.selectedUsers,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
  });

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startDate) && now.isBefore(endDate);
  }

  bool get isUpcoming {
    return DateTime.now().isBefore(startDate);
  }

  bool get isEnded {
    return DateTime.now().isAfter(endDate);
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'location': location,
      'selectedUserIds': selectedUserIds,
      'selectedUsers': selectedUsers,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'createdByName': createdByName,
    };
  }

  factory Exhibition.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseTimestamp(dynamic field) {
      if (field is Timestamp) return field.toDate();
      if (field is String) return DateTime.tryParse(field) ?? DateTime.now();
      return DateTime.now();
    }

    final rawUserIds = data['selectedUserIds'];
    final List<String> userIds = rawUserIds is List
        ? rawUserIds.map((e) => e.toString()).toList()
        : <String>[];

    final rawUsers = data['selectedUsers'];
    final List<Map<String, dynamic>> users = rawUsers is List
        ? rawUsers
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    return Exhibition(
      id: doc.id,
      name: data['name'] ?? '',
      startDate: parseTimestamp(data['startDate']),
      endDate: parseTimestamp(data['endDate']),
      location: data['location'] ?? '',
      selectedUserIds: userIds,
      selectedUsers: users,
      createdAt: parseTimestamp(data['createdAt']),
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
    );
  }
}

/// Item inside an Expo Order.
class ExpoOrderItem {
  final String mtcCode;
  final String itemName;
  final String description;
  final int qty;
  final double rate;
  final double gst; // percentage e.g. 18.0
  final double total; // (qty * rate) + ((qty * rate) * gst / 100)
  final String? photoUrl; // Optional photo of the item

  const ExpoOrderItem({
    required this.mtcCode,
    required this.itemName,
    required this.description,
    required this.qty,
    required this.rate,
    required this.gst,
    required this.total,
    this.photoUrl,
  });

  static double calculateTotal(int qty, double rate, double gst) {
    final base = qty * rate;
    final gstAmount = base * (gst / 100.0);
    return base + gstAmount;
  }

  Map<String, dynamic> toMap() {
    return {
      'mtcCode': mtcCode,
      'itemName': itemName,
      'description': description,
      'qty': qty,
      'rate': rate,
      'gst': gst,
      'total': total,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
    };
  }

  factory ExpoOrderItem.fromMap(Map<String, dynamic> map) {
    return ExpoOrderItem(
      mtcCode: map['mtcCode'] ?? '',
      itemName: map['itemName'] ?? '',
      description: map['description'] ?? '',
      qty: (map['qty'] as num?)?.toInt() ?? 0,
      rate: (map['rate'] as num?)?.toDouble() ?? 0.0,
      gst: (map['gst'] as num?)?.toDouble() ?? 0.0,
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      photoUrl: map['photoUrl'],
    );
  }
}

/// Full Expo Order submitted by a user.
class ExpoOrder {
  final String id;
  final String exhibitionId;
  final String exhibitionName;
  final String orderType; // 'Spot Delivery', 'Booking', 'Stall Delivery'
  final DateTime orderDate;
  final String shopName;
  final String customerName;
  final String place;
  final String district;
  final String state;
  final String phone;
  final String preferredBranch;
  final String preferredSalesman;
  final List<ExpoOrderItem> items;
  final double subtotal;
  final double totalGst;
  final double totalAmount;
  final int totalQty;
  final String status; // 'Pending', 'Completed'
  final String paymentMode; // 'Cash', 'Bank Transfer', 'UPI'
  final String? paymentProofUrl; // URL of receipt uploaded to Firebase Storage
  final String createdUserId;
  final String createdUserName;
  final String createdUserBranch;
  final DateTime createdAt;
  final DateTime? completedAt;

  const ExpoOrder({
    required this.id,
    required this.exhibitionId,
    required this.exhibitionName,
    required this.orderType,
    required this.orderDate,
    required this.shopName,
    required this.customerName,
    required this.place,
    required this.district,
    required this.state,
    required this.phone,
    required this.preferredBranch,
    required this.preferredSalesman,
    required this.items,
    required this.subtotal,
    required this.totalGst,
    required this.totalAmount,
    required this.totalQty,
    required this.status,
    this.paymentMode = 'Cash',
    this.paymentProofUrl,
    required this.createdUserId,
    required this.createdUserName,
    required this.createdUserBranch,
    required this.createdAt,
    this.completedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'exhibitionId': exhibitionId,
      'exhibitionName': exhibitionName,
      'orderType': orderType,
      'orderDate': Timestamp.fromDate(orderDate),
      'shopName': shopName,
      'customerName': customerName,
      'place': place,
      'district': district,
      'state': state,
      'phone': phone,
      'preferredBranch': preferredBranch,
      'preferredSalesman': preferredSalesman,
      'items': items.map((e) => e.toMap()).toList(),
      'subtotal': subtotal,
      'totalGst': totalGst,
      'totalAmount': totalAmount,
      'totalQty': totalQty,
      'status': status,
      'paymentMode': paymentMode,
      if (paymentProofUrl != null && paymentProofUrl!.isNotEmpty)
        'paymentProofUrl': paymentProofUrl,
      'createdUserId': createdUserId,
      'createdUserName': createdUserName,
      'createdUserBranch': createdUserBranch,
      'createdAt': Timestamp.fromDate(createdAt),
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    };
  }

  factory ExpoOrder.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseTimestamp(dynamic field) {
      if (field is Timestamp) return field.toDate();
      if (field is String) return DateTime.tryParse(field) ?? DateTime.now();
      return DateTime.now();
    }

    final rawItems = data['items'];
    final List<ExpoOrderItem> itemsList = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) => ExpoOrderItem.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <ExpoOrderItem>[];

    return ExpoOrder(
      id: doc.id,
      exhibitionId: data['exhibitionId'] ?? '',
      exhibitionName: data['exhibitionName'] ?? '',
      orderType: data['orderType'] ?? 'Spot Delivery',
      orderDate: parseTimestamp(data['orderDate']),
      shopName: data['shopName'] ?? '',
      customerName: data['customerName'] ?? '',
      place: data['place'] ?? '',
      district: data['district'] ?? '',
      state: data['state'] ?? '',
      phone: data['phone'] ?? '',
      preferredBranch: data['preferredBranch'] ?? '',
      preferredSalesman: data['preferredSalesman'] ?? 'N/A',
      items: itemsList,
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0.0,
      totalGst: (data['totalGst'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      totalQty: (data['totalQty'] as num?)?.toInt() ?? 0,
      status: data['status'] ?? 'Pending',
      paymentMode: data['paymentMode'] ?? 'Cash',
      paymentProofUrl: data['paymentProofUrl'],
      createdUserId: data['createdUserId'] ?? '',
      createdUserName: data['createdUserName'] ?? '',
      createdUserBranch: data['createdUserBranch'] ?? '',
      createdAt: parseTimestamp(data['createdAt']),
      completedAt: data['completedAt'] != null
          ? parseTimestamp(data['completedAt'])
          : null,
    );
  }
}

/// Service handling all Expo Firestore operations and caching.
class ExpoService {
  ExpoService._();
  static final ExpoService instance = ExpoService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _exhibitionsRef =>
      _firestore.collection('exhibitions');

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection('expo_orders');

  // --- Exhibitions Management ---

  Stream<List<Exhibition>> streamExhibitions() {
    return _exhibitionsRef
        .orderBy('startDate', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Exhibition.fromDoc(doc)).toList());
  }

  Stream<List<Exhibition>> streamExhibitionsForUser(String userId) {
    return _exhibitionsRef
        .where('selectedUserIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final list =
          snapshot.docs.map((doc) => Exhibition.fromDoc(doc)).toList();
      list.sort((a, b) => b.startDate.compareTo(a.startDate));
      return list;
    });
  }

  Future<void> saveExhibition({
    String? id,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required List<Map<String, dynamic>> selectedUsers,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final cache = UserCacheService.instance;
    await cache.ensureLoaded();

    final userIds = selectedUsers
        .map((u) => u['uid']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    final docData = {
      'name': name.trim(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'location': location.trim(),
      'selectedUserIds': userIds,
      'selectedUsers': selectedUsers,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (id == null || id.isEmpty) {
      docData['createdAt'] = FieldValue.serverTimestamp();
      docData['createdBy'] = user?.uid ?? '';
      docData['createdByName'] = cache.username ?? user?.displayName ?? 'Admin';
      await _exhibitionsRef.add(docData);
    } else {
      await _exhibitionsRef.doc(id).update(docData);
    }
  }

  Future<void> deleteExhibition(String exhibitionId) async {
    // Delete exhibition doc
    await _exhibitionsRef.doc(exhibitionId).delete();

    // Clean up corresponding orders in batch
    final ordersQuery =
        await _ordersRef.where('exhibitionId', isEqualTo: exhibitionId).get();
    final batch = _firestore.batch();
    for (final doc in ordersQuery.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // --- Orders Management ---

  Stream<List<ExpoOrder>> streamOrders({
    required String exhibitionId,
    String? status,
    String? userId,
  }) {
    Query<Map<String, dynamic>> query =
        _ordersRef.where('exhibitionId', isEqualTo: exhibitionId);

    if (status != null && status.isNotEmpty && status != 'All') {
      query = query.where('status', isEqualTo: status);
    }

    if (userId != null && userId.isNotEmpty) {
      query = query.where('createdUserId', isEqualTo: userId);
    }

    return query.snapshots().map((snapshot) {
      final orders =
          snapshot.docs.map((doc) => ExpoOrder.fromDoc(doc)).toList();
      orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
      return orders;
    });
  }

  Future<void> createOrder(ExpoOrder order) async {
    await _ordersRef.add(order.toMap());
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    final updateData = <String, dynamic>{
      'status': newStatus,
    };
    if (newStatus == 'Completed') {
      updateData['completedAt'] = FieldValue.serverTimestamp();
    } else {
      updateData['completedAt'] = null;
    }
    await _ordersRef.doc(orderId).update(updateData);
  }

  Future<void> deleteOrder(String orderId) async {
    await _ordersRef.doc(orderId).delete();
  }

  // --- Helpers for User Selection & Salesmen Filtering ---

  /// Retrieves all cached users grouped by branch.
  Future<Map<String, List<Map<String, dynamic>>>> getUsersByBranch({
    bool forceRefresh = false,
  }) async {
    final allUsers =
        await UserCacheService.instance.getAllUsers(forceRefresh: forceRefresh);
    final Map<String, List<Map<String, dynamic>>> branchMap = {};

    for (final user in allUsers) {
      final branch =
          (user['branch'] ?? 'Unknown').toString().trim().toUpperCase();
      if (branch.isEmpty) continue;
      branchMap.putIfAbsent(branch, () => []).add(user);
    }

    for (final list in branchMap.values) {
      list.sort((a, b) => (a['username'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['username'] ?? '').toString().toLowerCase()));
    }

    return branchMap;
  }

  /// Retrieves list of salesmen for a particular branch with 'N/A' as first choice.
  Future<List<String>> getSalesmenNamesForBranch(String branch) async {
    final allUsers = await UserCacheService.instance.getAllUsers();
    final normalizedBranch = branch.trim().toUpperCase();

    final branchSalesmen = allUsers.where((u) {
      final uBranch = (u['branch'] ?? '').toString().trim().toUpperCase();
      return uBranch == normalizedBranch;
    }).map((u) {
      final name = (u['username'] ?? '').toString().trim();
      return name.isNotEmpty ? name : (u['email'] ?? '').toString().trim();
    }).where((name) => name.isNotEmpty).toSet().toList();

    branchSalesmen.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['N/A', ...branchSalesmen];
  }

  /// Uploads a file (photo or proof) to Firebase Storage using storageCandidates.
  Future<String> uploadFile(File file, String folder) async {
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.split(Platform.pathSeparator).last}';
    Reference? ref;
    Object? lastError;

    for (final storage in FirebaseStorageHelper.storageCandidates()) {
      final candidateRef = storage.ref().child('expo').child(folder).child(fileName);
      try {
        await candidateRef.putFile(
          file,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        ref = candidateRef;
        break;
      } catch (e) {
        lastError = e;
        if (!FirebaseStorageHelper.isBucketNotFoundError(e)) {
          rethrow;
        }
      }
    }

    if (ref == null) {
      throw lastError ?? Exception('Failed to upload image to Firebase Storage');
    }

    return await ref.getDownloadURL();
  }

  /// Fetches Item Name and GST by MTC code from API (or Firestore fallback).
  /// Note: The user mentioned credentials will be provided later, so this
  /// method is prepared with an API stub/hook ready to connect.
  Future<Map<String, dynamic>?> fetchItemDetailsByMtcCode(String mtcCode) async {
    final cleanCode = mtcCode.trim();
    if (cleanCode.isEmpty) return null;

    try {
      // 1. Check if item exists in Firestore catalog/items if available
      final query = await _firestore
          .collection('items')
          .where('mtcCode', isEqualTo: cleanCode)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        return {
          'itemName': data['itemName'] ?? data['name'] ?? '',
          'gst': (data['gst'] as num?)?.toDouble() ?? 18.0,
          'rate': (data['rate'] as num?)?.toDouble(),
          'description': data['description'] ?? '',
        };
      }
    } catch (_) {
      // Ignore and proceed to API stub
    }

    // API integration hook: Credentials to be plugged in.
    return null;
  }
}
