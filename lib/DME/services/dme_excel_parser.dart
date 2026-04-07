import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../models/dme_product.dart';
import '../models/dme_customer.dart';
import '../models/dme_sale.dart';

class DmeExcelParser {
  /// Parse a product master Excel. Expected columns: Name, Unit
  static List<DmeProduct> parseProductExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 2) return [];

    final header = sheet.row(0);
    int? nameCol, unitCol;

    for (var i = 0; i < header.length; i++) {
      final h = header[i]?.value?.toString().toLowerCase().trim() ?? '';
      if (h.contains('name') || h.contains('product') || h.contains('description') || h.contains('item')) nameCol ??= i;
      if (h.contains('unit') || h.contains('uom')) unitCol ??= i;
    }

    if (nameCol == null || unitCol == null) {
      throw FormatException(
          'Product Excel must have Name and Unit columns. Found headers: '
          '${header.map((c) => c?.value?.toString()).join(', ')}');
    }

    final products = <DmeProduct>[];
    for (var r = 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final name = _cellStr(row, nameCol);
      final unit = _cellStr(row, unitCol);
      if (name.isEmpty) continue;
      products.add(DmeProduct(name: name, unit: unit.isNotEmpty ? unit : 'NOS'));
    }
    return products;
  }

  /// Parse a customer database Excel with extended fields.
  ///
  /// Expected columns (in any order):
  ///   Customer Name, Address (any number of address columns — all merged),
  ///   Contact 1, Contact 2, Customer Type, Category, Salesman, Branch,
  ///   Last Purchased Date, Purchased For (optional)
  ///
  /// Contact 1 / phone is the unique key per customer.
  static List<DmeCustomer> parseCustomerDatabaseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 3) return [];

    final header = sheet.row(1);
    int? nameCol, contact1Col;
    int? branchCol, dateCol, salesmanCol, customerTypeCol, categoryCol;
    int? purchasedForCol;
    final List<int> addressCols = [];

    for (var i = 0; i < header.length; i++) {
      final h = header[i]?.value?.toString().toLowerCase().trim() ?? '';
      if (h.isEmpty) continue;
      if (nameCol == null && (h.contains('customer name') || h == 'name' || h.contains('customer'))) nameCol = i;
      if (h.contains('address')) addressCols.add(i);
      if (h == 'contact 1' || h == 'contact1') { contact1Col = i; }
      else if (contact1Col == null && (h.contains('contact 1') || h.contains('contact1') || h.contains('phone') || h.contains('mobile'))) contact1Col = i;
      if (h.contains('branch')) branchCol ??= i;
      if (h.contains('last purchased') || h.contains('last purchase') || h.contains('purchase date')) dateCol ??= i;
      if (dateCol == null && h.contains('date')) dateCol = i;
      if (h.contains('salesman') || h.contains('sales rep')) salesmanCol ??= i;
      if (h.contains('customer type') || h == 'type') customerTypeCol ??= i;
      if (h.contains('category')) categoryCol ??= i;
      if (h.contains('purchased for') || h.contains('purchased_for')) purchasedForCol ??= i;
    }

    if (contact1Col == null) {
      throw FormatException(
          'Customer Excel must have a Contact 1 / Phone column. Found headers: '
          '${header.map((c) => c?.value?.toString()).join(', ')}');
    }

    final customers = <DmeCustomer>[];

    for (var r = 2; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final rawPhone = _cellStr(row, contact1Col!);
      if (rawPhone.isEmpty) continue;
      final contact1 = DmeCustomer.normalizePhone(rawPhone);
      if (contact1.isEmpty) continue;

      final name = nameCol != null ? _cellStr(row, nameCol!) : '';
      if (name.isEmpty) continue;

      // Merge all address columns
      final addressParts = addressCols
          .map((c) => _cellStr(row, c))
          .where((s) => s.isNotEmpty)
          .toList();
      final address = addressParts.isNotEmpty ? addressParts.join(', ') : null;

      // Parse purchase date if present
      DateTime? purchaseDate;
      if (dateCol != null) {
        final dateStr = _cellStr(row, dateCol!);
        if (dateStr.isNotEmpty) {
          purchaseDate = _parseDate(dateStr);
          if (purchaseDate == null) continue;
        }
      }

      customers.add(DmeCustomer(
        name: name,
        purchasedFor: purchasedForCol != null ? _cellStr(row, purchasedForCol!) : null,
        phone: contact1,
        address: address,
        branchName: branchCol != null ? _cellStr(row, branchCol!) : null,
        salesman: salesmanCol != null ? _cellStr(row, salesmanCol!) : null,
        customerType: customerTypeCol != null ? _cellStr(row, customerTypeCol!) : null,
        category: categoryCol != null ? _cellStr(row, categoryCol!) : null,
        lastPurchaseDate: purchaseDate,
      ));
    }

    return customers;
  }

  /// Parse a daily sales Excel (flat-row format).
  ///
  /// Expected columns (detected by header name, order-independent):
  ///   Branch, Date, VoucherNo (ignored), Party, Address1..N (all merged),
  ///   Mobile, Type, Category, Salesman, ItemName, Qty
  ///
  /// Each row represents one item. Rows with the same (normalized phone + date)
  /// are grouped into a single [DmeSaleRecord] with accumulated items.
  static List<DmeSaleRecord> parseDailySalesExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 3) return [];

    // ── Detect columns ───────────────────────────────────────────
    final header = sheet.row(1);
    int? dateCol, partyCol, phoneCol, typeCol, categoryCol, salesmanCol;
    int? itemNameCol, qtyCol, branchCol;
    final List<int> addressCols = []; // ALL columns whose header contains "address"

    for (var i = 0; i < header.length; i++) {
      final h = header[i]?.value?.toString().toLowerCase().trim() ?? '';
      if (h.isEmpty) continue;

      if (h.contains('branch')) branchCol ??= i;
      if (h.contains('date')) dateCol ??= i;
      if (h == 'party' || (partyCol == null && (h.contains('party') || h.contains('customer') || h.contains('name')))) partyCol ??= i;
      if (h.contains('address')) addressCols.add(i);
      if (h.contains('mobile') || h.contains('phone') || h.contains('contact')) phoneCol ??= i;
      if (h == 'type') typeCol = i;
      if (h == 'category' || (categoryCol == null && h.contains('category'))) categoryCol ??= i;
      if (h.contains('salesman') || h.contains('sales rep')) salesmanCol ??= i;
      if (h == 'itemname' || (itemNameCol == null && (h.contains('item') || h.contains('product')))) itemNameCol ??= i;
      if (h == 'qty' || (qtyCol == null && (h.contains('qty') || h.contains('quantity')))) qtyCol ??= i;
    }

    // ── Build grouped records ────────────────────────────────────
    // Key: "normalizedPhone|dateStr"  or  "partyNameLower|dateStr" when no phone
    final Map<String, Map<String, dynamic>> _headers = {};
    final Map<String, List<DmeSaleItem>> _items = {};
    final List<String> _orderedKeys = [];

    for (var r = 2; r < sheet.maxRows; r++) {
      final row = sheet.row(r);

      final partyName = partyCol != null ? _cellStr(row, partyCol!) : '';
      if (partyName.isEmpty || partyName.toLowerCase() == 'cash') continue;
      final rawPhone  = phoneCol  != null ? _cellStr(row, phoneCol!) : '';

      // Date is required for grouping sales; must be parsed successfully
      final dateStr = dateCol != null ? _cellStr(row, dateCol!) : '';
      if (dateStr.isEmpty) continue;
      final date = _parseDate(dateStr);
      if (date == null) continue;

      final phone = DmeCustomer.normalizePhone(rawPhone);

      final groupKey = phone.isNotEmpty
          ? '${phone}|${date.toIso8601String().split('T')[0]}'
          : '${partyName.toLowerCase()}|${date.toIso8601String().split('T')[0]}';

      // Merge all address columns
      final addressParts = addressCols
          .map((c) => _cellStr(row, c))
          .where((s) => s.isNotEmpty)
          .toList();
      final address = addressParts.join(', ');

      if (!_headers.containsKey(groupKey)) {
        _orderedKeys.add(groupKey);
        _headers[groupKey] = {
          'date': date,
          'customerName': partyName,
          'phone': phone.isNotEmpty ? phone : null,
          'address': address.isNotEmpty ? address : null,
          'branch': branchCol != null ? _cellStr(row, branchCol!) : null,
          'customerType': typeCol != null ? _cellStr(row, typeCol!) : null,
          'category': categoryCol != null ? _cellStr(row, categoryCol!) : null,
          'salesman': salesmanCol != null ? _cellStr(row, salesmanCol!) : null,
        };
        _items[groupKey] = [];
      }

      // Append item if itemName is present
      final itemName = itemNameCol != null ? _cellStr(row, itemNameCol!) : '';
      if (itemName.isNotEmpty) {
        final qtyStr = qtyCol != null ? _cellStr(row, qtyCol!) : '';
        _items[groupKey]!.add(DmeSaleItem(
          productName: itemName,
          quantity: _parseDouble(qtyStr) ?? 0,
          unit: _extractUnit(qtyStr),
        ));
      }
    }

    return _orderedKeys.map((k) {
      final h = _headers[k]!;
      return DmeSaleRecord(
        date: h['date'] as DateTime,
        customerName: h['customerName'] as String,
        phone: h['phone'] as String?,
        address: h['address'] as String?,
        branch: h['branch'] as String?,
        customerType: h['customerType'] as String?,
        category: h['category'] as String?,
        salesman: h['salesman'] as String?,
        items: _items[k]!,
      );
    }).toList();
  }

  // ── Helpers ──────────────────────────────────────────────────

  static String _cellStr(List<Data?> row, int col) {
    if (col >= row.length) return '';
    return row[col]?.value?.toString().trim() ?? '';
  }

  static DateTime? _parseDate(String value) {
    // Try common formats: dd-MMM-yy, dd/MM/yyyy, yyyy-MM-dd
    try {
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
      return DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  static double? _parseDouble(String value) {
    if (value.isEmpty) return null;
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
