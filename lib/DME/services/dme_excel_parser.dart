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
  ///   Customer Name, Company, Address, Contact 1, Contact 2,
  ///   Customer Type, Category, Salesman, Branch, Last Purchased Date
  ///
  /// Contact 1 is the unique key per person.
  /// The same Contact 1 can appear on multiple rows with different Company
  /// values — each becomes a separate customer record.
  static List<DmeCustomer> parseCustomerDatabaseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 2) return [];

    final header = sheet.row(0);
    int? nameCol, companyCol, addressCol, contact1Col, contact2Col;
    int? branchCol, dateCol, salesmanCol, customerTypeCol, categoryCol;

    for (var i = 0; i < header.length; i++) {
      final h = header[i]?.value?.toString().toLowerCase().trim() ?? '';
      // Customer Name column (person / contact name)
      if (companyCol == null && nameCol == null && (h.contains('customer name') || h == 'name')) nameCol = i;
      if (nameCol == null && (h.contains('customer') || h.contains('name'))) nameCol ??= i;
      // Company column (firm/company)
      if (h.contains('company') || h.contains('firm')) companyCol ??= i;
      // Address
      if (h.contains('address')) addressCol ??= i;
      // Contact 1 — explicit match first, then fallback
      if (h == 'contact 1' || h == 'contact1') { contact1Col = i; }
      else if (contact1Col == null && (h.contains('contact 1') || h.contains('contact1'))) contact1Col = i;
      else if (contact1Col == null && (h.contains('phone') || h.contains('mobile'))) contact1Col = i;
      // Contact 2
      if (h == 'contact 2' || h == 'contact2') { contact2Col = i; }
      else if (contact2Col == null && (h.contains('contact 2') || h.contains('contact2'))) contact2Col = i;
      // Branch
      if (h.contains('branch')) branchCol ??= i;
      // Last Purchased Date
      if (h.contains('last purchased') || h.contains('last purchase') || h.contains('purchase date') || h.contains('date')) dateCol ??= i;
      // Salesman
      if (h.contains('salesman') || h.contains('sales rep')) salesmanCol ??= i;
      // Customer Type
      if (h.contains('customer type') || h.contains('type')) customerTypeCol ??= i;
      // Category
      if (h.contains('category')) categoryCol ??= i;
    }

    if (contact1Col == null) {
      throw FormatException(
          'Customer Excel must have a Contact 1 column. Found headers: '
          '${header.map((c) => c?.value?.toString()).join(', ')}');
    }

    final customers = <DmeCustomer>[];

    for (var r = 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final rawPhone = _cellStr(row, contact1Col);
      if (rawPhone.isEmpty) continue;
      final contact1 = DmeCustomer.normalizePhone(rawPhone);
      if (contact1.isEmpty) continue;

      final name = nameCol != null ? _cellStr(row, nameCol) : '';
      final company = companyCol != null ? _cellStr(row, companyCol) : null;

      // At least one of name or company must be present
      if (name.isEmpty && (company == null || company.isEmpty)) continue;

      // Parse purchase date if present
      DateTime? purchaseDate;
      if (dateCol != null) {
        final dateStr = _cellStr(row, dateCol);
        if (dateStr.isNotEmpty) {
          purchaseDate = _parseDate(dateStr);
          if (purchaseDate == null) {
            // Skip rows with unparseable dates rather than aborting the whole file
            continue;
          }
        }
      }

      customers.add(DmeCustomer(
        name: name.isNotEmpty ? name : (company ?? ''),
        company: (company != null && company.isNotEmpty) ? company : null,
        phone: contact1,
        contact2: contact2Col != null
            ? DmeCustomer.normalizePhone(_cellStr(row, contact2Col))
            : null,
        address: addressCol != null ? _cellStr(row, addressCol) : null,
        branchName: branchCol != null ? _cellStr(row, branchCol) : null,
        salesman: salesmanCol != null ? _cellStr(row, salesmanCol) : null,
        customerType: customerTypeCol != null ? _cellStr(row, customerTypeCol) : null,
        category: categoryCol != null ? _cellStr(row, categoryCol) : null,
        lastPurchaseDate: purchaseDate,
      ));
    }

    return customers;
  }

  /// Parse a daily sales Excel.
  ///
  /// Column layout (from the sales report):
  ///   0: Date
  ///   1: Particulars  — Company Name (BOLD) = customer row; item name below = item row
  ///   2: Consignee / Party Address
  ///   3: Contact
  ///   4: Voucher Type  — IGNORED
  ///   5: Salesman
  ///   6: GSTIN / UIN  — IGNORED
  ///   7: Quantity      — BOLD value = header total; non-bold = item qty
  ///   8+: IGNORED
  ///
  /// Customer row detection: Particulars cell is bold OR Date column has a value.
  /// Returns a list of [DmeSaleRecord] each containing the customer header
  /// plus its child product items.
  static List<DmeSaleRecord> parseDailySalesExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet.maxRows < 2) return [];

    // ── Detect columns ───────────────────────────────────────────
    final header = sheet.row(0);
    int? dateCol, particularsCol, addressCol, contactCol, salesmanCol, qtyCol;

    for (var i = 0; i < header.length; i++) {
      final h = header[i]?.value?.toString().toLowerCase().trim() ?? '';
      if (h.contains('date')) dateCol ??= i;
      // Particulars column (holds company name bold + item names non-bold)
      if (h.contains('particular') || h.contains('customer') || h.contains('name'))
        particularsCol ??= i;
      // Address column — Consignee / Party Address
      if (h.contains('consignee') || h.contains('party') || h.contains('address'))
        addressCol ??= i;
      // Contact / Phone
      if (h.contains('contact') || h.contains('phone') || h.contains('mobile'))
        contactCol ??= i;
      // Skip Voucher Type (column 4) and GSTIN/UIN (column 6) — not mapped
      // Salesman
      if (h.contains('salesman') || h.contains('sales rep')) salesmanCol ??= i;
      // Quantity
      if (h.contains('quantity') || h.contains('qty')) qtyCol ??= i;
    }

    // Fallback to positional mapping if header detection missed columns
    particularsCol ??= 1;
    addressCol     ??= 2;
    contactCol     ??= 3;
    salesmanCol    ??= 5;
    qtyCol         ??= 7;

    if (particularsCol == null) {
      throw FormatException(
          'Sales Excel must have a Particulars column. Found: '
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
      final particularsValue = _cellStr(row, particularsCol!);
      final qtyValue = qtyCol != null ? _cellStr(row, qtyCol) : '';
      final salesmanValue = salesmanCol != null ? _cellStr(row, salesmanCol) : '';

      if (particularsValue.isEmpty) continue;

      // Customer row: Date is filled OR the Particulars cell is bold
      final bool isCustomerRow = dateValue.isNotEmpty ||
          _isBold(sheet, r, particularsCol!);

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
          customerName: particularsValue,
          address: addressCol != null ? _cellStr(row, addressCol) : null,
          phone: contactCol != null ? _cellStr(row, contactCol) : null,
          salesman: salesmanValue.isNotEmpty ? salesmanValue : null,
          // Category and Customer Type are not present in the daily sales file;
          // they will be collected from the user for new customers after upload.
          category: null,
          customerType: null,
          headerQuantity: _parseDouble(qtyValue),
        );
        currentItems = [];
      } else if (current != null) {
        // Item row — Particulars holds the item/product name
        final qty = _parseDouble(qtyValue) ?? 0;
        final unit = _extractUnit(qtyValue);
        currentItems.add(DmeSaleItem(
          productName: particularsValue,
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
