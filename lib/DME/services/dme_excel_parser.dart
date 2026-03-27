import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../models/dme_product.dart';
import '../models/dme_customer.dart';
import '../models/dme_sale.dart';

class DmeExcelParser {
  /// Parse a product master Excel. Expected columns: Code, Name, Unit
  static List<DmeProduct> parseProductExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 2) return [];

    final header = sheet.row(0);
    int? codeCol, nameCol, unitCol;

    for (var i = 0; i < header.length; i++) {
      final h = header[i]?.value?.toString().toLowerCase().trim() ?? '';
      if (h.contains('code') || h.contains('item code')) codeCol ??= i;
      if (h.contains('name') || h.contains('product') || h.contains('description')) nameCol ??= i;
      if (h.contains('unit') || h.contains('uom')) unitCol ??= i;
    }

    if (codeCol == null || nameCol == null || unitCol == null) {
      throw FormatException(
          'Product Excel must have Code, Name and Unit columns. Found headers: '
          '${header.map((c) => c?.value?.toString()).join(', ')}');
    }

    final products = <DmeProduct>[];
    for (var r = 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final code = _cellStr(row, codeCol);
      final name = _cellStr(row, nameCol);
      final unit = _cellStr(row, unitCol);
      if (code.isEmpty || name.isEmpty) continue;
      products.add(DmeProduct(code: code, name: name, unit: unit.isNotEmpty ? unit : 'NOS'));
    }
    return products;
  }

  /// Parse a customer database Excel. Columns: Customer, Address, Phone,
  /// Category, Customer Type, Salesman, Quantity (no Date)
  static List<DmeCustomer> parseCustomerDatabaseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 2) return [];

    final header = sheet.row(0);
    int? nameCol, addressCol, phoneCol, categoryCol, typeCol, salesmanCol;

    for (var i = 0; i < header.length; i++) {
      final h = header[i]?.value?.toString().toLowerCase().trim() ?? '';
      if (h.contains('customer') || h.contains('name') || h.contains('client')) nameCol ??= i;
      if (h.contains('address')) addressCol ??= i;
      if (h.contains('phone') || h.contains('mobile') || h.contains('contact')) phoneCol ??= i;
      if (h.contains('category')) categoryCol ??= i;
      if (h.contains('type') || h.contains('customer type')) typeCol ??= i;
      if (h.contains('salesman') || h.contains('sales')) salesmanCol ??= i;
    }

    if (nameCol == null || phoneCol == null) {
      throw FormatException(
          'Customer Excel must have Customer/Name and Phone columns. Found: '
          '${header.map((c) => c?.value?.toString()).join(', ')}');
    }

    final customers = <DmeCustomer>[];
    for (var r = 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final name = _cellStr(row, nameCol);
      final phone = DmeCustomer.normalizePhone(_cellStr(row, phoneCol));
      if (name.isEmpty || phone.isEmpty) continue;
      customers.add(DmeCustomer(
        name: name,
        phone: phone,
        address: addressCol != null ? _cellStr(row, addressCol) : null,
        category: categoryCol != null ? _cellStr(row, categoryCol) : null,
        customerType: typeCol != null ? _cellStr(row, typeCol) : null,
        salesman: salesmanCol != null ? _cellStr(row, salesmanCol) : null,
      ));
    }
    return customers;
  }

  /// Parse a daily sales Excel.
  ///
  /// Format (from image): Customer rows have Date filled; product rows have
  /// Date empty and appear directly below their customer.
  ///
  /// Columns: Date, Customer, Address, Phone(?), Category, Customer Type,
  ///          Salesman, Quantity
  ///
  /// Returns a list of [DmeSaleRecord] each containing the customer header
  /// plus its child product items.
  static List<DmeSaleRecord> parseDailySalesExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 2) return [];

    // ── Detect columns ───────────────────────────────────────────
    final header = sheet.row(0);
    int? dateCol, customerCol, addressCol, phoneCol, categoryCol;
    int? typeCol, salesmanCol, qtyCol;

    for (var i = 0; i < header.length; i++) {
      final h = header[i]?.value?.toString().toLowerCase().trim() ?? '';
      if (h.contains('date')) dateCol ??= i;
      if (h.contains('customer') || h.contains('name')) customerCol ??= i;
      if (h.contains('address')) addressCol ??= i;
      if (h.contains('phone') || h.contains('mobile') || h.contains('contact')) phoneCol ??= i;
      if (h.contains('category')) categoryCol ??= i;
      if (h.contains('type') || h.contains('customer type')) typeCol ??= i;
      if (h.contains('salesman') || h.contains('sales')) salesmanCol ??= i;
      if (h.contains('quantity') || h.contains('qty')) qtyCol ??= i;
    }

    if (customerCol == null) {
      throw FormatException(
          'Sales Excel must have a Customer column. Found: '
          '${header.map((c) => c?.value?.toString()).join(', ')}');
    }

    // ── Iterate rows ─────────────────────────────────────────────
    final records = <DmeSaleRecord>[];
    DmeSaleRecord? current;
    List<DmeSaleItem> currentItems = [];
    DateTime lastDate = DateTime.now();

    for (var r = 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final dateValue = dateCol != null ? _cellStr(row, dateCol) : '';
      final customerValue = _cellStr(row, customerCol);
      final qtyValue = qtyCol != null ? _cellStr(row, qtyCol) : '';
      final salesmanValue = salesmanCol != null ? _cellStr(row, salesmanCol) : '';

      if (customerValue.isEmpty) continue;

      // Detect if this is a customer header row:
      // 1. Date column is filled, OR
      // 2. The row has bold formatting on the customer cell, OR
      // 3. The salesman column is filled AND date is filled
      final bool isCustomerRow = dateValue.isNotEmpty ||
          _isBold(sheet, r, customerCol) ||
          (salesmanValue.isNotEmpty && _hasAddressOrPhone(row, addressCol, phoneCol));

      if (isCustomerRow) {
        // Save previous record
        if (current != null) {
          records.add(DmeSaleRecord(
            date: current.date,
            customerName: current.customerName,
            address: current.address,
            phone: current.phone,
            category: current.category,
            customerType: current.customerType,
            salesman: current.salesman,
            headerQuantity: current.headerQuantity,
            items: List.unmodifiable(currentItems),
          ));
        }

        // Parse date
        if (dateValue.isNotEmpty) {
          lastDate = _parseDate(dateValue) ?? lastDate;
        }

        current = DmeSaleRecord(
          date: lastDate,
          customerName: customerValue,
          address: addressCol != null ? _cellStr(row, addressCol) : null,
          phone: phoneCol != null ? _cellStr(row, phoneCol) : null,
          category: categoryCol != null ? _cellStr(row, categoryCol) : null,
          customerType: typeCol != null ? _cellStr(row, typeCol) : null,
          salesman: salesmanValue.isNotEmpty ? salesmanValue : null,
          headerQuantity: _parseDouble(qtyValue),
        );
        currentItems = [];
      } else if (current != null) {
        // Product row — customer column holds the product name
        final qty = _parseDouble(qtyValue) ?? 0;
        final unit = _extractUnit(qtyValue);
        currentItems.add(DmeSaleItem(
          productName: customerValue,
          quantity: qty,
          unit: unit,
        ));
      }
    }

    // Save last record
    if (current != null) {
      records.add(DmeSaleRecord(
        date: current.date,
        customerName: current.customerName,
        address: current.address,
        phone: current.phone,
        category: current.category,
        customerType: current.customerType,
        salesman: current.salesman,
        headerQuantity: current.headerQuantity,
        items: List.unmodifiable(currentItems),
      ));
    }

    return records;
  }

  // ── Helpers ──────────────────────────────────────────────────

  static String _cellStr(List<Data?> row, int col) {
    if (col >= row.length) return '';
    return row[col]?.value?.toString().trim() ?? '';
  }

  static bool _isBold(Sheet sheet, int row, int col) {
    try {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
      return cell.cellStyle?.isBold ?? false;
    } catch (_) {
      return false;
    }
  }

  static bool _hasAddressOrPhone(List<Data?> row, int? addressCol, int? phoneCol) {
    if (addressCol != null && _cellStr(row, addressCol).isNotEmpty) return true;
    if (phoneCol != null && _cellStr(row, phoneCol).isNotEmpty) return true;
    return false;
  }

  static DateTime? _parseDate(String value) {
    // Try common formats: dd-MMM-yy, dd/MM/yyyy, yyyy-MM-dd
    try {
      // Handle "20-Jan-26" format
      final parts = value.split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        final months = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
        };
        final monthNum = months[parts[1].toLowerCase()];
        if (monthNum != null) {
          var day = int.tryParse(parts[0]) ?? 1;
          var year = int.tryParse(parts[2]) ?? 2026;
          if (year < 100) year += 2000;
          return DateTime(year, monthNum, day);
        }
        // Try dd/MM/yyyy
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          return DateTime(y < 100 ? y + 2000 : y, m, d);
        }
      }
      // Fallback
      return DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  static double? _parseDouble(String value) {
    if (value.isEmpty) return null;
    // Extract number from strings like "200.00 MTR" or "175 PCS"
    final match = RegExp(r'[\d,.]+').firstMatch(value);
    if (match == null) return null;
    return double.tryParse(match.group(0)!.replaceAll(',', ''));
  }

  static String? _extractUnit(String value) {
    if (value.isEmpty) return null;
    final match = RegExp(r'[A-Za-z]+$').firstMatch(value.trim());
    return match?.group(0)?.toUpperCase();
  }
}
