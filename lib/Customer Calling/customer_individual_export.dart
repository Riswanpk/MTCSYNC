import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as syncfusion;
import '../Navigation/user_cache_service.dart';

class CustomerIndividualExportPage extends StatefulWidget {
	const CustomerIndividualExportPage({super.key});

	@override
	State<CustomerIndividualExportPage> createState() => _CustomerIndividualExportPageState();
}

class _CustomerIndividualExportPageState extends State<CustomerIndividualExportPage> {
	String? _selectedBranch;
	String? _selectedUserEmail;
	List<String> _branches = [];
	List<Map<String, dynamic>> _users = [];
	List<Map<String, dynamic>> _allUsers = [];
	String? _selectedMonthYear;
	bool _loadingUsers = false;
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
		_fetchUsersAndBranches();
	}

	Future<void> _fetchUsersAndBranches() async {
		setState(() {
			_loadingUsers = true;
			_error = null;
		});

		try {
			final cachedUsers = await UserCacheService.instance.getAllUsers();
			final users = cachedUsers
					.map((u) => {
							'email': (u['email'] ?? '').toString().trim(),
							'name': (u['username'] ?? '').toString().trim(),
							'branch': (u['branch'] ?? '').toString().trim(),
						})
					.where((u) =>
						u['email']!.isNotEmpty &&
						u['branch']!.isNotEmpty)
					.toList();

			final branches = users
					.map((u) => u['branch'] as String)
					.toSet()
					.toList()
				  ..sort();

			setState(() {
				_allUsers = users;
				_branches = branches;
				if (branches.isNotEmpty) {
					_selectedBranch = branches.first;
					_filterUsersForBranch(branches.first);
				}
				_loadingUsers = false;
			});
		} catch (e) {
			setState(() {
				_error = 'Failed to load users/branches: $e';
				_loadingUsers = false;
			});
		}
	}

	void _filterUsersForBranch(String branch) {
		_users = _allUsers.where((u) => u['branch'] == branch).toList()
			..sort((a, b) {
				final aName = ((a['name'] as String?) ?? '').toLowerCase();
				final bName = ((b['name'] as String?) ?? '').toLowerCase();
				return aName.compareTo(bName);
			});
		_selectedUserEmail = null;
	}

	Future<void> _exportIndividualExcel() async {
		setState(() {
			_loading = true;
			_error = null;
		});
		try {
			final email = _selectedUserEmail?.trim().toLowerCase() ?? '';
			if (email.isEmpty) {
				setState(() { _error = 'Please select a branch and user.'; _loading = false; });
				return;
			}
			final doc = await FirebaseFirestore.instance
					.collection('customer_target')
					.doc(_selectedMonthYear)
					.collection('users')
					.doc(email)
					.get();
			if (!doc.exists || doc.data()?['customers'] == null) {
				setState(() { _error = 'No customer list found for selected user/month.'; _loading = false; });
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
						DropdownButtonFormField<String>(
							value: _branches.contains(_selectedBranch) ? _selectedBranch : null,
							decoration: InputDecoration(
								labelText: 'Branch',
								prefixIcon: const Icon(Icons.business_rounded),
								border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
								filled: true,
								fillColor: isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF),
							),
							dropdownColor: isDark ? const Color(0xFF162236) : Colors.white,
							style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
							items: _branches
									.map((b) => DropdownMenuItem(value: b, child: Text(b)))
									.toList(),
							onChanged: _loadingUsers
									? null
									: (val) {
											if (val == null) return;
											setState(() {
												_selectedBranch = val;
												_filterUsersForBranch(val);
											});
										},
						),
						const SizedBox(height: 16),
						DropdownButtonFormField<String>(
							value: _users.any((u) => u['email'] == _selectedUserEmail)
									? _selectedUserEmail
									: null,
							decoration: InputDecoration(
								labelText: 'User',
								prefixIcon: const Icon(Icons.person_rounded),
								border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
								filled: true,
								fillColor: isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF),
							),
							dropdownColor: isDark ? const Color(0xFF162236) : Colors.white,
							style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
							items: _users
									.map(
										(u) => DropdownMenuItem(
											value: u['email'] as String,
											child: Text(
												((u['name'] as String?) ?? '').isNotEmpty
														? (u['name'] as String)
														: (u['email'] as String),
											),
										),
									)
									.toList(),
							onChanged: _loadingUsers
									? null
									: (val) => setState(() => _selectedUserEmail = val),
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
