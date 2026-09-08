import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../dme_constants.dart';
import 'excel_uploader_models.dart';

class ExcelParsingService {
  /// Extracts 10-digit mobile number, removing +91, 91 prefix if present
  static String cleanPhoneNumber(dynamic rawValue) {
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

        // If a new party or branch or voucher is present, update last seen header data
        if (rawBranch.isNotEmpty) {
          lastBranchName = rawBranch;
          lastBranchId = DmeConstants.getBranchIdByName(rawBranch);
        }
        if (rawDate != null && rawDate.toString().trim().isNotEmpty) {
          lastDate = parseExcelDate(rawDate);
        }
        if (rawVoucher.isNotEmpty) lastVoucher = rawVoucher;
        if (rawParty.isNotEmpty) lastParty = rawParty;
        if (rawMobile != null && rawMobile.toString().trim().isNotEmpty) {
          lastPhone = cleanPhoneNumber(rawMobile);
        }
        final mergedAddr = mergeAddress(address1, address2, address3);
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
        final date = (rawDate != null && rawDate.toString().trim().isNotEmpty)
            ? parseExcelDate(rawDate)
            : (lastDate ?? DateTime.now());
        final phone = (rawMobile != null && rawMobile.toString().trim().isNotEmpty)
            ? cleanPhoneNumber(rawMobile)
            : lastPhone;
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

    return {
      'parsedRows': parsed,
      'groupedSales': groupedList,
    };
  }
}
