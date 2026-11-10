import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Navigation/user_cache_service.dart';
import 'expo_supabase_config.dart';

// ---------------------------------------------------------------------------
// Parsing helpers (Supabase / PostgREST returns ISO strings & JSON numbers)
// ---------------------------------------------------------------------------

DateTime _parseDate(dynamic field, {DateTime? fallback}) {
  if (field is DateTime) return field.toLocal();
  if (field is String) {
    final parsed = DateTime.tryParse(field);
    if (parsed != null) return parsed.isUtc ? parsed.toLocal() : parsed;
  }
  return fallback ?? DateTime.now();
}

DateTime? _parseNullableDate(dynamic field) {
  if (field == null) return null;
  return _parseDate(field);
}

double _toDouble(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
int _toInt(dynamic v) => (v as num?)?.toInt() ?? 0;

/// timestamptz columns: always send UTC ISO-8601.
String _ts(DateTime d) => d.toUtc().toIso8601String();

/// date columns: send yyyy-MM-dd (local calendar date).
String _dateOnly(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

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

  /// Row for the `expo.exhibitions` table.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'start_date': _ts(startDate),
      'end_date': _ts(endDate),
      'location': location,
      'selected_user_ids': selectedUserIds,
      'selected_users': selectedUsers,
      'created_at': _ts(createdAt),
      'created_by': createdBy,
      'created_by_name': createdByName,
    };
  }

  factory Exhibition.fromMap(Map<String, dynamic> data) {
    final rawUserIds = data['selected_user_ids'];
    final List<String> userIds = rawUserIds is List
        ? rawUserIds.map((e) => e.toString()).toList()
        : <String>[];

    final rawUsers = data['selected_users'];
    final List<Map<String, dynamic>> users = rawUsers is List
        ? rawUsers
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    return Exhibition(
      id: (data['id'] ?? '').toString(),
      name: data['name'] ?? '',
      startDate: _parseDate(data['start_date']),
      endDate: _parseDate(data['end_date']),
      location: data['location'] ?? '',
      selectedUserIds: userIds,
      selectedUsers: users,
      createdAt: _parseDate(data['created_at']),
      createdBy: data['created_by'] ?? '',
      createdByName: data['created_by_name'] ?? '',
    );
  }
}

/// Item inside an Expo Order (stored as JSONB array in `expo.orders.items`).
class ExpoOrderItem {
  final String mtcCode;
  final String itemName;
  final String description;
  final int qty;
  final double rate;
  final double gst; // percentage e.g. 18.0
  final double total; // (qty * rate) + ((qty * rate) * gst / 100)
  final String? photoUrl; // Photo of the item (not mandatory)

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
      qty: _toInt(map['qty']),
      rate: _toDouble(map['rate']),
      gst: _toDouble(map['gst']),
      total: _toDouble(map['total']),
      photoUrl: map['photoUrl'],
    );
  }
}

/// Full Expo Order submitted by a user.
class ExpoOrder {
  final String id;
  final int? billNumber; // Unique sequential bill number generated by Postgres sequence
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
  final double roundOff; // Round-off applied to reach a whole-rupee total
  final double totalAmount; // Final (rounded) amount payable
  final int totalQty;
  final double advanceAmount; // Advance paid (for booking / stall delivery)
  final double balanceAmount; // Remaining balance due
  final String status; // 'Pending Verification', 'Completed'
  final String paymentMode; // 'Cash', 'Bank Transfer', 'UPI'
  final String? paymentProofUrl; // Public URL of receipt in Supabase Storage
  final DateTime? deliveryDate; // Delivery date for booking orders
  final DateTime? stallPickupDate; // Expected pickup date during exhibition for Stall Delivery
  final bool isConvertedToBooking; // True if stall delivery wasn't picked up and got converted to booking
  final String? stallPickupStatus; // 'Pending Pickup', 'Picked Up', 'Converted to Booking'
  final String? claimedById; // User UID currently reviewing/verifying
  final String? claimedByName; // Name of reviewer
  final DateTime? claimedAt; // Timestamp when claim was made
  final String createdUserId;
  final String createdUserName;
  final String createdUserBranch;
  final DateTime createdAt;
  final DateTime? completedAt;

