import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as syncfusion;

class CustomerIndividualExportPage extends StatefulWidget {
	const CustomerIndividualExportPage({super.key});

	@override
	State<CustomerIndividualExportPage> createState() => _CustomerIndividualExportPageState();
}

class _CustomerIndividualExportPageState extends State<CustomerIndividualExportPage> {
	final TextEditingController _emailController = TextEditingController();
	String? _selectedMonthYear;
	bool _loading = false;
	String? _error;
	final List<String> _monthYears = List.generate(
		12,
		(i) {
			final now = DateTime.now();
			final date = DateTime(now.year, now.month - i, 1);
			const months = [
				'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
				'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
			];
			return "${months[date.month - 1]} ${date.year}";
		},
	);

	@override
	void initState() {
		super.initState();
		_selectedMonthYear = _monthYears.first;
	}

	Future<void> _exportIndividualExcel() async {
		setState(() {
			_loading = true;
			_error = null;
		});
		try {
			final email = _emailController.text.trim().toLowerCase();
			if (email.isEmpty) {
				setState(() { _error = 'Please enter a user email.'; _loading = false; });
				return;
			}
			final doc = await FirebaseFirestore.instance
					.collection('customer_target')
					.doc(_selectedMonthYear)
					.collection('users')
					.doc(email)
					.get();
			if (!doc.exists || doc.data()?['customers'] == null) {
				setState(() { _error = 'No customer list found for this user/month.'; _loading = false; });
				return;
			}
			final List<dynamic> customersRaw = doc.data()!['customers'];
			final customers = customersRaw.map((e) => Map<String, dynamic>.from(e)).toList();

			final workbook = syncfusion.Workbook();
			final sheet = workbook.worksheets[0];
			sheet.name = 'Customers';

			// Header
			sheet.getRangeByName('A1').setText('Name');
			sheet.getRangeByName('B1').setText('Address');
			sheet.getRangeByName('C1').setText('Phone');
			for (final col in ['A1', 'B1', 'C1']) {
				final cell = sheet.getRangeByName(col);
				cell.cellStyle.bold = true;
				cell.cellStyle.backColor = '#005BAC';
				cell.cellStyle.fontColor = '#FFFFFF';
				cell.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
				cell.cellStyle.borders.all.color = '#CCCCCC';
			}

			// Data rows
			int row = 2;
			for (final customer in customers) {
				sheet.getRangeByName('A$row').setText(customer['name'] ?? '');
				sheet.getRangeByName('B$row').setText(customer['address'] ?? '');
				sheet.getRangeByName('C$row').setText(
					customer['contact1'] ?? customer['contact'] ?? customer['phone'] ?? ''
				);
				for (final col in ['A$row', 'B$row', 'C$row']) {
					final cell = sheet.getRangeByName(col);
					cell.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
					cell.cellStyle.borders.all.color = '#CCCCCC';
				}
				row++;
			}
			sheet.autoFitColumn(1);
			sheet.autoFitColumn(2);
			sheet.autoFitColumn(3);

			final List<int> bytes = workbook.saveAsStream();
			workbook.dispose();

			final dir = await getTemporaryDirectory();
			final file = File('${dir.path}/CustomerList_${email}_${_selectedMonthYear!.replaceAll(' ', '_')}.xlsx');
			await file.writeAsBytes(bytes, flush: true);
			await Share.shareXFiles([XFile(file.path)], text: 'Customer List $_selectedMonthYear');
		} catch (e) {
			setState(() { _error = 'Export failed: $e'; });
		} finally {
			setState(() { _loading = false; });
		}
	}

	@override
	Widget build(BuildContext context) {
		final isDark = Theme.of(context).brightness == Brightness.dark;
		return Scaffold(
			appBar: AppBar(
				title: const Text('Export Individual Customer List'),
				backgroundColor: const Color(0xFF005BAC),
				foregroundColor: Colors.white,
			),
			backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F7FA),
			body: Padding(
				padding: const EdgeInsets.all(20),
				child: Column(
					crossAxisAlignment: CrossAxisAlignment.stretch,
					children: [
						TextField(
							controller: _emailController,
							decoration: InputDecoration(
								labelText: 'User Email',
								prefixIcon: const Icon(Icons.email_rounded),
								border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
								filled: true,
								fillColor: isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF),
							),
							keyboardType: TextInputType.emailAddress,
						),
						const SizedBox(height: 16),
						DropdownButtonFormField<String>(
							value: _selectedMonthYear,
							decoration: InputDecoration(
								labelText: 'Month',
								prefixIcon: const Icon(Icons.calendar_today_rounded),
								border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
								filled: true,
								fillColor: isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF),
							),
							dropdownColor: isDark ? const Color(0xFF162236) : Colors.white,
							style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
							items: _monthYears.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
							onChanged: (val) => setState(() => _selectedMonthYear = val),
						),
						const SizedBox(height: 24),
						ElevatedButton.icon(
							onPressed: _loading ? null : _exportIndividualExcel,
							icon: _loading
									? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
									: const Icon(Icons.download_rounded),
							label: Text(_loading ? 'Exporting...' : 'Export as Excel'),
							style: ElevatedButton.styleFrom(
								backgroundColor: const Color(0xFF8CC63F),
								foregroundColor: Colors.white,
								padding: const EdgeInsets.symmetric(vertical: 16),
								textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
								shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
							),
						),
						if (_error != null) ...[
							const SizedBox(height: 16),
							Text(_error!, style: const TextStyle(color: Colors.red)),
						],
					],
				),
			),
		);
	}
}
