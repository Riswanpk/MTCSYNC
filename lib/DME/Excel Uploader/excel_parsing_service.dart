import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../dme_constants.dart';
import 'excel_uploader_models.dart';

class ExcelParsingService {
  /// Extracts digit sequence from phone column without stripping prefixes
  static String cleanPhoneNumber(dynamic rawValue) {
    if (rawValue == null) return '';
    String str = rawValue.toString().trim();
    return str.replaceAll(RegExp(r'[^\d]'), '');
  }


  /// Merges Address1, Address2, Address3 into one clean string
  static String mergeAddress(dynamic a1, dynamic a2, dynamic a3) {
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
  static DateTime parseExcelDate(dynamic rawValue) {
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

  static dynamic getCellValue(Data? cell) {
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

  /// Checks if a party name should be ignored (e.g. YUSUF MALABAR TRADING LLP)
  static bool isIgnoredParty(String? party) {
    if (party == null) return false;
    final clean = party.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
    if (clean.isEmpty) return false;
    return clean == 'YUSUF MALABAR TRADING LLP' ||
        clean == 'YUSUF MALABAR TRADING LLP.' ||
        clean == 'YUSUF MALABAR TRADING' ||
        clean.startsWith('YUSUF MALABAR TRADING');
  }

  /// Extracts a 10-digit mobile number from text (e.g. from address columns if mobile column is blank)
  static String extractMobileFromText(dynamic val) {
    if (val == null) return '';
    final str = val.toString().trim();
    if (str.isEmpty) return '';

    // Check if entire clean number is 10 digits
    final clean = cleanPhoneNumber(str);
    if (clean.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(clean)) {
      return clean;
    }

    // Try regex for Indian mobile pattern starting with 6-9
    final match = RegExp(r'(?:(?:\+?91|0)?\s*)?([6-9]\d{9})\b').firstMatch(str);
    if (match != null) {
      return match.group(1) ?? '';
    }
    return '';
  }

  /// Parses Excel file bytes into raw rows and grouped sales
  static Map<String, dynamic> parseExcelBytes(Uint8List bytes) {
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
      bool isCurrentSaleIgnored = false;

      for (int r = 2; r < rows.length; r++) {
        final row = rows[r];
        if (row.isEmpty) continue;

        // Safe cell accessor to prevent RangeError on short/malformed rows
        Data? safeCell(int colIdx) => colIdx < row.length ? row[colIdx] : null;

        String rawBranch = getCellValue(safeCell(0)).toString().trim().toUpperCase();
        dynamic rawDate = getCellValue(safeCell(1));
        String rawVoucher = getCellValue(safeCell(2)).toString().trim();
        String rawParty = getCellValue(safeCell(3)).toString().trim();
        dynamic address1 = getCellValue(safeCell(4));
        dynamic address2 = getCellValue(safeCell(5));
        dynamic address3 = getCellValue(safeCell(6));
        dynamic rawMobile = getCellValue(safeCell(7));
        String rawType = getCellValue(safeCell(8)).toString().trim().toUpperCase();
        String rawCat = getCellValue(safeCell(9)).toString().trim().toUpperCase();
        String rawSalesman = getCellValue(safeCell(10)).toString().trim();
        String itemName = getCellValue(safeCell(11)).toString().trim();
        String qty = getCellValue(safeCell(12)).toString().trim();

        if (rawBranch.isEmpty && rawParty.isEmpty && rawVoucher.isEmpty && itemName.isEmpty) {
          continue;
        }

        final mergedAddr = mergeAddress(address1, address2, address3);

        // Determine phone number strictly from the phone column (Col 7)
        String rowPhone = cleanPhoneNumber(rawMobile);
        if (rowPhone.isEmpty && rawMobile != null && rawMobile.toString().trim().isNotEmpty) {
          rowPhone = rawMobile.toString().trim();
        }

        // Determine if this row belongs to the same ongoing sale or is a new sale
        bool isContinuation = false;
        if (lastParty.isNotEmpty || lastVoucher.isNotEmpty) {
          final bool voucherMatches = rawVoucher.isEmpty || (lastVoucher.isNotEmpty && rawVoucher == lastVoucher);
          final bool partyMatches = rawParty.isEmpty || (lastParty.isNotEmpty && rawParty.toLowerCase() == lastParty.toLowerCase());
          final bool branchMatches = rawBranch.isEmpty || (lastBranchName.isNotEmpty && rawBranch == lastBranchName);
          final bool phoneMatches = rowPhone.isEmpty || lastPhone.isEmpty || (rowPhone == lastPhone);

          if (voucherMatches && partyMatches && branchMatches && phoneMatches) {
            if ((rawVoucher.isNotEmpty && rawVoucher == lastVoucher) ||
                (rawVoucher.isEmpty && rawParty.isEmpty && rowPhone.isEmpty) ||
                (rawParty.isNotEmpty && rawParty.toLowerCase() == lastParty.toLowerCase())) {
              isContinuation = true;
            }
          }
        }

        if (isContinuation) {
          // If the ongoing sale is for an ignored party (e.g. YUSUF MALABAR TRADING LLP), skip it!
          if (isCurrentSaleIgnored) {
            continue;
          }

          if (rowPhone.isNotEmpty && lastPhone.isEmpty) {
            lastPhone = rowPhone;
          }

          final branchName = lastBranchName.isNotEmpty ? lastBranchName : rawBranch;
          final branchId = lastBranchId ?? DmeConstants.getBranchIdByName(branchName);
          final date = lastDate ?? (rawDate != null ? parseExcelDate(rawDate) : DateTime.now());
          final phone = lastPhone;
          final party = lastParty;
          final voucherNo = lastVoucher;
          final address = lastAddress.isNotEmpty ? lastAddress : mergedAddr;
          final typeName = lastTypeName.isNotEmpty ? lastTypeName : rawType;
          final typeId = lastTypeId ?? (typeName.isNotEmpty ? DmeConstants.getCustomerTypeIdByName(typeName) : null);
          final categoryName = lastCatName.isNotEmpty ? lastCatName : rawCat;
          final categoryId = lastCatId ?? (categoryName.isNotEmpty ? DmeConstants.getCategoryIdByName(categoryName) : null);
          final salesman = lastSalesman.isNotEmpty ? lastSalesman : rawSalesman;

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
          continue;
        }

        // --- NEW SALE BOUNDARY ---

        // Check if this party should be ignored completely (e.g. YUSUF MALABAR TRADING LLP)
        if (isIgnoredParty(rawParty)) {
          isCurrentSaleIgnored = true;
          lastVoucher = rawVoucher;
          lastParty = rawParty;
          lastPhone = '';
          lastAddress = '';
          lastSalesman = '';
          lastTypeName = '';
          lastTypeId = null;
          lastCatName = '';
          lastCatId = null;
          if (rawBranch.isNotEmpty) {
            lastBranchName = rawBranch;
            lastBranchId = DmeConstants.getBranchIdByName(rawBranch);
          }
          if (rawDate != null && rawDate.toString().trim().isNotEmpty) {
            lastDate = parseExcelDate(rawDate);
          }
          continue; // Skip ignored party!
        }

        isCurrentSaleIgnored = false;

        if (rawBranch.isNotEmpty) {
          lastBranchName = rawBranch;
          lastBranchId = DmeConstants.getBranchIdByName(rawBranch);
        }
        if (rawDate != null && rawDate.toString().trim().isNotEmpty) {
          lastDate = parseExcelDate(rawDate);
        }

        lastVoucher = rawVoucher;
        lastParty = rawParty;

        // CRITICAL: Phone number belongs ONLY to this new customer row!
        // It NEVER takes the previous customer's phone number!
        lastPhone = rowPhone;

        lastAddress = mergedAddr;
        lastTypeName = rawType;
        lastTypeId = rawType.isNotEmpty ? DmeConstants.getCustomerTypeIdByName(rawType) : null;
        lastCatName = rawCat;
        lastCatId = rawCat.isNotEmpty ? DmeConstants.getCategoryIdByName(rawCat) : null;
        lastSalesman = rawSalesman;

        final branchName = rawBranch.isNotEmpty ? rawBranch : lastBranchName;
        final branchId = DmeConstants.getBranchIdByName(branchName) ?? lastBranchId;
        final date = (rawDate != null && rawDate.toString().trim().isNotEmpty)
            ? parseExcelDate(rawDate)
            : (lastDate ?? DateTime.now());
        final phone = rowPhone;
        final party = rawParty;
        final voucherNo = rawVoucher;
        final address = mergedAddr;
        final typeName = rawType;
        final typeId = lastTypeId;
        final categoryName = rawCat;
        final categoryId = lastCatId;
        final salesman = rawSalesman;

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
      if (isIgnoredParty(row.party)) continue;

      if (currentSale != null &&
          currentSale.phone == row.phone &&
          currentSale.party.toLowerCase() == row.party.toLowerCase() &&
          currentSale.branchName == row.branchName &&
          currentSale.date.year == row.date.year &&
          currentSale.date.month == row.date.month &&
          currentSale.date.day == row.date.day &&
          (currentSale.voucherNo.isEmpty || row.voucherNo.isEmpty || currentSale.voucherNo == row.voucherNo)) {
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

    return {
      'parsedRows': parsed,
      'groupedSales': groupedList,
    };
  }
}