  const ExpoOrder({
    required this.id,
    this.billNumber,
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
    this.roundOff = 0.0,
    required this.totalAmount,
    required this.totalQty,
    this.advanceAmount = 0.0,
    this.balanceAmount = 0.0,
    required this.status,
    this.paymentMode = 'Cash',
    this.paymentProofUrl,
    this.deliveryDate,
    this.stallPickupDate,
    this.isConvertedToBooking = false,
    this.stallPickupStatus,
    this.claimedById,
    this.claimedByName,
    this.claimedAt,
    required this.createdUserId,
    required this.createdUserName,
    required this.createdUserBranch,
    required this.createdAt,
    this.completedAt,
  });

  /// Row for the `expo.orders` table (id / created_at are generated by DB).
  Map<String, dynamic> toMap() {
    return {
      'exhibition_id': exhibitionId,
      'exhibition_name': exhibitionName,
      'order_type': orderType,
      'order_date': _ts(orderDate),
      'shop_name': shopName,
      'customer_name': customerName,
      'place': place,
      'district': district,
      'state': state,
      'phone': phone,
      'preferred_branch': preferredBranch,
      'preferred_salesman': preferredSalesman,
      'items': items.map((e) => e.toMap()).toList(),
      'subtotal': subtotal,
      'total_gst': totalGst,
      'round_off': roundOff,
      'total_amount': totalAmount,
      'total_qty': totalQty,
      'advance_amount': advanceAmount,
      'balance_amount': balanceAmount,
      'status': status,
      'payment_mode': paymentMode,
      'payment_proof_url':
          (paymentProofUrl != null && paymentProofUrl!.isNotEmpty)
              ? paymentProofUrl
              : null,
      'delivery_date': deliveryDate != null ? _dateOnly(deliveryDate!) : null,
      'stall_pickup_date':
          stallPickupDate != null ? _dateOnly(stallPickupDate!) : null,
      'is_converted_to_booking': isConvertedToBooking,
      'stall_pickup_status':
          (stallPickupStatus != null && stallPickupStatus!.isNotEmpty)
              ? stallPickupStatus
              : null,
      'created_user_id': createdUserId,
      'created_user_name': createdUserName,
      'created_user_branch': createdUserBranch,
      'completed_at': completedAt != null ? _ts(completedAt!) : null,
    };
  }

  factory ExpoOrder.fromMap(Map<String, dynamic> data) {
    final rawItems = data['items'];
    final List<ExpoOrderItem> itemsList = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) => ExpoOrderItem.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <ExpoOrderItem>[];

    final totalAmount = _toDouble(data['total_amount']);
    final advance = _toDouble(data['advance_amount']);

