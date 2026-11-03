import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const List<String> kSupersaleFallbackBranches = [
  'BGR', 'CBE', 'CHN', 'CLT', 'EKM', 'JBL', 'KKM', 'KSD',
  'KTM', 'PKD', 'PKT', 'PMN', 'TRR', 'TSR', 'TLY', 'TVM',
  'UDP', 'VDK', 'WND', 'PKTR', 'PLA', 'PMNA',
];

const List<String> kSupersaleTargetRoles = ['manager', 'asst_manager', 'sales'];

class SupersaleCampaignModel {
  final String id;
  final String item;
  final DateTime bookingStart;
  final DateTime bookingEnd;
  final DateTime deliveryStart;
  final DateTime deliveryEnd;
  final List<String> branches;
  final DateTime createdAt;

  const SupersaleCampaignModel({
    required this.id,
    required this.item,
    required this.bookingStart,
    required this.bookingEnd,
    required this.deliveryStart,
    required this.deliveryEnd,
    required this.branches,
    required this.createdAt,
  });

  bool get isAllBranches => branches.isEmpty || branches.contains('all');

  List<String> get effectiveBranches =>
      isAllBranches ? kSupersaleFallbackBranches : branches;

  bool appliesToBranch(String branch) =>
      isAllBranches || branches.contains(branch);

  String statusLabel(DateTime now) {
    if (now.isAfter(bookingStart) && now.isBefore(bookingEnd)) {
      return 'Booking Open';
    }
    if (now.isBefore(bookingStart)) {
      return 'Scheduled';
    }
    if (now.isBefore(deliveryEnd)) {
      return 'Delivery Active';
    }
    return 'Expired';
  }

  bool isExpired(DateTime now) => deliveryEnd.isBefore(now);
  bool isBookingOpen(DateTime now) =>
      now.isAfter(bookingStart) && now.isBefore(bookingEnd);
}

class SupersaleUserModel {
  final String uid;
  final String username;
  final String email;
  final String role;
  final String branch;

  const SupersaleUserModel({
    required this.uid,
    required this.username,
    required this.email,
    required this.role,
    required this.branch,
  });

  String get formattedRole {
    switch (role.toLowerCase()) {
      case 'manager':
        return 'Manager';
      case 'asst_manager':
        return 'Asst. Manager';
      case 'sales':
        return 'Sales';
      default:
        return role;
    }
  }
}

class SupersaleEntryModel {
  final String docId;
  final String adminPostingId;
  final String itemName;
  final String branch;
  final String customerName;
  final String phone;
  final String billedPhone;
  final String description;
  final double quantity;
  final double rate;
  final double advance;
  final String userId;
  final String username;
  final String email;
  final String status; // 'pending', 'delivered', 'cancelled'
  final String cancelReason;
  final bool isSpotSale;
  final bool isPartialSplit;
  final bool hasPartialDelivery;
  final String? parentBookingId;
  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final DateTime? deliveryReminder;
  final DateTime? bookingStart;
  final DateTime? bookingEnd;
  final DateTime? deliveryStart;
  final DateTime? deliveryEnd;

  const SupersaleEntryModel({
    required this.docId,
    required this.adminPostingId,
    required this.itemName,
    required this.branch,
    required this.customerName,
    required this.phone,
    required this.billedPhone,
    required this.description,
    required this.quantity,
    required this.rate,
    required this.advance,
    required this.userId,
    required this.username,
    required this.email,
    required this.status,
    required this.cancelReason,
    required this.isSpotSale,
    required this.isPartialSplit,
    required this.hasPartialDelivery,
    this.parentBookingId,
    this.createdAt,
    this.deliveredAt,
    this.deliveryReminder,
    this.bookingStart,
    this.bookingEnd,
    this.deliveryStart,
    this.deliveryEnd,
  });

  double get totalAmount => quantity * rate;
  double get balanceAmount => (totalAmount - advance).clamp(0.0, double.infinity);

  bool get isCancelled => status.toLowerCase() == 'cancelled';
  bool get isDelivered => status.toLowerCase() == 'delivered';
  bool get isPending => !isCancelled && !isDelivered;

  DateTime? get effectiveDeadline => deliveryReminder ?? deliveryEnd;

  bool isOverdue(DateTime now) {
    if (!isPending) return false;
    final deadline = effectiveDeadline;
    if (deadline == null) return false;
    return deadline.isBefore(now);
  }

  int daysOverdue(DateTime now) {
    final deadline = effectiveDeadline;
    if (deadline == null) return 0;
    return now.difference(deadline).inDays;
  }
}

