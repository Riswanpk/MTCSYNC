import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dme_constants.dart';
import 'dme_config.dart';

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

class DmeExcelUploaderPage extends StatefulWidget {
  const DmeExcelUploaderPage({super.key});

  @override
  State<DmeExcelUploaderPage> createState() => _DmeExcelUploaderPageState();
}

class _DmeExcelUploaderPageState extends State<DmeExcelUploaderPage> with SingleTickerProviderStateMixin {
  String? _selectedFileName;
  Uint8List? _fileBytes;
  bool _isParsing = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _statusMessage = '';

  List<ParsedExcelRow> _parsedRows = [];
  List<GroupedSale> _groupedSales = [];
  List<ParsedCustomerItem> _customerList = [];
  List<CustomerConflict> _conflicts = [];
  List<MissingPhoneCustomer> _missingPhones = [];
  final List<String> _logs = [];

  String _customerFilter = 'all'; // 'all', 'new', 'existing', 'conflict'
  String _customerSearch = '';

  SupabaseClient? get _supabaseClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _initSupabaseIfNeeded();
  }

  Future<void> _initSupabaseIfNeeded() async {
    if (!DmeConfig.isConfigured) return;
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: DmeConfig.supabaseUrl,
        anonKey: DmeConfig.supabaseAnonKey,
      );
    }
  }

  /// Pick and process the Excel file
  Future<void> _pickExcelFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() {
        _selectedFileName = file.name;
        _fileBytes = file.bytes;
        _parsedRows.clear();
        _groupedSales.clear();
        _customerList.clear();
        _conflicts.clear();
        _logs.clear();
        _statusMessage = 'File selected: ${file.name}';
      });

      if (_fileBytes != null) {
        await _parseExcel(_fileBytes!);
      } else if (file.path != null) {
        final bytes = await File(file.path!).readAsBytes();
        await _parseExcel(bytes);
      }
    } catch (e) {
      _showSnackBar('Error picking file: $e', isError: true);
    }
  }

  /// Extracts 10-digit mobile number, removing +91, 91 prefix if present
  String _cleanPhoneNumber(dynamic rawValue) {
    if (rawValue == null) return '';
    String str = rawValue.toString().trim();
    String digits = str.replaceAll(RegExp(r'[^\d]'), '');

    if (digits.length == 10) {
      return digits;
    } else if (digits.length > 10) {
      if (digits.startsWith('91') && digits.length == 12) {
        return digits.substring(2);
      }
      if (digits.startsWith('0') && digits.length == 11) {
        return digits.substring(1);
      }
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  /// Merges Address1, Address2, Address3 into one clean string
  String _mergeAddress(dynamic a1, dynamic a2, dynamic a3) {
    List<String> parts = [];
    void addIfValid(dynamic val) {
      if (val != null) {
        String text = val.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') {
          parts.add(text);
        }
      }
    }

    addIfValid(a1);
    addIfValid(a2);
    addIfValid(a3);

    return parts.join(', ');
  }

  /// Parse dates flexibly from Excel (e.g. 8-Jul-26, 2026-07-08, DateTime object)
  DateTime _parseExcelDate(dynamic rawValue) {
    if (rawValue == null) return DateTime.now();
    if (rawValue is DateTime) {
      return DateTime(rawValue.year, rawValue.month, rawValue.day);
    }

    String dateStr = rawValue.toString().trim();
    if (dateStr.isEmpty) return DateTime.now();

    List<String> formats = [
      'd-MMM-yy',
      'd-MMM-yyyy',
      'dd-MMM-yy',
      'dd-MMM-yyyy',
      'dd/MM/yyyy',
      'd/M/yyyy',
      'dd-MM-yyyy',
      'yyyy-MM-dd',
      'MM/dd/yyyy',
    ];

    for (final fmt in formats) {
      try {
        final parsed = DateFormat(fmt).parseLoose(dateStr);
        int year = parsed.year;
        if (year < 100) {
          year = 2000 + year;
        }
        return DateTime(year, parsed.month, parsed.day);
      } catch (_) {}
    }

    final fallback = DateTime.tryParse(dateStr);
    if (fallback != null) {
      return DateTime(fallback.year, fallback.month, fallback.day);
    }
    return DateTime.now();
  }

  dynamic _getCellValue(Data? cell) {
    if (cell == null || cell.value == null) return '';
    final val = cell.value;
    if (val is TextCellValue) return val.value.text ?? '';
    if (val is DateCellValue) {
      return DateTime(val.year, val.month, val.day);
    }
    if (val is DateTimeCellValue) {
      return DateTime(val.year, val.month, val.day);
    }
    if (val is IntCellValue) return val.value.toString();
    if (val is DoubleCellValue) return val.value.toString();
    if (val is BoolCellValue) return val.value.toString();
    return val.toString();
  }

  /// Parses the Excel file and groups continuous items into sales
  Future<void> _parseExcel(Uint8List bytes) async {
    setState(() {
      _isParsing = true;
      _statusMessage = 'Reading and parsing Excel data...';
    });

    try {
      final excel = Excel.decodeBytes(bytes);
      final List<ParsedExcelRow> parsed = [];

      for (var table in excel.tables.keys) {
        final rows = excel.tables[table]?.rows;
        if (rows == null || rows.length < 3) continue;

        // Row 0: Title row (Ignored)
        // Row 1: Header row
        // Row 2+: Data Rows

        String lastBranchName = '';
        int? lastBranchId;
        DateTime? lastDate;
        String lastVoucher = '';
        String lastParty = '';
        String lastAddress = '';
        String lastPhone = '';
        String lastTypeName = '';
        int? lastTypeId;
        String lastCatName = '';
        int? lastCatId;
        String lastSalesman = '';

        for (int r = 2; r < rows.length; r++) {
          final row = rows[r];
          if (row.isEmpty) continue;

          String rawBranch = _getCellValue(row.isNotEmpty ? row[0] : null).toString().trim().toUpperCase();
          dynamic rawDate = row.length > 1 ? _getCellValue(row[1]) : null;
          String rawVoucher = _getCellValue(row.length > 2 ? row[2] : null).toString().trim();
          String rawParty = _getCellValue(row.length > 3 ? row[3] : null).toString().trim();
          dynamic address1 = row.length > 4 ? _getCellValue(row[4]) : null;
          dynamic address2 = row.length > 5 ? _getCellValue(row[5]) : null;
          dynamic address3 = row.length > 6 ? _getCellValue(row[6]) : null;
          dynamic rawMobile = row.length > 7 ? _getCellValue(row[7]) : null;
          String rawType = _getCellValue(row.length > 8 ? row[8] : null).toString().trim().toUpperCase();
          String rawCat = _getCellValue(row.length > 9 ? row[9] : null).toString().trim().toUpperCase();
          String rawSalesman = _getCellValue(row.length > 10 ? row[10] : null).toString().trim();
          String itemName = _getCellValue(row.length > 11 ? row[11] : null).toString().trim();
          String qty = _getCellValue(row.length > 12 ? row[12] : null).toString().trim();

          if (rawBranch.isEmpty && rawParty.isEmpty && rawVoucher.isEmpty && itemName.isEmpty) {
            continue;
          }

          // If a new party or branch or voucher is present, update last seen header data
          if (rawBranch.isNotEmpty) {
            lastBranchName = rawBranch;
            lastBranchId = DmeConstants.getBranchIdByName(rawBranch);
          }
          if (rawDate != null && rawDate.toString().trim().isNotEmpty) {
            lastDate = _parseExcelDate(rawDate);
          }
          if (rawVoucher.isNotEmpty) lastVoucher = rawVoucher;
          if (rawParty.isNotEmpty) lastParty = rawParty;
          if (rawMobile != null && rawMobile.toString().trim().isNotEmpty) {
            lastPhone = _cleanPhoneNumber(rawMobile);
          }
          final mergedAddr = _mergeAddress(address1, address2, address3);
          if (mergedAddr.isNotEmpty) lastAddress = mergedAddr;

          if (rawType.isNotEmpty) {
            lastTypeName = rawType;
            lastTypeId = DmeConstants.getCustomerTypeIdByName(rawType);
          }
          if (rawCat.isNotEmpty) {
            lastCatName = rawCat;
            lastCatId = DmeConstants.getCategoryIdByName(rawCat);
          }
          if (rawSalesman.isNotEmpty) lastSalesman = rawSalesman;

          final branchName = rawBranch.isNotEmpty ? rawBranch : lastBranchName;
          final branchId = DmeConstants.getBranchIdByName(branchName) ?? lastBranchId;
          final date = (rawDate != null && rawDate.toString().trim().isNotEmpty) ? _parseExcelDate(rawDate) : (lastDate ?? DateTime.now());
          final phone = (rawMobile != null && rawMobile.toString().trim().isNotEmpty) ? _cleanPhoneNumber(rawMobile) : lastPhone;
          final party = rawParty.isNotEmpty ? rawParty : lastParty;
          final voucherNo = rawVoucher.isNotEmpty ? rawVoucher : lastVoucher;
          final address = mergedAddr.isNotEmpty ? mergedAddr : lastAddress;
          final typeName = rawType.isNotEmpty ? rawType : lastTypeName;
          final typeId = DmeConstants.getCustomerTypeIdByName(typeName) ?? lastTypeId;
          final categoryName = rawCat.isNotEmpty ? rawCat : lastCatName;
          final categoryId = DmeConstants.getCategoryIdByName(categoryName) ?? lastCatId;
          final salesman = rawSalesman.isNotEmpty ? rawSalesman : lastSalesman;

          parsed.add(ParsedExcelRow(
            branchName: branchName,
            branchId: branchId,
            date: date,
            voucherNo: voucherNo,
            party: party,
            address: address,
            phone: phone,
            typeName: typeName,
            typeId: typeId,
            categoryName: categoryName,
            categoryId: categoryId,
            salesman: salesman,
            itemName: itemName,
            qty: qty,
            rawRowIndex: r + 1,
          ));
        }
      }

      // Group continuous rows with the same Party / Phone / Branch / Date into one sale
      final List<GroupedSale> groupedList = [];
      GroupedSale? currentSale;

      for (var row in parsed) {
        if (currentSale != null &&
            currentSale.phone == row.phone &&
            currentSale.party.toLowerCase() == row.party.toLowerCase() &&
            currentSale.branchName == row.branchName &&
            currentSale.date.year == row.date.year &&
            currentSale.date.month == row.date.month &&
            currentSale.date.day == row.date.day) {
          if (row.itemName.isNotEmpty) {
            currentSale.products.add({
              'item_name': row.itemName,
              'qty': row.qty,
            });
          }
        } else {
          currentSale = GroupedSale(
            voucherNo: row.voucherNo,
            branchName: row.branchName,
            branchId: row.branchId,
            date: row.date,
            party: row.party,
            address: row.address,
            phone: row.phone,
            typeName: row.typeName,
            typeId: row.typeId,
            categoryName: row.categoryName,
            categoryId: row.categoryId,
            salesman: row.salesman,
            products: row.itemName.isNotEmpty
                ? [
                    {
                      'item_name': row.itemName,
                      'qty': row.qty,
                    }
                  ]
                : [],
          );
          groupedList.add(currentSale);
        }
      }

      setState(() {
        _parsedRows = parsed;
        _groupedSales = groupedList;
      });

      // Analyze and Build Customer List and detect duplicates & database conflicts
      await _analyzeCustomerList();
    } catch (e) {
      setState(() {
        _isParsing = false;
        _statusMessage = 'Error parsing file: $e';
      });
      _showSnackBar('Parsing error: $e', isError: true);
    }
  }

  /// Groups by phone number and queries Supabase + checks Excel within itself for repeated phones
  Future<void> _analyzeCustomerList() async {
    final client = _supabaseClient;

    setState(() {
      _isParsing = true;
      _statusMessage = 'Checking duplicate phone numbers & database records...';
    });

    try {
      final List<ParsedCustomerItem> customerItems = [];
      final List<CustomerConflict> detectedConflicts = [];
      final List<MissingPhoneCustomer> detectedMissingPhones = [];
      final Map<String, dynamic> dbCache = {};
      final Map<String, String> excelPhonePartyMap = {}; // phone -> first party seen in this excel

      for (var sale in _groupedSales) {
        bool isExisting = false;
        String? existingDbName;
        int? existingDbId;

        if (sale.phone.isEmpty) {
          if (!detectedMissingPhones.any((m) => m.partyName.toLowerCase() == sale.party.toLowerCase() && m.branchName == sale.branchName)) {
            detectedMissingPhones.add(MissingPhoneCustomer(
              partyName: sale.party,
              branchName: sale.branchName,
              voucherNo: sale.voucherNo,
              address: sale.address,
              salesman: sale.salesman,
              categoryName: sale.categoryName,
              typeName: sale.typeName,
              date: sale.date,
            ));
          }
        } else {
          // 1. Check if same phone is repeated within the same Excel with different party names
          if (excelPhonePartyMap.containsKey(sale.phone)) {
            final firstPartyInExcel = excelPhonePartyMap[sale.phone]!;
            if (firstPartyInExcel.toLowerCase() != sale.party.toLowerCase()) {
              if (!detectedConflicts.any((c) => c.originalPhone == sale.phone && c.newName == sale.party)) {
                detectedConflicts.add(CustomerConflict(
                  originalPhone: sale.phone,
                  existingName: '$firstPartyInExcel (in Excel)',
                  existingCustomerId: null,
                  newName: sale.party,
                  newAddress: sale.address,
                  newSalesman: sale.salesman,
                ));
              }
            }
          } else {
            excelPhonePartyMap[sale.phone] = sale.party;
          }

          // 2. Check with Supabase database for existing record
          if (client != null && DmeConfig.isConfigured) {
            try {
              if (dbCache.containsKey(sale.phone)) {
                final res = dbCache[sale.phone];
                if (res != null) {
                  isExisting = true;
                  existingDbId = res['id'] as int?;
                  existingDbName = (res['name'] ?? '').toString().trim();
                }
              } else {
                final res = await client
                    .from('dme_customers')
                    .select('id, name, phone, address, salesman')
                    .eq('phone', sale.phone)
                    .maybeSingle();

                dbCache[sale.phone] = res;

                if (res != null) {
                  isExisting = true;
                  existingDbId = res['id'] as int?;
                  existingDbName = (res['name'] ?? '').toString().trim();

                  if (existingDbName.isNotEmpty &&
                      sale.party.isNotEmpty &&
                      existingDbName.toLowerCase() != sale.party.toLowerCase()) {
                    if (!detectedConflicts.any((c) => c.originalPhone == sale.phone)) {
                      detectedConflicts.add(CustomerConflict(
                        originalPhone: sale.phone,
                        existingName: existingDbName,
                        existingCustomerId: existingDbId,
                        newName: sale.party,
                        newAddress: sale.address,
                        newSalesman: sale.salesman,
                      ));
                    }
                  }
                }
              }
            } catch (_) {}
          }
        }

        customerItems.add(ParsedCustomerItem(
          phone: sale.phone.isNotEmpty ? sale.phone : 'Missing Phone',
          partyName: sale.party.isNotEmpty ? sale.party : 'Unnamed Party',
          address: sale.address,
          branchName: sale.branchName,
          salesman: sale.salesman,
          categoryName: sale.categoryName,
          typeName: sale.typeName,
          totalSalesCount: 1,
          totalItemsCount: sale.products.length,
          isExisting: isExisting,
          existingDbName: existingDbName,
          existingDbId: existingDbId,
          resolution: detectedConflicts.any((c) => c.originalPhone == sale.phone)
              ? ConflictResolution.keepExisting
              : null,
        ));
      }

      setState(() {
        _customerList = customerItems;
        _conflicts = detectedConflicts;
        _missingPhones = detectedMissingPhones;
        _isParsing = false;
        if (_missingPhones.isNotEmpty) {
          _statusMessage = 'Found ${_missingPhones.length} customer(s) with missing phone number. Please enter phone numbers before uploading.';
        } else if (_conflicts.isNotEmpty) {
          _statusMessage = 'Found ${_conflicts.length} duplicate/conflict phone number(s). Review choices below.';
        } else {
          _statusMessage = 'Found ${_groupedSales.length} sale(s): ${_customerList.where((c) => !c.isExisting).length} New, ${_customerList.where((c) => c.isExisting).length} Existing.';
        }
      });

      if (_missingPhones.isNotEmpty && mounted) {
        await _showMissingPhoneDialog();
      } else if (_conflicts.isNotEmpty && mounted) {
        await _showConflictDialog();
      }
    } catch (e) {
      setState(() {
        _isParsing = false;
        _statusMessage = 'Could not verify database status: $e';
      });
    }
  }

  /// Dialog requiring the user to enter a phone number for customers without one
  Future<void> _showMissingPhoneDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allFilled = _missingPhones.every((m) => m.phoneController.text.trim().length >= 5);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.phone_missed_rounded, color: Colors.redAccent, size: 26),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Missing Phone Numbers',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The following customer(s) have no mobile number in the Excel sheet. DME requires a valid phone number for every customer. Please enter their phone numbers below:',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _missingPhones.length,
                        separatorBuilder: (_, __) => const Divider(height: 20),
                        itemBuilder: (context, idx) {
                          final m = _missingPhones[idx];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      m.partyName.isNotEmpty ? m.partyName : 'Unnamed Party',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      m.branchName,
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                                    ),
                                  ),
                                ],
                              ),
                              if (m.address.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(m.address, style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                              const SizedBox(height: 8),
                              TextField(
                                controller: m.phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: 'Enter Mobile Number *',
                                  hintText: 'e.g. 9876543210',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  prefixIcon: const Icon(Icons.phone_android_rounded, size: 18),
                                  errorText: m.phoneController.text.trim().isEmpty ? 'Required' : null,
                                ),
                                onChanged: (val) {
                                  m.assignedPhone = _cleanPhoneNumber(val.trim());
                                  setDialogState(() {});
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: allFilled ? const Color(0xFF005BAC) : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final unfilled = _missingPhones.where((m) => _cleanPhoneNumber(m.phoneController.text.trim()).isEmpty).toList();
                    if (unfilled.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Please fill in phone numbers for all ${unfilled.length} customer(s).'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // Propagate newly filled phone numbers to parsed rows and grouped sales
                    for (var m in _missingPhones) {
                      final cleanPh = _cleanPhoneNumber(m.phoneController.text.trim());
                      m.assignedPhone = cleanPh;

                      for (var s in _groupedSales) {
                        if (s.party.toLowerCase() == m.partyName.toLowerCase() && s.branchName == m.branchName && s.phone.isEmpty) {
                          s.phone = cleanPh;
                        }
                      }
                      for (var r in _parsedRows) {
                        if (r.party.toLowerCase() == m.partyName.toLowerCase() && r.branchName == m.branchName && r.phone.isEmpty) {
                          r.phone = cleanPh;
                        }
                      }
                      for (var c in _customerList) {
                        if (c.partyName.toLowerCase() == m.partyName.toLowerCase() && c.branchName == m.branchName && (c.phone == 'Missing Phone' || c.phone == 'N/A' || c.phone.isEmpty)) {
                          c.phone = cleanPh;
                        }
                      }
                    }

                    setState(() {
                      _missingPhones.clear();
                    });

                    Navigator.of(ctx).pop();

                    // Now check duplicate phone conflict dialog if any exists
                    if (_conflicts.isNotEmpty && mounted) {
                      _showConflictDialog();
                    }
                  },
                  child: const Text('Save Phone Numbers & Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Dialog allowing the user to choose which customer to keep or change phone number
  Future<void> _showConflictDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Phone Duplication',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The same phone number is associated with different customer names. Select which name to keep or enter a separate phone number:',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _conflicts.length,
                        separatorBuilder: (_, __) => const Divider(height: 24),
                        itemBuilder: (context, idx) {
                          final c = _conflicts[idx];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Phone: ${c.originalPhone}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF005BAC)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '1: ${c.existingName}',
                                      style: TextStyle(color: Colors.blue[900], fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const Icon(Icons.compare_arrows, size: 16, color: Colors.grey),
                                  Expanded(
                                    child: Text(
                                      '2: ${c.newName}',
                                      style: TextStyle(color: Colors.green[800], fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // 3 Choices: Keep Existing, Overwrite, or Assign New Phone
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  ChoiceChip(
                                    label: Text('Keep "${c.existingName}"', style: const TextStyle(fontSize: 12)),
                                    selected: c.userChoice == ConflictResolution.keepExisting,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setDialogState(() => c.userChoice = ConflictResolution.keepExisting);
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  ChoiceChip(
                                    label: Text('Keep "${c.newName}"', style: const TextStyle(fontSize: 12)),
                                    selected: c.userChoice == ConflictResolution.overwriteExisting,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setDialogState(() => c.userChoice = ConflictResolution.overwriteExisting);
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('Change Phone Number', style: TextStyle(fontSize: 12)),
                                    selected: c.userChoice == ConflictResolution.assignNewPhone,
                                    selectedColor: Colors.orange.withValues(alpha: 0.2),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setDialogState(() {
                                          c.userChoice = ConflictResolution.assignNewPhone;
                                          if (c.phoneController.text.isEmpty) {
                                            c.phoneController.text = '${c.originalPhone}_2';
                                          }
                                        });
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),

                              if (c.userChoice == ConflictResolution.assignNewPhone) ...[
                                const SizedBox(height: 10),
                                TextField(
                                  controller: c.phoneController,
                                  decoration: InputDecoration(
                                    labelText: 'New Phone Number for ${c.newName}',
                                    hintText: 'Enter distinct 10-digit mobile number',
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    prefixIcon: const Icon(Icons.phone, size: 18),
                                  ),
                                  onChanged: (val) {
                                    c.customNewPhone = val.trim();
                                  },
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF005BAC),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    for (var c in _conflicts) {
                      if (c.userChoice == ConflictResolution.assignNewPhone) {
                        c.customNewPhone = c.phoneController.text.trim();
                        if (c.customNewPhone.isEmpty) {
                          c.customNewPhone = '${c.originalPhone}_alt';
                        }
                      }
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Apply Choices'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Uploads all processed data to Supabase in fast batch operations
  Future<void> _startUpload() async {
    final client = _supabaseClient;
    if (client == null || !DmeConfig.isConfigured) {
      _showConfigDialog();
      return;
    }

    if (_groupedSales.isEmpty) {
      _showSnackBar('No sales to upload', isError: true);
      return;
    }

    // STRICT CHECK: Ensure no customer has a missing phone number before uploading
    final missingPhoneSales = _groupedSales.where((s) => s.phone.trim().isEmpty).toList();
    if (missingPhoneSales.isNotEmpty || _missingPhones.isNotEmpty) {
      if (_missingPhones.isEmpty) {
        for (var s in missingPhoneSales) {
          if (!_missingPhones.any((m) => m.partyName.toLowerCase() == s.party.toLowerCase() && m.branchName == s.branchName)) {
            _missingPhones.add(MissingPhoneCustomer(
              partyName: s.party,
              branchName: s.branchName,
              voucherNo: s.voucherNo,
              address: s.address,
              salesman: s.salesman,
              categoryName: s.categoryName,
              typeName: s.typeName,
              date: s.date,
            ));
          }
        }
      }
      _showSnackBar('Please fill in missing phone numbers before uploading.', isError: true);
      await _showMissingPhoneDialog();
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.1;
      _logs.clear();
      _statusMessage = 'Preparing batch upload...';
    });

    final currentUser = FirebaseAuth.instance.currentUser;
    final uploadedBy = currentUser?.email ?? currentUser?.uid ?? 'manual_upload';

    try {
      _addLog('Starting fast batch upload for ${_groupedSales.length} sale(s)...');

      // 1. Prepare unique customer records
      final Map<String, Map<String, dynamic>> customersToUpsert = {};
      final Map<String, String> activePhoneBySale = {};

      for (var sale in _groupedSales) {
        String activePhone = sale.phone;

        final conflict = _conflicts.where((c) => c.originalPhone == sale.phone && (c.newName == sale.party || c.existingName == sale.party)).firstOrNull;

        if (conflict != null && conflict.userChoice == ConflictResolution.assignNewPhone && conflict.newName == sale.party) {
          activePhone = conflict.customNewPhone.isNotEmpty ? conflict.customNewPhone : '${sale.phone}_alt';
        }

        activePhoneBySale['${sale.party}_${sale.phone}_${sale.date.millisecondsSinceEpoch}'] = activePhone;

        if (activePhone.isNotEmpty) {
          customersToUpsert[activePhone] = {
            'name': sale.party.isNotEmpty ? sale.party : 'Unnamed Customer',
            'phone': activePhone,
            'address': sale.address.isNotEmpty ? sale.address : null,
            'salesman': sale.salesman.isNotEmpty ? sale.salesman : null,
            'last_purchase_date': DateFormat('yyyy-MM-dd').format(sale.date),
            'updated_at': DateTime.now().toIso8601String(),
          };
        }
      }

      setState(() {
        _uploadProgress = 0.3;
        _statusMessage = 'Syncing ${customersToUpsert.length} customer(s)...';
      });

      // Upsert customers in bulk
      final upsertedCustRes = await client
          .from('dme_customers')
          .upsert(
            customersToUpsert.values.toList(),
            onConflict: 'phone',
          )
          .select('id, phone');

      final Map<String, int> phoneToCustomerId = {};
      for (var row in (upsertedCustRes as List)) {
        final ph = row['phone']?.toString();
        final id = row['id'] as int?;
        if (ph != null && id != null) {
          phoneToCustomerId[ph] = id;
        }
      }

      _addLog('✓ Synchronized ${phoneToCustomerId.length} customer records in Supabase');

      setState(() {
        _uploadProgress = 0.5;
        _statusMessage = 'Inserting sales...';
      });

      // 2. Batch Upsert Sales (Handles re-uploads and multiple sales per customer cleanly)
      final List<Map<String, dynamic>> salesToInsert = [];
      final Map<String, int> saleGroupToIdx = {};

      for (int i = 0; i < _groupedSales.length; i++) {
        final sale = _groupedSales[i];
        final activePhone = activePhoneBySale['${sale.party}_${sale.phone}_${sale.date.millisecondsSinceEpoch}'] ?? sale.phone;
        final custId = phoneToCustomerId[activePhone];
        final dateStr = DateFormat('yyyy-MM-dd').format(sale.date);
        final saleKey = '${custId}_${dateStr}_${sale.branchId}';

        if (!saleGroupToIdx.containsKey(saleKey)) {
          saleGroupToIdx[saleKey] = salesToInsert.length;
          salesToInsert.add({
            'date': dateStr,
            'customer_id': custId,
            'purchased_branch': sale.branchId,
            'salesman': sale.salesman.isNotEmpty ? sale.salesman : null,
            'category_id': sale.categoryId,
            'customer_type_id': sale.typeId,
            'uploaded_by': uploadedBy,
          });
        }
      }

      dynamic insertedSalesRes;
      try {
        // Try upserting with date,customer_id,purchased_branch or onConflict date,customer_id
        insertedSalesRes = await client
            .from('dme_sales')
            .upsert(
              salesToInsert,
              onConflict: 'date,customer_id,purchased_branch',
            )
            .select('id, date, customer_id, purchased_branch');
      } catch (upsertErr) {
        debugPrint('Upsert onConflict date,customer_id,purchased_branch note: $upsertErr');
        try {
          insertedSalesRes = await client
              .from('dme_sales')
              .upsert(
                salesToInsert,
                onConflict: 'date,customer_id',
              )
              .select('id, date, customer_id, purchased_branch');
        } catch (_) {
          // If constraint is custom named, fallback to plain upsert without explicit onConflict
          insertedSalesRes = await client
              .from('dme_sales')
              .upsert(salesToInsert)
              .select('id, date, customer_id, purchased_branch');
        }
      }

      final List insertedSalesList = insertedSalesRes as List;
      final Map<String, int> saleKeyToSaleId = {};
      for (var row in insertedSalesList) {
        final id = row['id'] as int?;
        final dt = row['date']?.toString();
        final cId = row['customer_id']?.toString();
        final bId = row['purchased_branch']?.toString();
        if (id != null && dt != null && cId != null) {
          saleKeyToSaleId['${cId}_${dt}_$bId'] = id;
          saleKeyToSaleId['${cId}_$dt'] = id;
        }
      }

      _addLog('✓ Synchronized ${insertedSalesList.length} sales records in database');

      setState(() {
        _uploadProgress = 0.7;
        _statusMessage = 'Saving sale details, reminders, and branches...';
      });

      // 3. Prepare Batch Sale Details, Reminders (deduplicated by customer_id), and Customer Branches (deduplicated by customer_id + branch_id)
      final List<Map<String, dynamic>> detailsToInsert = [];
      final Map<int, Map<String, dynamic>> remindersByCustomer = {};
      final Map<String, Map<String, dynamic>> branchesByCustBranch = {};

      for (int i = 0; i < _groupedSales.length; i++) {
        final sale = _groupedSales[i];
        final activePhone = activePhoneBySale['${sale.party}_${sale.phone}_${sale.date.millisecondsSinceEpoch}'] ?? sale.phone;
        final custId = phoneToCustomerId[activePhone];
        final dateStr = DateFormat('yyyy-MM-dd').format(sale.date);
        final saleKeyWithBranch = '${custId}_${dateStr}_${sale.branchId}';
        final saleKeyWithoutBranch = '${custId}_$dateStr';
        final saleId = saleKeyToSaleId[saleKeyWithBranch] ?? saleKeyToSaleId[saleKeyWithoutBranch];

        if (saleId != null && sale.products.isNotEmpty) {
          detailsToInsert.add({
            'sale_id': saleId,
            'products': sale.products,
          });
        }

        if (custId != null) {
          // Check if this sale's category is excluded from reminders
          // Excluded: TRUST (7), INSTITUTION (8), VEHICLE SHOWROOM (11), GENERAL & OTHERS (13)
          final catId = sale.categoryId;
          final catName = sale.categoryName.toUpperCase().trim();
          final isExcludedCategory = catId == 7 ||
              catId == 8 ||
              catId == 11 ||
              catId == 13 ||
              catName.contains('TRUST') ||
              catName.contains('INSTITUTION') ||
              catName.contains('VEHICLE') ||
              catName.contains('GENERAL');

          // If this branch/sale is an eligible category, set/update reminder specifically for this branch
          if (!isExcludedCategory) {
            final reminderDate = sale.date.add(const Duration(days: 28));
            final existingReminderForCust = remindersByCustomer[custId];

            // If customer has no reminder yet, or if this eligible sale is newer than any previously considered sale
            if (existingReminderForCust == null) {
              remindersByCustomer[custId] = {
                'customer_id': custId,
                'reminder_date': DateFormat('yyyy-MM-dd').format(reminderDate),
                'last_purchase_date': DateFormat('yyyy-MM-dd').format(sale.date),
                'last_purchase_branch': sale.branchId,
                'status': 'pending', // Fresh/reset reminder date for new purchase
                'updated_at': DateTime.now().toIso8601String(),
              };
            } else {
              // Update with the latest eligible branch sale date
              final prevDateStr = existingReminderForCust['last_purchase_date']?.toString();
              final prevDate = prevDateStr != null ? DateTime.tryParse(prevDateStr) : null;
              if (prevDate == null || sale.date.isAfter(prevDate)) {
                remindersByCustomer[custId] = {
                  'customer_id': custId,
                  'reminder_date': DateFormat('yyyy-MM-dd').format(reminderDate),
                  'last_purchase_date': DateFormat('yyyy-MM-dd').format(sale.date),
                  'last_purchase_branch': sale.branchId,
                  'status': 'pending',
                  'updated_at': DateTime.now().toIso8601String(),
                };
              }
            }
          }

          // Branch junction (recorded for all branches)
          if (sale.branchId != null) {
            final branchKey = '${custId}_${sale.branchId}';
            branchesByCustBranch[branchKey] = {
              'customer_id': custId,
              'branch_id': sale.branchId,
              'category_id': sale.categoryId,
              'customer_type_id': sale.typeId,
            };
          }
        }
      }

      // Check existing reminders in database to ensure we advance due dates for existing customers
      final List<int> customerIdsWithNewReminders = remindersByCustomer.keys.toList();
      if (customerIdsWithNewReminders.isNotEmpty) {
        try {
          // Fetch existing database reminders in chunks of 500
          for (int i = 0; i < customerIdsWithNewReminders.length; i += 500) {
            final chunk = customerIdsWithNewReminders.sublist(
              i,
              (i + 500 > customerIdsWithNewReminders.length) ? customerIdsWithNewReminders.length : i + 500,
            );
            final existingDbReminders = await client
                .from('dme_reminders')
                .select('id, customer_id, last_purchase_date, reminder_date, status')
                .inFilter('customer_id', chunk);

            for (var dbRow in (existingDbReminders as List)) {
              final cId = dbRow['customer_id'] as int?;
              if (cId != null && remindersByCustomer.containsKey(cId)) {
                final dbLastPurchaseStr = dbRow['last_purchase_date']?.toString();
                final dbLastPurchase = dbLastPurchaseStr != null ? DateTime.tryParse(dbLastPurchaseStr) : null;

                final currentObj = remindersByCustomer[cId]!;
                final newLastPurchaseStr = currentObj['last_purchase_date']?.toString();
                final newLastPurchase = newLastPurchaseStr != null ? DateTime.tryParse(newLastPurchaseStr) : null;

                // If existing DB last purchase is newer than Excel, preserve the DB one
                if (dbLastPurchase != null && newLastPurchase != null && dbLastPurchase.isAfter(newLastPurchase)) {
                  remindersByCustomer[cId] = {
                    'customer_id': cId,
                    'reminder_date': dbRow['reminder_date'],
                    'last_purchase_date': dbRow['last_purchase_date'],
                    'last_purchase_branch': currentObj['last_purchase_branch'],
                    'status': dbRow['status'],
                    'updated_at': DateTime.now().toIso8601String(),
                  };
                } else {
                  // The newly uploaded invoice is newer: Reset status to 'pending' and advance reminder_date forward!
                  currentObj['status'] = 'pending';
                  currentObj['updated_at'] = DateTime.now().toIso8601String();
                }
              }
            }
          }
        } catch (checkErr) {
          debugPrint('Notice checking existing reminders: $checkErr');
        }
      }

      final remindersToUpsert = remindersByCustomer.values.toList();
      final customerBranchesToInsert = branchesByCustBranch.values.toList();

      // Execute batch inserts concurrently for maximum speed
      await Future.wait([
        if (detailsToInsert.isNotEmpty)
          client.from('dme_sales_detail').insert(detailsToInsert),
        if (remindersToUpsert.isNotEmpty)
          client.from('dme_reminders').upsert(remindersToUpsert, onConflict: 'customer_id'),
        if (customerBranchesToInsert.isNotEmpty)
          client.from('dme_customer_branches').insert(customerBranchesToInsert),
      ]);

      _addLog('✓ Saved ${detailsToInsert.length} sale detail batches & ${remindersToUpsert.length} reminders');

      setState(() {
        _uploadProgress = 1.0;
        _isUploading = false;
        _statusMessage = 'Upload completed: ${insertedSalesList.length} sales uploaded successfully!';
      });

      _showSummaryDialog(insertedSalesList.length, 0);
    } catch (e) {
      setState(() {
        _isUploading = false;
        _statusMessage = 'Batch upload failed: $e';
      });
      _addLog('✗ Batch upload error: $e');
      _showSnackBar('Upload error: $e', isError: true);
    }
  }

  void _addLog(String msg) {
    setState(() {
      _logs.add('[${DateFormat('HH:mm:ss').format(DateTime.now())}] $msg');
    });
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
      ),
    );
  }

  void _showConfigDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supabase Not Configured'),
        content: const Text(
          'Please set your Supabase URL and Anon Key in `lib/DME/dme_config.dart` before uploading.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSummaryDialog(int success, int errors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              errors == 0 ? Icons.check_circle : Icons.info,
              color: errors == 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            const Text('Upload Summary'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Successfully synced: $success sales'),
            if (errors > 0) Text('Failed to sync: $errors sales', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            Text(
              'All matched branch IDs, categories, customer types, and item details have been saved to Supabase.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filteredCustomers = _customerList.where((c) {
      if (_customerFilter == 'new' && c.isExisting) return false;
      if (_customerFilter == 'existing' && !c.isExisting) return false;
      if (_customerFilter == 'conflict' && !c.hasNameConflict) return false;

      if (_customerSearch.isNotEmpty) {
        final q = _customerSearch.toLowerCase();
        final name = c.partyName.toLowerCase();
        final phone = c.phone.toLowerCase();
        return name.contains(q) || phone.contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DME Excel Sales Uploader'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          if (_conflicts.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${_conflicts.length}'),
                child: const Icon(Icons.warning_amber_rounded),
              ),
              tooltip: 'Review Duplicates',
              onPressed: _showConflictDialog,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pick File Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: (_isParsing || _isUploading) ? null : _pickExcelFile,
                      icon: const Icon(Icons.file_upload),
                      label: Text(_selectedFileName == null ? 'Select Excel File' : 'Change Excel File'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005BAC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    if (_selectedFileName != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'File: $_selectedFileName',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (_isParsing) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(_statusMessage, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Parsed Statistics Card
            if (_parsedRows.isNotEmpty) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload Overview',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('Total Rows', '${_parsedRows.length}', Icons.list_alt),
                          _buildStatItem('Sales', '${_groupedSales.length}', Icons.receipt_long),
                          _buildStatItem(
                            'New',
                            '${_customerList.where((c) => !c.isExisting).length}',
                            Icons.person_add,
                            color: Colors.green,
                          ),
                          _buildStatItem(
                            'Existing',
                            '${_customerList.where((c) => c.isExisting).length}',
                            Icons.how_to_reg,
                            color: Colors.blue,
                          ),
                          if (_conflicts.isNotEmpty)
                            _buildStatItem(
                              'Conflicts',
                              '${_conflicts.length}',
                              Icons.warning_amber,
                              color: Colors.orange,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_isUploading || _isParsing) ? null : _startUpload,
                          icon: const Icon(Icons.cloud_upload),
                          label: Text('Upload ${_groupedSales.length} Sales to Supabase'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8CC63F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Customer Preview Section
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Transactions (${_customerList.length})',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (_conflicts.isNotEmpty)
                            TextButton.icon(
                              onPressed: _showConflictDialog,
                              icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                              label: Text('Resolve (${_conflicts.length})', style: const TextStyle(color: Colors.orange, fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Filter chips & Search
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('All (${_customerList.length})', style: const TextStyle(fontSize: 12)),
                            selected: _customerFilter == 'all',
                            onSelected: (_) => setState(() => _customerFilter = 'all'),
                          ),
                          ChoiceChip(
                            label: Text('New (${_customerList.where((c) => !c.isExisting).length})', style: const TextStyle(fontSize: 12)),
                            selected: _customerFilter == 'new',
                            selectedColor: Colors.green.withValues(alpha: 0.2),
                            onSelected: (_) => setState(() => _customerFilter = 'new'),
                          ),
                          ChoiceChip(
                            label: Text('Existing (${_customerList.where((c) => c.isExisting).length})', style: const TextStyle(fontSize: 12)),
                            selected: _customerFilter == 'existing',
                            selectedColor: Colors.blue.withValues(alpha: 0.2),
                            onSelected: (_) => setState(() => _customerFilter = 'existing'),
                          ),
                          if (_conflicts.isNotEmpty)
                            ChoiceChip(
                              label: Text('Conflicts (${_conflicts.length})', style: const TextStyle(fontSize: 12)),
                              selected: _customerFilter == 'conflict',
                              selectedColor: Colors.orange.withValues(alpha: 0.2),
                              onSelected: (_) => setState(() => _customerFilter = 'conflict'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search customer name or mobile...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (val) => setState(() => _customerSearch = val),
                      ),
                      const SizedBox(height: 12),

                      // Customer List View
                      Container(
                        constraints: const BoxConstraints(maxHeight: 380),
                        child: filteredCustomers.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(child: Text('No transactions match the filter')),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filteredCustomers.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, idx) {
                                  final cust = filteredCustomers[idx];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: cust.isExisting
                                              ? (cust.hasNameConflict ? Colors.orange : Colors.blue)
                                              : Colors.green,
                                          foregroundColor: Colors.white,
                                          child: Icon(
                                            cust.isExisting
                                                ? (cust.hasNameConflict ? Icons.warning_amber : Icons.how_to_reg)
                                                : Icons.person_add,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      cust.partyName,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: cust.isExisting
                                                          ? (cust.hasNameConflict
                                                              ? Colors.orange.withValues(alpha: 0.15)
                                                              : Colors.blue.withValues(alpha: 0.15))
                                                          : Colors.green.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: cust.isExisting
                                                            ? (cust.hasNameConflict ? Colors.orange : Colors.blue)
                                                            : Colors.green,
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      cust.isExisting
                                                          ? (cust.hasNameConflict ? 'Duplicate' : 'Existing')
                                                          : 'New Customer',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: cust.isExisting
                                                            ? (cust.hasNameConflict ? Colors.orange[800] : Colors.blue[800])
                                                            : Colors.green[800],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Mobile: ${cust.phone}  •  Branch: ${cust.branchName}',
                                                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                              ),
                                              if (cust.address.isNotEmpty)
                                                Text(
                                                  cust.address,
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              if (cust.hasNameConflict) ...[
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'Known Name: "${cust.existingDbName}" vs Excel Name: "${cust.partyName}"',
                                                    style: const TextStyle(fontSize: 11, color: Colors.deepOrange),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Upload Progress & Logs
            if (_isUploading || _logs.isNotEmpty) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Upload Progress', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _uploadProgress,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8CC63F)),
                      ),
                      const SizedBox(height: 8),
                      Text(_statusMessage, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const Divider(height: 24),
                      Text('Activity Logs', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                        child: ListView.builder(
                          reverse: true,
                          itemCount: _logs.length,
                          itemBuilder: (context, idx) {
                            final log = _logs[_logs.length - 1 - idx];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: log.contains('✗')
                                      ? Colors.red
                                      : log.contains('✓')
                                          ? Colors.green
                                          : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? const Color(0xFF005BAC), size: 26),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? const Color(0xFF005BAC),
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