    return ExpoOrder(
      id: (data['id'] ?? '').toString(),
      billNumber: (data['bill_number'] as num?)?.toInt(),
      exhibitionId: (data['exhibition_id'] ?? '').toString(),
      exhibitionName: data['exhibition_name'] ?? '',
      orderType: data['order_type'] ?? 'Spot Delivery',
      orderDate: _parseDate(data['order_date']),
      shopName: data['shop_name'] ?? '',
      customerName: data['customer_name'] ?? '',
      place: data['place'] ?? '',
      district: data['district'] ?? '',
      state: data['state'] ?? '',
      phone: data['phone'] ?? '',
      preferredBranch: data['preferred_branch'] ?? '',
      preferredSalesman: data['preferred_salesman'] ?? 'N/A',
      items: itemsList,
      subtotal: _toDouble(data['subtotal']),
      totalGst: _toDouble(data['total_gst']),
      roundOff: _toDouble(data['round_off']),
      totalAmount: totalAmount,
      totalQty: _toInt(data['total_qty']),
      advanceAmount: advance,
      balanceAmount: data['balance_amount'] != null
          ? _toDouble(data['balance_amount'])
          : (totalAmount - advance),
      status: data['status'] ?? 'Pending',
      paymentMode: data['payment_mode'] ?? 'Cash',
      paymentProofUrl: data['payment_proof_url'],
      deliveryDate: _parseNullableDate(data['delivery_date']),
      stallPickupDate: _parseNullableDate(data['stall_pickup_date']),
      isConvertedToBooking: data['is_converted_to_booking'] ?? false,
      stallPickupStatus: data['stall_pickup_status'],
      claimedById: data['claimed_by_id']?.toString(),
      claimedByName: data['claimed_by_name']?.toString(),
      claimedAt: _parseNullableDate(data['claimed_at']),
      createdUserId: data['created_user_id'] ?? '',
      createdUserName: data['created_user_name'] ?? '',
      createdUserBranch: data['created_user_branch'] ?? '',
      createdAt: _parseDate(data['created_at']),
      completedAt: _parseNullableDate(data['completed_at']),
    );
  }

  ExpoOrder copyWith({
    String? id,
    int? billNumber,
    String? exhibitionId,
    String? exhibitionName,
    String? orderType,
    DateTime? orderDate,
    String? shopName,
    String? customerName,
    String? place,
    String? district,
    String? state,
    String? phone,
    String? preferredBranch,
    String? preferredSalesman,
    List<ExpoOrderItem>? items,
    double? subtotal,
    double? totalGst,
    double? roundOff,
    double? totalAmount,
    int? totalQty,
    double? advanceAmount,
    double? balanceAmount,
    String? status,
    String? paymentMode,
    String? paymentProofUrl,
    DateTime? deliveryDate,
    DateTime? stallPickupDate,
    bool? isConvertedToBooking,
    String? stallPickupStatus,
    String? claimedById,
    String? claimedByName,
    DateTime? claimedAt,
    String? createdUserId,
    String? createdUserName,
    String? createdUserBranch,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return ExpoOrder(
      id: id ?? this.id,
      billNumber: billNumber ?? this.billNumber,
      exhibitionId: exhibitionId ?? this.exhibitionId,
      exhibitionName: exhibitionName ?? this.exhibitionName,
      orderType: orderType ?? this.orderType,
      orderDate: orderDate ?? this.orderDate,
      shopName: shopName ?? this.shopName,
      customerName: customerName ?? this.customerName,
      place: place ?? this.place,
      district: district ?? this.district,
      state: state ?? this.state,
      phone: phone ?? this.phone,
      preferredBranch: preferredBranch ?? this.preferredBranch,
      preferredSalesman: preferredSalesman ?? this.preferredSalesman,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      totalGst: totalGst ?? this.totalGst,
      roundOff: roundOff ?? this.roundOff,
      totalAmount: totalAmount ?? this.totalAmount,
      totalQty: totalQty ?? this.totalQty,
      advanceAmount: advanceAmount ?? this.advanceAmount,
      balanceAmount: balanceAmount ?? this.balanceAmount,
      status: status ?? this.status,
      paymentMode: paymentMode ?? this.paymentMode,
      paymentProofUrl: paymentProofUrl ?? this.paymentProofUrl,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      stallPickupDate: stallPickupDate ?? this.stallPickupDate,
      isConvertedToBooking: isConvertedToBooking ?? this.isConvertedToBooking,
      stallPickupStatus: stallPickupStatus ?? this.stallPickupStatus,
      claimedById: claimedById ?? this.claimedById,
      claimedByName: claimedByName ?? this.claimedByName,
      claimedAt: claimedAt ?? this.claimedAt,
      createdUserId: createdUserId ?? this.createdUserId,
      createdUserName: createdUserName ?? this.createdUserName,
      createdUserBranch: createdUserBranch ?? this.createdUserBranch,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// Service handling all Expo operations on the Supabase `expo` schema
/// (Postgres tables + Realtime + Storage).
///
/// Tables inside `expo` schema (see docs/expo_supabase_setup.md):
///   expo.exhibitions, expo.orders, expo.customers, expo.items
class ExpoService {
  ExpoService._();
  static final ExpoService instance = ExpoService._();

  static const String _exhibitionsTable = 'exhibitions';
  static const String _ordersTable = 'orders';
  static const String _customersTable = 'customers';
  static const String _itemsTable = 'items';

  SupabaseClient get _db => ExpoSupabaseConfig.client;

  PostgrestQueryBuilder _table(String tableName) =>
      _db.schema(ExpoSupabaseConfig.schema).from(tableName);

  // --- Exhibitions Management ---

  Stream<List<Exhibition>> streamExhibitions() {
    return _db
        .schema(ExpoSupabaseConfig.schema)
        .from(_exhibitionsTable)
        .stream(primaryKey: ['id'])
        .order('start_date', ascending: false)
        .map((rows) => rows.map(Exhibition.fromMap).toList());
  }

  Stream<List<Exhibition>> streamExhibitionsForUser(String userId) {
    // Realtime streams support a single eq-filter only, so array membership
    // is filtered client-side (exhibition count is tiny).
    return _db
        .schema(ExpoSupabaseConfig.schema)
        .from(_exhibitionsTable)
        .stream(primaryKey: ['id'])
        .map((rows) {
      final list = rows
          .map(Exhibition.fromMap)
          .where((e) => e.selectedUserIds.contains(userId))
          .toList();
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

    final row = <String, dynamic>{
      'name': name.trim(),
      'start_date': _ts(startDate),
      'end_date': _ts(endDate),
      'location': location.trim(),
      'selected_user_ids': userIds,
      'selected_users': selectedUsers,
    };

    if (id == null || id.isEmpty) {
      row['created_by'] = user?.uid ?? '';
      row['created_by_name'] =
          cache.username ?? user?.displayName ?? 'Admin';
      await _table(_exhibitionsTable).insert(row);
    } else {
      await _table(_exhibitionsTable).update(row).eq('id', id);
    }
  }

  Future<void> deleteExhibition(String exhibitionId) async {
    // Orders are removed automatically via ON DELETE CASCADE.
    await _table(_exhibitionsTable).delete().eq('id', exhibitionId);
  }

  // --- Orders Management ---

  Stream<List<ExpoOrder>> streamOrders({
    required String exhibitionId,
    String? status,
    String? userId,
  }) {
    final filterStatus =
        status != null && status.isNotEmpty && status != 'All';
    final filterUser = userId != null && userId.isNotEmpty;

    return _db
        .schema(ExpoSupabaseConfig.schema)
        .from(_ordersTable)
        .stream(primaryKey: ['id'])
        .eq('exhibition_id', exhibitionId)
        .map((rows) {
      final orders = rows
          .map(ExpoOrder.fromMap)
          .where((o) => !filterStatus || o.status == status)
          .where((o) => !filterUser || o.createdUserId == userId)
          .toList();
      orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
      return orders;
    });
  }

  /// Inserts the order. The DB trigger `expo_orders_upsert_customer`
  /// automatically upserts the customer into `expo.customers`.
  Future<void> createOrder(ExpoOrder order) async {
    await _table(_ordersTable).insert(order.toMap());
  }

  /// Searches customers of an exhibition by phone number (prefix match).
  /// Returns maps with camelCase keys used by the order form.
  Future<List<Map<String, dynamic>>> searchExpoCustomersByPhone({
    required String exhibitionName,
    required String phoneQuery,
    int limit = 8,
  }) async {
    final cleanQuery = phoneQuery.replaceAll(RegExp(r'\D'), '');
    final cleanExhibition = exhibitionName.trim();
    if (cleanQuery.length < 3 || cleanExhibition.isEmpty) return [];

    try {
      final rows = await _table(_customersTable)
          .select()
          .eq('exhibition_name', cleanExhibition)
          .like('phone', '$cleanQuery%')
          .order('last_updated', ascending: false)
          .limit(limit);

      return rows
          .map<Map<String, dynamic>>((r) => {
                'phone': r['phone'] ?? '',
                'shopName': r['shop_name'] ?? '',
                'customerName': r['customer_name'] ?? '',
                'place': r['place'] ?? '',
                'district': r['district'] ?? '',
                'state': r['state'] ?? '',
                'preferredBranch': r['preferred_branch'] ?? '',
                'preferredSalesman': r['preferred_salesman'] ?? '',
              })
          .toList();
    } catch (e) {
      debugPrint('Error searching expo customers: $e');
      return [];
    }
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    await _table(_ordersTable).update({
      'status': newStatus,
      'completed_at':
          newStatus == 'Completed' ? _ts(DateTime.now()) : null,
      'claimed_by_id': null,
      'claimed_by_name': null,
      'claimed_at': null,
    }).eq('id', orderId);
  }

  /// Bulk updates multiple orders to a new status (e.g. verifying selected cash orders).
  Future<void> updateMultipleOrdersStatus(List<String> orderIds, String newStatus) async {
    if (orderIds.isEmpty) return;
    await _table(_ordersTable).update({
      'status': newStatus,
      'completed_at':
          newStatus == 'Completed' ? _ts(DateTime.now()) : null,
      'claimed_by_id': null,
      'claimed_by_name': null,
      'claimed_at': null,
    }).filter('id', 'in', orderIds);
  }

  /// Attempts to atomically claim an order for verification queue so two
  /// accounts users do not review or modify the same order simultaneously.
  Future<Map<String, dynamic>> claimOrderForVerification({
    required String orderId,
    required String userId,
    required String userName,
    int timeoutMinutes = 5,
  }) async {
    try {
      final res = await _db.rpc(
        'claim_order_for_verification',
        params: {
          'p_order_id': orderId,
          'p_user_id': userId,
          'p_user_name': userName,
          'p_timeout_minutes': timeoutMinutes,
        },
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'success': true};
    } catch (e) {
      debugPrint('Error claiming order queue: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Releases the claim lock on an order so another accounts user can pick it up.
  Future<void> releaseOrderClaim({
    required String orderId,
    required String userId,
  }) async {
    try {
      await _db.rpc(
        'release_order_claim',
        params: {
          'p_order_id': orderId,
          'p_user_id': userId,
        },
      );
    } catch (e) {
      debugPrint('Error releasing order claim: $e');
    }
  }

  /// Marks a stall delivery order as picked up by the customer at the stall (Spot Delivery).
  Future<void> markStallDeliveryPickedUp(String orderId) async {
    await _table(_ordersTable).update({
      'status': 'Completed',
      'stall_pickup_status': 'Picked Up',
      'completed_at': _ts(DateTime.now()),
    }).eq('id', orderId);
  }

  Future<void> deleteOrder(String orderId) async {
    await _table(_ordersTable).delete().eq('id', orderId);
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

  /// Uploads a file (photo or proof) to the appropriate Supabase Storage bucket
  /// (`expo-item-photos`, `expo-upi-proofs`, or `expo-bank-proofs`) and
  /// returns its public URL.
  Future<String> uploadFile(File file, {required String bucketName}) async {
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.split(Platform.pathSeparator).last}';
    final bucket = _db.storage.from(bucketName);

    await bucket.upload(
      fileName,
      file,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
    );
    return bucket.getPublicUrl(fileName);
  }

  /// Fetches Item Name, GST, Rate & Description by MTC code from the
  /// `expo.items` catalog table.
  Future<Map<String, dynamic>?> fetchItemDetailsByMtcCode(String mtcCode) async {
    final cleanCode = mtcCode.trim();
    if (cleanCode.isEmpty) return null;

    try {
      final row = await _table(_itemsTable)
          .select()
          .eq('mtc_code', cleanCode)
          .maybeSingle();

      if (row != null) {
        return {
          'itemName': row['item_name'] ?? '',
          'gst': (row['gst'] as num?)?.toDouble() ?? 18.0,
          'rate': (row['rate'] as num?)?.toDouble(),
          'description': row['description'] ?? '',
        };
      }
    } catch (e) {
      debugPrint('Error fetching expo.items: $e');
    }

    // API integration hook: external item API can be plugged in here.
    return null;
  }
}