class CampaignReportRow {
  final SupersaleCampaignModel campaign;
  int totalOrders = 0;
  int deliveredOrders = 0;
  int pendingOrders = 0;
  int cancelledOrders = 0;
  int spotSaleOrders = 0;
  int overdueOrders = 0;
  double bookedQty = 0;
  double deliveredQty = 0;
  double pendingQty = 0;
  double cancelledQty = 0;
  double spotSaleQty = 0;
  double totalAmount = 0;
  double deliveredAmount = 0;
  double totalAdvance = 0;
  final Set<String> activeBranches = {};
  final Set<String> participatingUsers = {};

  CampaignReportRow({required this.campaign});

  double get deliveryPct =>
      bookedQty > 0 ? (deliveredQty / bookedQty) * 100.0 : 0.0;
}

class BranchBookingReportRow {
  final String branch;
  int totalOrders = 0;
  int spotOrders = 0;
  int normalOrders = 0;
  double totalQty = 0;
  double spotQty = 0;
  double normalQty = 0;
  double totalAmount = 0;
  double totalAdvance = 0;

  BranchBookingReportRow({required this.branch});

  double get balanceAmount =>
      (totalAmount - totalAdvance).clamp(0.0, double.infinity);
  double get avgRate => totalQty > 0 ? totalAmount / totalQty : 0.0;
}

class BranchDeliveryReportRow {
  final String branch;
  int totalOrders = 0;
  int deliveredOrders = 0;
  int pendingOrders = 0;
  int cancelledOrders = 0;
  int overdueOrders = 0;
  double totalBookingQty = 0;
  double deliveredQty = 0;
  double pendingQty = 0;
  double cancelledQty = 0;
  double deliveredAmount = 0;
  double pendingAmount = 0;

  BranchDeliveryReportRow({required this.branch});

  double get deliveryPct =>
      totalBookingQty > 0 ? (deliveredQty / totalBookingQty) * 100.0 : 0.0;
}

class UserPerformanceReportRow {
  final String uid;
  final String username;
  final String branch;
  final String role;
  int applicableCampaigns = 0;
  int participatedCampaigns = 0;
  int completedCampaigns = 0;
  int totalOrders = 0;
  int deliveredOrders = 0;
  int pendingOrders = 0;
  int cancelledOrders = 0;
  int spotSaleOrders = 0;
  int overdueOrders = 0;
  double bookedQty = 0;
  double deliveredQty = 0;
  double pendingQty = 0;
  double totalAmount = 0;
  double totalAdvance = 0;

  UserPerformanceReportRow({
    required this.uid,
    required this.username,
    required this.branch,
    required this.role,
  });

  double get deliveryPct =>
      bookedQty > 0 ? (deliveredQty / bookedQty) * 100.0 : 0.0;

  double get campaignParticipationPct => applicableCampaigns > 0
      ? (participatedCampaigns / applicableCampaigns) * 100.0
      : 0.0;

  String get formattedRole {
    switch (role.toLowerCase()) {
      case 'manager':
        return 'Manager';
      case 'asst_manager':
        return 'Asst. Manager';
      case 'sales':
        return 'Sales';
      default:
        return role;
    }
  }
}

class NonParticipantRow {
  final String uid;
  final String username;
  final String branch;
  final String role;
  final String campaignItem;
  final DateTime deliveryEnd;

  const NonParticipantRow({
    required this.uid,
    required this.username,
    required this.branch,
    required this.role,
    required this.campaignItem,
    required this.deliveryEnd,
  });

  String get formattedRole {
    switch (role.toLowerCase()) {
      case 'manager':
        return 'Manager';
      case 'asst_manager':
        return 'Asst. Manager';
      case 'sales':
        return 'Sales';
      default:
        return role;
    }
  }
}

class SupersaleDashboardBundle {
  final List<SupersaleCampaignModel> allCampaigns;
  final List<SupersaleUserModel> allUsers;
  final List<SupersaleEntryModel> allEntries;
  final List<String> allBranches;

  const SupersaleDashboardBundle({
    required this.allCampaigns,
    required this.allUsers,
    required this.allEntries,
    required this.allBranches,
  });

  SupersaleDashboardBundle copyWith({
    List<SupersaleCampaignModel>? allCampaigns,
    List<SupersaleUserModel>? allUsers,
    List<SupersaleEntryModel>? allEntries,
    List<String>? allBranches,
  }) {
    return SupersaleDashboardBundle(
      allCampaigns: allCampaigns ?? this.allCampaigns,
      allUsers: allUsers ?? this.allUsers,
      allEntries: allEntries ?? this.allEntries,
      allBranches: allBranches ?? this.allBranches,
    );
  }
}

class SupersaleComputedAnalytics {
  // KPIs
  final int totalCampaigns;
  final int activeBookingCampaigns;
  final int activeDeliveryCampaigns;
  final int expiredCampaigns;

