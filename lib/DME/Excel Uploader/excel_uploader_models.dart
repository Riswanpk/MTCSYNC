import 'package:flutter/material.dart';

/// Enum to handle customer name conflict resolutions
enum ConflictResolution {
  keepExisting, // Keep existing customer name (attach sale to existing)
  overwriteExisting, // Overwrite existing customer name with new party name
  assignNewPhone, // Edit/change phone number for the new customer so both exist
}

/// Parsed row from the Excel file
class ParsedExcelRow {
  final String branchName;
  final int? branchId;
  final DateTime date;
  final String voucherNo;
  final String party;
  final String address;
  String phone;
  final String typeName;
  final int? typeId;
  final String categoryName;
  final int? categoryId;
  final String salesman;
  final String itemName;
  final String qty;
  final int rawRowIndex;

  ParsedExcelRow({
    required this.branchName,
    this.branchId,
    required this.date,
    required this.voucherNo,
    required this.party,
    required this.address,
    required this.phone,
    required this.typeName,
    this.typeId,
    required this.categoryName,
    this.categoryId,
    required this.salesman,
    required this.itemName,
    required this.qty,
    required this.rawRowIndex,
  });
}

/// Grouped Sale by Party and continuous items
class GroupedSale {
  final String voucherNo;
  final String branchName;
  final int? branchId;
  final DateTime date;
  String party;
  String address;
  String phone;
  final String typeName;
  final int? typeId;
  final String categoryName;
  final int? categoryId;
  final String salesman;
  final List<Map<String, String>> products; // [{'item_name': '...', 'qty': '...'}]

  GroupedSale({
    required this.voucherNo,
    required this.branchName,
    this.branchId,
    required this.date,
    required this.party,
    required this.address,
    required this.phone,
    required this.typeName,
    this.typeId,
    required this.categoryName,
    this.categoryId,
    required this.salesman,
    required this.products,
  });
}

/// Item to represent each customer/sale in the preview list
class ParsedCustomerItem {
  String phone;
  final String partyName;
  final String address;
  final String branchName;
  final String salesman;
  final String categoryName;
  final String typeName;
  final int totalSalesCount;
  final int totalItemsCount;
  final bool isExisting;
  final String? existingDbName;
  final int? existingDbId;
  ConflictResolution? resolution;

  ParsedCustomerItem({
    required this.phone,
    required this.partyName,
    required this.address,
    required this.branchName,
    required this.salesman,
    required this.categoryName,
    required this.typeName,
    required this.totalSalesCount,
    required this.totalItemsCount,
    required this.isExisting,
    this.existingDbName,
    this.existingDbId,
    this.resolution,
  });

  bool get hasNameConflict =>
      isExisting &&
      existingDbName != null &&
      existingDbName!.trim().toLowerCase() != partyName.trim().toLowerCase();
}

/// Information about a customer name mismatch / duplicate phone conflict
class CustomerConflict {
  final String originalPhone;
  final String existingName;
  final int? existingCustomerId;
  final String newName;
  final String newAddress;
  final String newSalesman;
  ConflictResolution userChoice;
  String customNewPhone; // Custom phone if user chooses to change number
  final TextEditingController phoneController;

  CustomerConflict({
    required this.originalPhone,
    required this.existingName,
    this.existingCustomerId,
    required this.newName,
    required this.newAddress,
    required this.newSalesman,
    this.userChoice = ConflictResolution.keepExisting,
    String? customPhone,
  })  : customNewPhone = customPhone ?? '',
        phoneController = TextEditingController(text: customPhone ?? '');
}

/// Information about a customer record without a phone number
class MissingPhoneCustomer {
  final String partyName;
  final String branchName;
  final String voucherNo;
  final String address;
  final String salesman;
  final String categoryName;
  final String typeName;
  final DateTime date;
  String assignedPhone;
  final TextEditingController phoneController;

  MissingPhoneCustomer({
    required this.partyName,
    required this.branchName,
    required this.voucherNo,
    required this.address,
    required this.salesman,
    required this.categoryName,
    required this.typeName,
    required this.date,
    String? phone,
  })  : assignedPhone = phone ?? '',
        phoneController = TextEditingController(text: phone ?? '');
}