  final int totalValidOrders;
  final int deliveredOrders;
  final int pendingOrders;
  final int cancelledOrders;
  final int overdueOrders;
  final int spotSaleOrders;
  final int normalBookingOrders;
  final int partialSplitOrders;

  final double totalBookedQty;
  final double deliveredQty;
  final double pendingQty;
  final double cancelledQty;
  final double spotSaleQty;
  final double normalBookingQty;

  final double totalOrderAmount;
  final double deliveredAmount;
  final double pendingAmount;
  final double cancelledAmount;
  final double totalAdvanceAmount;
  final double spotSaleAmount;
  final double normalBookingAmount;

  // Report tables
  final List<CampaignReportRow> campaignRows;
  final List<BranchBookingReportRow> branchBookingRows;
  final List<BranchDeliveryReportRow> branchDeliveryRows;
  final List<UserPerformanceReportRow> userPerformanceRows;
  final List<NonParticipantRow> nonParticipantRows;
  final List<SupersaleEntryModel> overdueEntries;
  final List<SupersaleEntryModel> pendingEntries;
  final List<SupersaleEntryModel> cancelledEntries;
  final List<SupersaleEntryModel> splitEntries;
  final List<SupersaleEntryModel> filteredEntries;

  const SupersaleComputedAnalytics({
    required this.totalCampaigns,
    required this.activeBookingCampaigns,
    required this.activeDeliveryCampaigns,
    required this.expiredCampaigns,
    required this.totalValidOrders,
    required this.deliveredOrders,
    required this.pendingOrders,
    required this.cancelledOrders,
    required this.overdueOrders,
    required this.spotSaleOrders,
    required this.normalBookingOrders,
    required this.partialSplitOrders,
    required this.totalBookedQty,
    required this.deliveredQty,
    required this.pendingQty,
    required this.cancelledQty,
    required this.spotSaleQty,
    required this.normalBookingQty,
    required this.totalOrderAmount,
    required this.deliveredAmount,
    required this.pendingAmount,
    required this.cancelledAmount,
    required this.totalAdvanceAmount,
    required this.spotSaleAmount,
    required this.normalBookingAmount,
    required this.campaignRows,
    required this.branchBookingRows,
    required this.branchDeliveryRows,
    required this.userPerformanceRows,
    required this.nonParticipantRows,
    required this.overdueEntries,
    required this.pendingEntries,
    required this.cancelledEntries,
    required this.splitEntries,
    required this.filteredEntries,
  });

  double get deliveryFulfillmentPct =>
      totalBookedQty > 0 ? (deliveredQty / totalBookedQty) * 100.0 : 0.0;

  double get spotSaleQtySharePct =>
      totalBookedQty > 0 ? (spotSaleQty / totalBookedQty) * 100.0 : 0.0;
}

class SupersaleDashboardService {
  static DateTime _parseDate(dynamic raw, [DateTime? fallback]) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) {
      return DateTime.tryParse(raw) ?? (fallback ?? DateTime.now());
    }
    return fallback ?? DateTime.now();
  }

  static DateTime? _parseNullableDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static Future<SupersaleDashboardBundle> fetchMetadata() async {
    final firestore = FirebaseFirestore.instance;

    final results = await Future.wait([
      firestore
          .collection('supersales')
          .orderBy('created_at', descending: true)
          .get(),
      firestore.collection('users').get(),
    ]);

    final supersalesSnap = results[0];
    final usersSnap = results[1];

    final List<SupersaleCampaignModel> campaigns = [];
    for (final doc in supersalesSnap.docs) {
      final data = doc.data();
      final List<dynamic> rawBranches = data['branches'] ?? [];
      campaigns.add(
        SupersaleCampaignModel(
          id: doc.id,
          item: (data['item'] ?? 'Unnamed').toString().trim(),
          bookingStart: _parseDate(data['bookingStart']),
          bookingEnd: _parseDate(data['bookingEnd']),
          deliveryStart: _parseDate(data['deliveryStart']),
          deliveryEnd: _parseDate(data['deliveryEnd']),
          branches: rawBranches.map((e) => e.toString()).toList(),
          createdAt: _parseDate(data['created_at']),
        ),
      );
    }

    final List<SupersaleUserModel> users = [];
    final Set<String> branchSet = {...kSupersaleFallbackBranches};

    for (final doc in usersSnap.docs) {
      final data = doc.data();
      final role = (data['role'] ?? '').toString().toLowerCase().trim();
      if (!kSupersaleTargetRoles.contains(role)) continue;
      final branch = (data['branch'] ?? '').toString().trim();
      if (branch.isEmpty || branch.toLowerCase() == 'admin') continue;

      branchSet.add(branch);
      users.add(
        SupersaleUserModel(
          uid: doc.id,
          username: (data['username']?.toString().trim().isNotEmpty == true)
              ? data['username'].toString().trim()
              : (data['email']?.toString().trim() ?? 'Unknown'),
          email: (data['email'] ?? '').toString().trim(),
          role: role,
          branch: branch,
        ),
      );
    }

    final sortedBranches = branchSet.toList()..sort();

    return SupersaleDashboardBundle(
      allCampaigns: campaigns,
      allUsers: users,
      allEntries: const [],
      allBranches: sortedBranches,
    );
  }

  static Future<List<SupersaleEntryModel>> fetchEntriesForSelection({
    required List<SupersaleCampaignModel> campaigns,
    required List<String> branches,
    String? selectedCampaignId,
    String? selectedBranch,
  }) async {
    final firestore = FirebaseFirestore.instance;

    final targetCampaigns = (selectedCampaignId != null && selectedCampaignId.isNotEmpty)
        ? campaigns.where((c) => c.id == selectedCampaignId).toList()
        : campaigns;

    final Set<String> targetItemNames =
        targetCampaigns.map((c) => c.item).where((i) => i.isNotEmpty).toSet();

    final List<Future<List<SupersaleEntryModel>>> queryFutures = [];

    for (final itemName in targetItemNames) {
      final Set<String> itemBranches = {};
      for (final c in targetCampaigns.where((c) => c.item == itemName)) {
        if (c.isAllBranches) {
          itemBranches.addAll(branches);
        } else {
          itemBranches.addAll(c.branches);
        }
      }

      final branchesToQuery = (selectedBranch != null && selectedBranch.isNotEmpty)
          ? itemBranches.where((b) => b == selectedBranch).toList()
          : itemBranches.toList();

      for (final branch in branchesToQuery) {
        queryFutures.add(
          firestore
              .collection('supersale_user_entries')
              .doc(branch)
              .collection(itemName)
              .get()
              .then((snap) {
            return snap.docs.map((doc) {
              final d = doc.data();
              final bool isSpot =
                  d['isSpotSale'] == true || d['saleType'] == 'spot_sale';
              return SupersaleEntryModel(
                docId: doc.id,
                adminPostingId: (d['adminPostingId'] ?? '').toString(),
                itemName: itemName,
                branch: branch,
                customerName: (d['customerName'] ?? '').toString().trim(),
                phone: (d['phone'] ?? '').toString().trim(),
                billedPhone: (d['billedPhone'] ?? '').toString().trim(),
                description: (d['description'] ?? '').toString().trim(),
                quantity: (d['quantity'] is num)
                    ? (d['quantity'] as num).toDouble()
                    : (double.tryParse(d['quantity']?.toString() ?? '0') ??
                        0.0),
                rate: (d['rate'] is num)
                    ? (d['rate'] as num).toDouble()
                    : (double.tryParse(d['rate']?.toString() ?? '0') ?? 0.0),
                advance: (d['advance'] is num)
                    ? (d['advance'] as num).toDouble()
                    : (double.tryParse(d['advance']?.toString() ?? '0') ?? 0.0),
                userId: (d['userId'] ?? '').toString(),
                username: (d['username']?.toString().trim().isNotEmpty == true)
                    ? d['username'].toString().trim()
                    : (d['email']?.toString().trim() ?? 'Unknown'),
                email: (d['email'] ?? '').toString().trim(),
                status: (d['status'] ?? 'pending').toString().toLowerCase(),
                cancelReason: (d['cancelReason'] ?? '').toString().trim(),
                isSpotSale: isSpot,
                isPartialSplit: d['isPartialSplit'] == true,
                hasPartialDelivery: d['hasPartialDelivery'] == true,
                parentBookingId: d['parentBookingId']?.toString(),
                createdAt: _parseNullableDate(d['created_at']),
                deliveredAt: _parseNullableDate(d['deliveredAt']),
                deliveryReminder: _parseNullableDate(d['deliveryReminder']),
                bookingStart: _parseNullableDate(d['bookingStart']),
                bookingEnd: _parseNullableDate(d['bookingEnd']),
                deliveryStart: _parseNullableDate(d['deliveryStart']),
                deliveryEnd: _parseNullableDate(d['deliveryEnd']),
              );
            }).toList();
          }).catchError((_) => <SupersaleEntryModel>[]),
        );
      }
    }

    final nestedEntries = await Future.wait(queryFutures);
    final List<SupersaleEntryModel> entries =
        nestedEntries.expand((e) => e).toList();

    entries.sort((a, b) {
      final aTime = a.createdAt ?? DateTime(2000);
      final bTime = b.createdAt ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return entries;
  }

  static Future<SupersaleDashboardBundle> fetchAllData() async {
    final firestore = FirebaseFirestore.instance;

    // 1. Fetch campaigns & users in parallel
    final results = await Future.wait([
      firestore
          .collection('supersales')
          .orderBy('created_at', descending: true)
          .get(),
      firestore.collection('users').get(),
    ]);

    final supersalesSnap = results[0];
    final usersSnap = results[1];

    final List<SupersaleCampaignModel> campaigns = [];
    for (final doc in supersalesSnap.docs) {
      final data = doc.data();
      final List<dynamic> rawBranches = data['branches'] ?? [];
      campaigns.add(
        SupersaleCampaignModel(
          id: doc.id,
          item: (data['item'] ?? 'Unnamed').toString().trim(),
          bookingStart: _parseDate(data['bookingStart']),
          bookingEnd: _parseDate(data['bookingEnd']),
          deliveryStart: _parseDate(data['deliveryStart']),
          deliveryEnd: _parseDate(data['deliveryEnd']),
          branches: rawBranches.map((e) => e.toString()).toList(),
          createdAt: _parseDate(data['created_at']),
        ),
      );
    }

    final List<SupersaleUserModel> users = [];
    final Set<String> branchSet = {...kSupersaleFallbackBranches};

    for (final doc in usersSnap.docs) {
      final data = doc.data();
      final role = (data['role'] ?? '').toString().toLowerCase().trim();
      if (!kSupersaleTargetRoles.contains(role)) continue;
      final branch = (data['branch'] ?? '').toString().trim();
      if (branch.isEmpty || branch.toLowerCase() == 'admin') continue;

      branchSet.add(branch);
      users.add(
        SupersaleUserModel(
          uid: doc.id,
          username: (data['username']?.toString().trim().isNotEmpty == true)
              ? data['username'].toString().trim()
              : (data['email']?.toString().trim() ?? 'Unknown'),
          email: (data['email'] ?? '').toString().trim(),
          role: role,
          branch: branch,
        ),
      );
    }

    final sortedBranches = branchSet.toList()..sort();

    // 2. Fetch all entries across unique (branch, itemName) pairs in parallel
    final Set<String> uniqueItems =
        campaigns.map((c) => c.item).where((i) => i.isNotEmpty).toSet();

    final List<Future<List<SupersaleEntryModel>>> queryFutures = [];

    for (final itemName in uniqueItems) {
      // Determine all branches that ever had this item
      final Set<String> itemBranches = {};
      for (final c in campaigns.where((c) => c.item == itemName)) {
        if (c.isAllBranches) {
          itemBranches.addAll(sortedBranches);
        } else {
          itemBranches.addAll(c.branches);
        }
      }

      for (final branch in itemBranches) {
        queryFutures.add(
          firestore
              .collection('supersale_user_entries')
              .doc(branch)
              .collection(itemName)
              .get()
              .then((snap) {
            return snap.docs.map((doc) {
              final d = doc.data();
              final bool isSpot =
                  d['isSpotSale'] == true || d['saleType'] == 'spot_sale';
              return SupersaleEntryModel(
                docId: doc.id,
                adminPostingId: (d['adminPostingId'] ?? '').toString(),
                itemName: itemName,
                branch: branch,
                customerName: (d['customerName'] ?? '').toString().trim(),
                phone: (d['phone'] ?? '').toString().trim(),
                billedPhone: (d['billedPhone'] ?? '').toString().trim(),
                description: (d['description'] ?? '').toString().trim(),
                quantity: (d['quantity'] is num)
                    ? (d['quantity'] as num).toDouble()
                    : (double.tryParse(d['quantity']?.toString() ?? '0') ??
                        0.0),
                rate: (d['rate'] is num)
                    ? (d['rate'] as num).toDouble()
                    : (double.tryParse(d['rate']?.toString() ?? '0') ?? 0.0),
                advance: (d['advance'] is num)
                    ? (d['advance'] as num).toDouble()
                    : (double.tryParse(d['advance']?.toString() ?? '0') ?? 0.0),
                userId: (d['userId'] ?? '').toString(),
                username: (d['username']?.toString().trim().isNotEmpty == true)
                    ? d['username'].toString().trim()
                    : (d['email']?.toString().trim() ?? 'Unknown'),
                email: (d['email'] ?? '').toString().trim(),
                status: (d['status'] ?? 'pending').toString().toLowerCase(),
                cancelReason: (d['cancelReason'] ?? '').toString().trim(),
                isSpotSale: isSpot,
                isPartialSplit: d['isPartialSplit'] == true,
                hasPartialDelivery: d['hasPartialDelivery'] == true,
                parentBookingId: d['parentBookingId']?.toString(),
                createdAt: _parseNullableDate(d['created_at']),
                deliveredAt: _parseNullableDate(d['deliveredAt']),
                deliveryReminder: _parseNullableDate(d['deliveryReminder']),
                bookingStart: _parseNullableDate(d['bookingStart']),
                bookingEnd: _parseNullableDate(d['bookingEnd']),
                deliveryStart: _parseNullableDate(d['deliveryStart']),
                deliveryEnd: _parseNullableDate(d['deliveryEnd']),
              );
            }).toList();
          }).catchError((_) => <SupersaleEntryModel>[]),
        );
      }
    }

    final nestedEntries = await Future.wait(queryFutures);
    final List<SupersaleEntryModel> allEntries =
        nestedEntries.expand((e) => e).toList();

    // Sort newest first
    allEntries.sort((a, b) {
      final aTime = a.createdAt ?? DateTime(2000);
      final bTime = b.createdAt ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return SupersaleDashboardBundle(
      allCampaigns: campaigns,
      allUsers: users,
      allEntries: allEntries,
      allBranches: sortedBranches,
    );
  }

  static SupersaleComputedAnalytics computeAnalytics({
    required SupersaleDashboardBundle bundle,
    String? selectedCampaignId,
    String? selectedBranch,
    DateTimeRange? dateRange,
  }) {
    final now = DateTime.now();

    // Filter campaigns
    final List<SupersaleCampaignModel> filteredCampaigns =
        bundle.allCampaigns.where((c) {
      if (selectedCampaignId != null &&
          selectedCampaignId.isNotEmpty &&
          c.id != selectedCampaignId) {
        return false;
      }
      if (selectedBranch != null &&
          selectedBranch.isNotEmpty &&
          !c.appliesToBranch(selectedBranch)) {
        return false;
      }
      return true;
    }).toList();

    final Map<String, SupersaleCampaignModel> campaignById = {
      for (final c in bundle.allCampaigns) c.id: c,
    };

    // Filter entries
    final List<SupersaleEntryModel> filteredEntries =
        bundle.allEntries.where((e) {
      if (selectedCampaignId != null && selectedCampaignId.isNotEmpty) {
        final selectedCampaign = campaignById[selectedCampaignId];
        if (e.adminPostingId.isNotEmpty) {
          if (e.adminPostingId != selectedCampaignId) return false;
        } else if (selectedCampaign != null &&
            e.itemName != selectedCampaign.item) {
          return false;
        }
      }
      if (selectedBranch != null &&
          selectedBranch.isNotEmpty &&
          e.branch != selectedBranch) {
        return false;
      }
      if (dateRange != null) {
        final dt = e.createdAt ?? e.bookingStart;
        if (dt == null) return false;
        final start = DateTime(
          dateRange.start.year,
          dateRange.start.month,
          dateRange.start.day,
        );
        final end = DateTime(
          dateRange.end.year,
          dateRange.end.month,
          dateRange.end.day,
          23,
          59,
          59,
        );
        if (dt.isBefore(start) || dt.isAfter(end)) return false;
      }
      return true;
    }).toList();

    // Campaign status counts
    int activeBookingCampaigns = 0;
    int activeDeliveryCampaigns = 0;
    int expiredCampaigns = 0;

    for (final c in filteredCampaigns) {
      if (c.isBookingOpen(now)) {
        activeBookingCampaigns++;
      } else if (!c.isExpired(now)) {
        activeDeliveryCampaigns++;
      } else {
        expiredCampaigns++;
      }
    }

    // Overall KPIs
    int totalValidOrders = 0;
    int deliveredOrders = 0;
    int pendingOrders = 0;
    int cancelledOrders = 0;
    int overdueOrders = 0;
    int spotSaleOrders = 0;
    int normalBookingOrders = 0;
    int partialSplitOrders = 0;

    double totalBookedQty = 0;
    double deliveredQty = 0;
    double pendingQty = 0;
    double cancelledQty = 0;
    double spotSaleQty = 0;
    double normalBookingQty = 0;

    double totalOrderAmount = 0;
    double deliveredAmount = 0;
    double pendingAmount = 0;
    double cancelledAmount = 0;
    double totalAdvanceAmount = 0;
    double spotSaleAmount = 0;
    double normalBookingAmount = 0;

    final Map<String, CampaignReportRow> campaignRowMap = {
      for (final c in filteredCampaigns) c.id: CampaignReportRow(campaign: c),
    };

    final Map<String, BranchBookingReportRow> branchBookingMap = {};
    final Map<String, BranchDeliveryReportRow> branchDeliveryMap = {};

    final List<SupersaleEntryModel> overdueList = [];
    final List<SupersaleEntryModel> pendingList = [];
    final List<SupersaleEntryModel> cancelledList = [];
    final List<SupersaleEntryModel> splitList = [];

    for (final entry in filteredEntries) {
      if (entry.isPartialSplit || entry.hasPartialDelivery) {
        partialSplitOrders++;
        splitList.add(entry);
      }

      // Resolve campaign row
      CampaignReportRow? cRow;
      if (entry.adminPostingId.isNotEmpty &&
          campaignRowMap.containsKey(entry.adminPostingId)) {
        cRow = campaignRowMap[entry.adminPostingId];
      } else {
        for (final r in campaignRowMap.values) {
          if (r.campaign.item == entry.itemName) {
            cRow = r;
            break;
          }
        }
      }

      final bDelivery = branchDeliveryMap.putIfAbsent(
        entry.branch,
        () => BranchDeliveryReportRow(branch: entry.branch),
      );

      if (entry.isCancelled) {
        cancelledOrders++;
        cancelledQty += entry.quantity;
        cancelledAmount += entry.totalAmount;
        cancelledList.add(entry);

        cRow?.cancelledOrders++;
        if (cRow != null) cRow.cancelledQty += entry.quantity;

        bDelivery.cancelledOrders++;
        bDelivery.cancelledQty += entry.quantity;
        continue;
      }

      // Valid non-cancelled order
      totalValidOrders++;
      totalBookedQty += entry.quantity;
      totalOrderAmount += entry.totalAmount;
      totalAdvanceAmount += entry.advance;

      if (entry.isSpotSale) {
        spotSaleOrders++;
        spotSaleQty += entry.quantity;
        spotSaleAmount += entry.totalAmount;
      } else {
        normalBookingOrders++;
        normalBookingQty += entry.quantity;
        normalBookingAmount += entry.totalAmount;
      }

      final bBooking = branchBookingMap.putIfAbsent(
        entry.branch,
        () => BranchBookingReportRow(branch: entry.branch),
      );
      bBooking.totalOrders++;
      bBooking.totalQty += entry.quantity;
      bBooking.totalAmount += entry.totalAmount;
      bBooking.totalAdvance += entry.advance;
      if (entry.isSpotSale) {
        bBooking.spotOrders++;
        bBooking.spotQty += entry.quantity;
      } else {
        bBooking.normalOrders++;
        bBooking.normalQty += entry.quantity;
      }

      bDelivery.totalOrders++;
      bDelivery.totalBookingQty += entry.quantity;

      if (cRow != null) {
        cRow.totalOrders++;
        cRow.bookedQty += entry.quantity;
        cRow.totalAmount += entry.totalAmount;
        cRow.totalAdvance += entry.advance;
        cRow.activeBranches.add(entry.branch);
        if (entry.userId.isNotEmpty) {
          cRow.participatingUsers.add(entry.userId);
        }
        if (entry.isSpotSale) {
          cRow.spotSaleOrders++;
          cRow.spotSaleQty += entry.quantity;
        }
      }

      if (entry.isDelivered) {
        deliveredOrders++;
        deliveredQty += entry.quantity;
        deliveredAmount += entry.totalAmount;

        bDelivery.deliveredOrders++;
        bDelivery.deliveredQty += entry.quantity;
        bDelivery.deliveredAmount += entry.totalAmount;

        if (cRow != null) {
          cRow.deliveredOrders++;
          cRow.deliveredQty += entry.quantity;
          cRow.deliveredAmount += entry.totalAmount;
        }
      } else {
        pendingOrders++;
        pendingQty += entry.quantity;
        pendingAmount += entry.totalAmount;
        pendingList.add(entry);

        bDelivery.pendingOrders++;
        bDelivery.pendingQty += entry.quantity;
        bDelivery.pendingAmount += entry.totalAmount;

        if (cRow != null) {
          cRow.pendingOrders++;
          cRow.pendingQty += entry.quantity;
        }

        if (entry.isOverdue(now)) {
          overdueOrders++;
          overdueList.add(entry);
          bDelivery.overdueOrders++;
          if (cRow != null) {
            cRow.overdueOrders++;
          }
        }
      }
    }

    // Sort campaign rows
    final List<CampaignReportRow> campaignRows = campaignRowMap.values.toList()
      ..sort((a, b) => b.bookedQty.compareTo(a.bookedQty));

    // Sort branch booking rows by qty descending
    final List<BranchBookingReportRow> branchBookingRows =
        branchBookingMap.values.toList()
          ..sort((a, b) => b.totalQty.compareTo(a.totalQty));

    // Sort branch delivery rows by pendingQty descending, then totalBookingQty
    final List<BranchDeliveryReportRow> branchDeliveryRows =
        branchDeliveryMap.values.toList()
          ..sort((a, b) {
            final cmp = b.pendingQty.compareTo(a.pendingQty);
            if (cmp != 0) return cmp;
            return b.totalBookingQty.compareTo(a.totalBookingQty);
          });

    // Sort overdue entries by daysOverdue descending
    overdueList.sort((a, b) => b.daysOverdue(now).compareTo(a.daysOverdue(now)));

    // User Performance & Non-Participant Calculation
    final List<SupersaleUserModel> targetUsers = bundle.allUsers.where((u) {
      if (selectedBranch != null &&
          selectedBranch.isNotEmpty &&
          u.branch != selectedBranch) {
        return false;
      }
      return true;
    }).toList();

    final Map<String, UserPerformanceReportRow> userPerfMap = {
      for (final u in targetUsers)
        u.uid: UserPerformanceReportRow(
          uid: u.uid,
          username: u.username,
          branch: u.branch,
          role: u.role,
        ),
    };

    // Include any entry user not in targetUsers (e.g. legacy or transferred user)
    for (final entry in filteredEntries) {
      final key = entry.userId.isNotEmpty ? entry.userId : entry.username;
      if (key.isEmpty) continue;
      final uPerf = userPerfMap.putIfAbsent(
        key,
        () => UserPerformanceReportRow(
          uid: entry.userId,
          username: entry.username,
          branch: entry.branch,
          role: 'sales',
        ),
      );

      if (entry.isCancelled) {
        uPerf.cancelledOrders++;
        continue;
      }

      uPerf.totalOrders++;
      uPerf.bookedQty += entry.quantity;
      uPerf.totalAmount += entry.totalAmount;
      uPerf.totalAdvance += entry.advance;

      if (entry.isSpotSale) {
        uPerf.spotSaleOrders++;
      }

      if (entry.isDelivered) {
        uPerf.deliveredOrders++;
        uPerf.deliveredQty += entry.quantity;
      } else {
        uPerf.pendingOrders++;
        uPerf.pendingQty += entry.quantity;
        if (entry.isOverdue(now)) {
          uPerf.overdueOrders++;
        }
      }
    }

    // Calculate campaign participation & non-participants per user
    final List<NonParticipantRow> nonParticipantRows = [];

    for (final u in targetUsers) {
      final uPerf = userPerfMap[u.uid]!;
      final applicable =
          filteredCampaigns.where((c) => c.appliesToBranch(u.branch)).toList();
      uPerf.applicableCampaigns = applicable.length;

      for (final campaign in applicable) {
        final userCampaignEntries = filteredEntries.where((e) {
          if (e.isCancelled) return false;
          if (e.userId != u.uid) return false;
          if (e.adminPostingId.isNotEmpty) {
            return e.adminPostingId == campaign.id;
          }
          return e.itemName == campaign.item && e.branch == u.branch;
        }).toList();

        if (userCampaignEntries.isNotEmpty) {
          uPerf.participatedCampaigns++;
          if (userCampaignEntries.any((e) => e.isDelivered)) {
            uPerf.completedCampaigns++;
          }
        } else {
          nonParticipantRows.add(
            NonParticipantRow(
              uid: u.uid,
              username: u.username,
              branch: u.branch,
              role: u.role,
              campaignItem: campaign.item,
              deliveryEnd: campaign.deliveryEnd,
            ),
          );
        }
      }
    }

    final List<UserPerformanceReportRow> userPerformanceRows =
        userPerfMap.values.toList()
          ..sort((a, b) {
            final cmp = b.bookedQty.compareTo(a.bookedQty);
            if (cmp != 0) return cmp;
            return a.username.compareTo(b.username);
          });

    return SupersaleComputedAnalytics(
      totalCampaigns: filteredCampaigns.length,
      activeBookingCampaigns: activeBookingCampaigns,
      activeDeliveryCampaigns: activeDeliveryCampaigns,
      expiredCampaigns: expiredCampaigns,
      totalValidOrders: totalValidOrders,
      deliveredOrders: deliveredOrders,
      pendingOrders: pendingOrders,
      cancelledOrders: cancelledOrders,
      overdueOrders: overdueOrders,
      spotSaleOrders: spotSaleOrders,
      normalBookingOrders: normalBookingOrders,
      partialSplitOrders: partialSplitOrders,
      totalBookedQty: totalBookedQty,
      deliveredQty: deliveredQty,
      pendingQty: pendingQty,
      cancelledQty: cancelledQty,
      spotSaleQty: spotSaleQty,
      normalBookingQty: normalBookingQty,
      totalOrderAmount: totalOrderAmount,
      deliveredAmount: deliveredAmount,
      pendingAmount: pendingAmount,
      cancelledAmount: cancelledAmount,
      totalAdvanceAmount: totalAdvanceAmount,
      spotSaleAmount: spotSaleAmount,
      normalBookingAmount: normalBookingAmount,
      campaignRows: campaignRows,
      branchBookingRows: branchBookingRows,
      branchDeliveryRows: branchDeliveryRows,
      userPerformanceRows: userPerformanceRows,
      nonParticipantRows: nonParticipantRows,
      overdueEntries: overdueList,
      pendingEntries: pendingList,
      cancelledEntries: cancelledList,
      splitEntries: splitList,
      filteredEntries: filteredEntries,
    );
  }
}

