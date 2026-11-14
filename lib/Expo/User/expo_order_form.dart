import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../Navigation/user_cache_service.dart';
import '../expo_draft_service.dart';
import '../expo_service.dart';
import '../expo_states_districts_service.dart';
import '../expo_supabase_config.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class ExpoOrderFormPage extends StatefulWidget {
  final Exhibition exhibition;
  final String initialOrderType;
  final ExpoOrderDraft? initialDraft;

  const ExpoOrderFormPage({
    super.key,
    required this.exhibition,
    this.initialOrderType = 'Spot Delivery',
    this.initialDraft,
  });

  @override
  State<ExpoOrderFormPage> createState() => _ExpoOrderFormPageState();
}

class _ItemRowData {
  final TextEditingController mtcCodeController = TextEditingController();
  final TextEditingController itemNameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController gstController = TextEditingController();

  File? photoFile;
  String? existingPhotoUrl;
  bool isFetchingMtc = false;

  /// Saved items are shown as a compact summary tile (tap edit to reopen).
  bool isSaved = false;
  int gstType = 0; // 0 = EXCLUDE, 1 = INCLUDE
  double baseGst = 0.0;
  double gstAboveThreshold = 0.0;
  double gstThreshold = 0.0;
  double total = 0.0;

  int get qty => int.tryParse(qtyController.text.trim()) ?? 0;
  double get rate => double.tryParse(rateController.text.trim()) ?? 0.0;
  double get gst => double.tryParse(gstController.text.trim()) ?? 0.0;

  double get subtotalAmount =>
      ExpoOrderItem.calculateSubtotal(qty, rate, gst, gstType: gstType);

  double get gstAmount =>
      ExpoOrderItem.calculateGstAmount(qty, rate, gst, gstType: gstType);

  static String formatGstNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void applyThresholdGst() {
    if (gstThreshold > 0 && gstAboveThreshold > 0) {
      final effective = ExpoOrderItem.effectiveGstRate(
        rate: rate,
        baseGst: baseGst,
        gstThreshold: gstThreshold,
        gstAboveThreshold: gstAboveThreshold,
      );
      final formatted = formatGstNum(effective);
      if (gstController.text.trim() != formatted) {
        gstController.text = formatted;
      }
    }
  }

  void recalculateTotal() {
    total = ExpoOrderItem.calculateTotal(qty, rate, gst, gstType: gstType);
  }

  void dispose() {
    mtcCodeController.dispose();
    itemNameController.dispose();
    descriptionController.dispose();
    qtyController.dispose();
    rateController.dispose();
    gstController.dispose();
  }
}

class _FormStep {
  final String title;
  final IconData icon;
  const _FormStep(this.title, this.icon);
}

class _ExpoOrderFormPageState extends State<ExpoOrderFormPage> {
  final ImagePicker _imagePicker = ImagePicker();

  // --- Multi-page (Google Forms style) navigation ---
  static const List<_FormStep> _steps = [
    _FormStep('Customer Details', Icons.person_pin_rounded),
    _FormStep('Item Details', Icons.inventory_2_rounded),
    _FormStep('Payment', Icons.payment_rounded),
  ];
  int _currentStep = 0;
  final List<GlobalKey<FormState>> _formKeys =
      List.generate(_steps.length, (_) => GlobalKey<FormState>());

  // Auto-fetched date (read-only)
  final DateTime _orderDate = DateTime.now();

  // Order Type selected from dialog or preset
  late String _selectedOrderType;

  // Customer Details Controllers
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _placeController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();

  // Booking Delivery Date
  DateTime? _deliveryDate;

  // Stall Delivery Pickup Date
  DateTime? _stallPickupDate;

  // Advance & Balance (for booking / stall delivery)
  final TextEditingController _advanceController = TextEditingController();
  final TextEditingController _cashSplitController = TextEditingController();
  final TextEditingController _onlineSplitController = TextEditingController();

  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _stateFocusNode = FocusNode();
  final FocusNode _districtFocusNode = FocusNode();
  final FocusNode _placeFocusNode = FocusNode();

  // Preferred Branch & Preferred Salesman (Do not auto-select branch)
  List<String> _allBranches = [];
  String? _selectedPreferredBranch;
  List<String> _salesmenForBranch = ['N/A'];
  String _selectedSalesman = 'N/A';
  bool _isLoadingBranches = true;

  // Payment Selection: Cash, UPI, UPI + Cash, Bank, Bank + Cash
  String _selectedPaymentMode = 'Cash';
  File? _paymentProofFile;
  String? _existingPaymentProofUrl;

  // Item Details
  final List<_ItemRowData> _items = [];
  bool _isSaving = false;
  late String _draftId;

  @override
  void initState() {
    super.initState();
    _draftId = widget.initialDraft?.id ??
        'draft_${DateTime.now().millisecondsSinceEpoch}';
    _selectedOrderType = widget.initialDraft?.orderType ?? widget.initialOrderType;

    if (widget.initialDraft != null) {
      final d = widget.initialDraft!;
      _phoneController.text = d.phone;
      _shopNameController.text = d.shopName;
      _customerNameController.text = d.customerName;
      _placeController.text = d.place;
      _districtController.text = d.district;
      _stateController.text = d.state;
      _selectedPreferredBranch = d.preferredBranch;
      _selectedSalesman = d.preferredSalesman;
      _deliveryDate = d.deliveryDate ??
          (_selectedOrderType == 'Booking'
              ? DateTime.now().add(const Duration(days: 30))
              : null);
      _stallPickupDate = d.stallPickupDate;
      _advanceController.text = d.advanceText == '0' ? '' : d.advanceText;
      _cashSplitController.text = d.cashSplitText == '0' ? '' : d.cashSplitText;
      _onlineSplitController.text =
          d.onlineSplitText == '0' ? '' : d.onlineSplitText;
      _selectedPaymentMode = ExpoOrder.normalizePaymentMode(d.paymentMode);
      if (d.paymentProofPath != null && d.paymentProofPath!.isNotEmpty) {
        final f = File(d.paymentProofPath!);
        if (f.existsSync()) _paymentProofFile = f;
      }
      _currentStep = d.currentStep.clamp(0, _steps.length - 1);

      if (d.items.isNotEmpty) {
        for (final itemMap in d.items) {
          final row = _ItemRowData();
          row.mtcCodeController.text = itemMap['mtcCode'] ?? '';
          row.itemNameController.text = itemMap['itemName'] ?? '';
          row.descriptionController.text = itemMap['description'] ?? '';
          row.qtyController.text = (itemMap['qty'] ?? '').toString();
          row.rateController.text = (itemMap['rate'] ?? '').toString();
          row.gstController.text = (itemMap['gst'] ?? '').toString();
          row.gstType = (itemMap['gstType'] as num?)?.toInt() ?? 0;
          row.baseGst = (itemMap['baseGst'] as num?)?.toDouble() ?? row.gst;
          row.gstAboveThreshold =
              (itemMap['gstAboveThreshold'] as num?)?.toDouble() ?? 0.0;
          row.gstThreshold =
              (itemMap['gstThreshold'] as num?)?.toDouble() ?? 0.0;
          row.isSaved = itemMap['isSaved'] == true;
          final pPath = itemMap['photoPath']?.toString();
          if (pPath != null && pPath.isNotEmpty) {
            final f = File(pPath);
            if (f.existsSync()) row.photoFile = f;
          }
          row.recalculateTotal();
          _items.add(row);
        }
      } else {
        _items.add(_ItemRowData()..recalculateTotal());
      }
    } else {
      if (_selectedOrderType == 'Booking') {
        _deliveryDate = DateTime.now().add(const Duration(days: 30));
      }
      _items.add(_ItemRowData()..recalculateTotal());
    }

    ExpoStatesDistrictsService.instance.init();
    _loadBranches();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _shopNameController.dispose();
    _customerNameController.dispose();
    _placeController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    _advanceController.dispose();
    _cashSplitController.dispose();
    _onlineSplitController.dispose();
    _phoneFocusNode.dispose();
    _stateFocusNode.dispose();
    _districtFocusNode.dispose();
    _placeFocusNode.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _showSnack(String message, {Color? color}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _autofillCustomer(Map<String, dynamic> customer) async {
    FocusScope.of(context).unfocus();
    setState(() {
      final phone = (customer['phone'] ?? '').toString();
      if (_phoneController.text != phone) _phoneController.text = phone;
      _shopNameController.text = customer['shopName'] ?? '';
      _customerNameController.text = customer['customerName'] ?? '';
      _placeController.text = customer['place'] ?? '';
      _districtController.text = customer['district'] ?? '';
      if ((customer['state'] ?? '').toString().isNotEmpty) {
        _stateController.text = customer['state'];
      }
    });

    if (_selectedOrderType != 'Spot Delivery') {
      final branch = (customer['preferredBranch'] ?? '').toString().trim();
      if (branch.isNotEmpty && branch != 'N/A' && _allBranches.contains(branch)) {
        await _onBranchChanged(branch);
        final salesman =
            (customer['preferredSalesman'] ?? '').toString().trim();
        if (salesman.isNotEmpty && mounted) {
          setState(() {
            if (_salesmenForBranch.contains(salesman)) {
              _selectedSalesman = salesman;
            }
          });
        }
      }
    }
  }

  void _clearCustomerDetails() {
    FocusScope.of(context).unfocus();
    setState(() {
      _phoneController.clear();
      _shopNameController.clear();
      _customerNameController.clear();
      _stateController.clear();
      _districtController.clear();
      _placeController.clear();
      _selectedPreferredBranch = null;
      _selectedSalesman = 'N/A';
      _salesmenForBranch = ['N/A'];
    });
    _showSnack('Customer details cleared', color: Colors.blueGrey);
  }

  // --- Items ---

  /// Returns an error message for the item, or null when valid.
  String? _validateItem(_ItemRowData it, int index) {
    if (it.itemNameController.text.trim().isEmpty) {
      return 'Please enter item name for Item #${index + 1}';
    }
    if (it.qty <= 0) {
      return 'Please enter a valid quantity (>0) for Item #${index + 1}';
    }
    return null;
  }

  /// Validates & saves (collapses) every open item. Returns true if all valid.
  bool _saveOpenItems({bool showSuccess = true}) {
    _formKeys[1].currentState?.validate();
    final openIndexes = <int>[
      for (int i = 0; i < _items.length; i++)
        if (!_items[i].isSaved) i,
    ];

    for (final i in openIndexes) {
      final error = _validateItem(_items[i], i);
      if (error != null) {
        _showSnack(error);
        return false;
      }
    }

    if (openIndexes.isNotEmpty) {
      FocusScope.of(context).unfocus();
      setState(() {
        for (final i in openIndexes) {
          _items[i]
            ..recalculateTotal()
            ..isSaved = true;
        }
      });
      if (showSuccess) {
        _showSnack(
          openIndexes.length == 1 ? 'Item saved' : 'Items saved',
          color: primaryGreen,
        );
      }
    } else if (showSuccess) {
      _showSnack('All items are already saved');
    }
    return true;
  }

  void _onAddItemPressed() {
    // Save the current item(s) before opening a new blank one.
    if (!_saveOpenItems(showSuccess: false)) return;
    setState(() {
      _items.add(_ItemRowData()..recalculateTotal());
    });
  }

  void _removeItemRow(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  Future<void> _loadBranches() async {
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      final branches = await cache.getBranches();

      if (mounted) {
        setState(() {
          _allBranches = branches;
          // As explicitly requested: Do not auto select any branch in preferred branch
          _selectedPreferredBranch = null;
        });
      }
    } catch (e) {
      debugPrint('Error loading branches: $e');
    } finally {
      if (mounted) setState(() => _isLoadingBranches = false);
    }
  }

  Future<void> _onBranchChanged(String? newBranch) async {
    if (newBranch == null) return;
    setState(() {
      _selectedPreferredBranch = newBranch;
    });

    final salesmen =
        await ExpoService.instance.getSalesmenNamesForBranch(newBranch);
    if (mounted) {
      setState(() {
        _salesmenForBranch = salesmen;
        _selectedSalesman = 'N/A';
      });
    }
  }

  // --- MTC Code Automatic Lookup ---
  Future<void> _onMtcCodeSubmitted(_ItemRowData item) async {
    final code = item.mtcCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() => item.isFetchingMtc = true);
    try {
      final details =
          await ExpoService.instance.fetchItemDetailsByMtcCode(code);
      if (details != null && mounted) {
        setState(() {
          if (details['mtcCode'] != null &&
              details['mtcCode'].toString().isNotEmpty) {
            item.mtcCodeController.text = details['mtcCode']
                .toString()
                .replaceFirst(RegExp(r'^MTC', caseSensitive: false), '')
                .trim();
          }
          if (details['itemName'] != null &&
              details['itemName'].toString().isNotEmpty) {
            item.itemNameController.text = details['itemName'].toString();
          }
          if (details['rate'] != null && (details['rate'] as num) > 0) {
            item.rateController.text =
                _ItemRowData.formatGstNum((details['rate'] as num).toDouble());
          }
          item.gstType = (details['gstType'] as num?)?.toInt() ?? 0;
          item.baseGst = (details['gst'] as num?)?.toDouble() ?? 18.0;
          item.gstAboveThreshold =
              (details['gstAboveThreshold'] as num?)?.toDouble() ?? 0.0;
          item.gstThreshold =
              (details['gstThreshold'] as num?)?.toDouble() ?? 0.0;

          final effectiveGst = ExpoOrderItem.effectiveGstRate(
            rate: item.rate,
            baseGst: item.baseGst,
            gstThreshold: item.gstThreshold,
            gstAboveThreshold: item.gstAboveThreshold,
          );
          item.gstController.text = _ItemRowData.formatGstNum(effectiveGst);
          item.recalculateTotal();
        });
      }
    } catch (e) {
      debugPrint('Error fetching MTC code details: $e');
    } finally {
      if (mounted) setState(() => item.isFetchingMtc = false);
    }
  }

  // --- Image Pickers for Item & Payment Proof ---
  Future<File> _compressImageFile(File file) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String targetPath =
          '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final XFile? compressedXFile =
          await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 55, // Optimized balance of quality and small file size (< 100-150KB)
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.jpeg,
      );

      if (compressedXFile != null) {
        final compressedFile = File(compressedXFile.path);
        if (compressedFile.existsSync()) {
          return compressedFile;
        }
      }
    } catch (e) {
      debugPrint('Error compressing image: $e');
    }
    return file;
  }

  Future<void> _pickImageForItem(_ItemRowData item) async {
    final ImageSource? source = await _showImageSourceDialog(
      title: 'Item Photo',
      subtitle: 'Take a photo or choose from gallery',
    );
    if (source == null) return;

    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 60,
      );
      if (picked != null && mounted) {
        final compressed = await _compressImageFile(File(picked.path));
        if (mounted) {
          setState(() {
            item.photoFile = compressed;
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking item image: $e');
    }
  }

  Future<void> _pickPaymentProof() async {
    final ImageSource? source = await _showImageSourceDialog(
      title: 'Payment Proof',
      subtitle: 'Upload receipt from gallery or take photo now',
    );
    if (source == null) return;

    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 60,
      );
      if (picked != null && mounted) {
        final compressed = await _compressImageFile(File(picked.path));
        if (mounted) {
          setState(() {
            _paymentProofFile = compressed;
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking payment proof: $e');
    }
  }

  Future<ImageSource?> _showImageSourceDialog({
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: isDark ? const Color(0xFF0F243E) : Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: primaryBlue),
                ),
                title: const Text('Take Photo Now',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.photo_library_rounded, color: primaryGreen),
                ),
                title: const Text('Choose from Gallery',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Totals ---

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  double get _subtotal {
    double sum = 0.0;
    for (final it in _items) {
      sum += it.subtotalAmount;
    }
    return sum;
  }

  double get _totalGst {
    double sum = 0.0;
    for (final it in _items) {
      sum += it.gstAmount;
    }
    return sum;
  }

  /// Total before round-off (2 decimals).
  double get _grandTotal => _round2(_subtotal + _totalGst);

  /// Final payable amount (Round Off removed per requirement).
  double get _netTotal => _grandTotal;

  /// Round-off kept at 0.0 (feature removed from order entry).
  double get _roundOff => 0.0;

  double get _advanceAmount {
    if (ExpoOrder.modeIsSplit(_selectedPaymentMode)) {
      if (_selectedOrderType == 'Spot Delivery') return _netTotal;
      final splitTotal = _round2(_cashSplitAmount + _onlineSplitAmount);
      return splitTotal.clamp(0.0, _netTotal);
    }
    if (_selectedOrderType == 'Spot Delivery') return _netTotal;
    final val = double.tryParse(_advanceController.text.trim()) ?? 0.0;
    return val.clamp(0.0, _netTotal);
  }

  double get _balanceAmount {
    if (_selectedOrderType == 'Spot Delivery') return 0.0;
    final bal = _netTotal - _advanceAmount;
    return bal < 0 ? 0.0 : _round2(bal);
  }

  double get _effectivePaidNow =>
      _selectedOrderType == 'Spot Delivery' ? _netTotal : _advanceAmount;

  double get _cashSplitAmount =>
      _round2(double.tryParse(_cashSplitController.text.trim()) ?? 0.0);

  double get _onlineSplitAmount =>
      _round2(double.tryParse(_onlineSplitController.text.trim()) ?? 0.0);

  String _formatEditableMoney(double v) {
    final r = _round2(v);
    if (r <= 0) return '';
    return (r - r.roundToDouble()).abs() < 0.005
        ? r.round().toString()
        : r.toStringAsFixed(2);
  }

  void _syncReadOnlySplitTotal() {
    final totalSplit = _round2(_cashSplitAmount + _onlineSplitAmount);
    _advanceController.text = _formatEditableMoney(totalSplit);
  }

  void _selectPaymentMode(String mode) {
    setState(() {
      _selectedPaymentMode = mode;
      if (!ExpoOrder.modeRequiresReceipt(mode)) {
        _paymentProofFile = null;
      }
      if (ExpoOrder.modeIsSplit(mode)) {
        _syncReadOnlySplitTotal();
      }
    });
  }

  void _onTotalAdvanceChanged(String raw) {
    setState(() {});
  }

  void _onCashSplitChanged(String raw) {
    setState(() => _syncReadOnlySplitTotal());
  }

  void _onOnlineSplitChanged(String raw) {
    setState(() => _syncReadOnlySplitTotal());
  }

  int get _totalQty {
    int sum = 0;
    for (final it in _items) {
      sum += it.qty;
    }
    return sum;
  }

  // --- Step navigation ---

  bool _validateStep(int step) {
    final form = _formKeys[step].currentState;
    switch (step) {
      case 0:
        if (form != null && !form.validate()) return false;

        // Strictly enforce State validation against database/cached list
        final stateInput = _stateController.text.trim();
        final districtInput = _districtController.text.trim();

        if (!ExpoStatesDistrictsService.instance.isValidState(stateInput)) {
          _showSnack('Please select a valid State from the suggestions list');
          return false;
        }

        // Strictly enforce District validation against state's allowed districts
        if (!ExpoStatesDistrictsService.instance.isValidDistrict(stateInput, districtInput)) {
          _showSnack('Please select a valid District belonging to $stateInput from the suggestions list');
          return false;
        }

        if (_selectedOrderType != 'Spot Delivery' &&
            (_selectedPreferredBranch == null ||
                _selectedPreferredBranch!.isEmpty)) {
          _showSnack('Please select preferred branch');
          return false;
        }
        return true;
      case 1:
        if (_items.isEmpty) {
          _showSnack('Please add at least one item');
          return false;
        }
        return _saveOpenItems(showSuccess: false);
      case 2:
        if (form != null && !form.validate()) return false;
        if (ExpoOrder.modeIsSplit(_selectedPaymentMode)) {
          final totalSplit = _round2(_cashSplitAmount + _onlineSplitAmount);
          final label = ExpoOrder.onlineLabelForMode(_selectedPaymentMode);
          if (_selectedOrderType == 'Spot Delivery') {
            if ((totalSplit - _netTotal).abs() > 0.05) {
              _showSnack(
                'Total Advance (Cash + $label) must equal Net Total (₹${_netTotal.toStringAsFixed(2)}) for Spot Delivery',
              );
              return false;
            }
          } else if (totalSplit > _netTotal + 0.01) {
            _showSnack(
              'Total Advance (Cash + $label) cannot exceed Net Total',
            );
            return false;
          }
        } else if (_selectedOrderType != 'Spot Delivery') {
          final advanceEntered =
              double.tryParse(_advanceController.text.trim()) ?? 0.0;
          if (advanceEntered > _netTotal + 0.01) {
            _showSnack('Advance amount cannot exceed Net Total');
            return false;
          }
        }
        return true;
    }
    return true;
  }

  void _goNext() {
    FocusScope.of(context).unfocus();
    if (!_validateStep(_currentStep)) return;
    if (_currentStep < _steps.length - 1) {
      setState(() {
        _currentStep++;
        if (_currentStep == 2 &&
            ExpoOrder.modeIsSplit(_selectedPaymentMode)) {
          _syncReadOnlySplitTotal();
        }
      });
    }
  }

  bool get _hasDraftContent {
    if (_phoneController.text.trim().isNotEmpty) return true;
    if (_shopNameController.text.trim().isNotEmpty) return true;
    if (_customerNameController.text.trim().isNotEmpty) return true;
    if (_placeController.text.trim().isNotEmpty) return true;
    if (_districtController.text.trim().isNotEmpty) return true;
    if (_stateController.text.trim().isNotEmpty) return true;
    if (_selectedPreferredBranch != null && _selectedPreferredBranch!.isNotEmpty) return true;
    if (_selectedSalesman.isNotEmpty && _selectedSalesman != 'N/A') return true;
    if (_advanceController.text.trim().isNotEmpty && _advanceController.text.trim() != '0') return true;
    if (_cashSplitController.text.trim().isNotEmpty && _cashSplitController.text.trim() != '0') return true;
    if (_onlineSplitController.text.trim().isNotEmpty && _onlineSplitController.text.trim() != '0') return true;
    if (_paymentProofFile != null) return true;
    if (_items.any((it) =>
        it.itemNameController.text.trim().isNotEmpty ||
        it.mtcCodeController.text.trim().isNotEmpty ||
        it.qtyController.text.trim().isNotEmpty ||
        it.rateController.text.trim().isNotEmpty ||
        it.photoFile != null)) {
      return true;
    }
    return false;
  }

  Future<void> _saveAsDraft({bool showNotice = false}) async {
    if (!_hasDraftContent) return;

    final draft = ExpoOrderDraft(
      id: _draftId,
      exhibitionId: widget.exhibition.id,
      exhibitionName: widget.exhibition.name,
      orderType: _selectedOrderType,
      phone: _phoneController.text.trim(),
      shopName: _shopNameController.text.trim(),
      customerName: _customerNameController.text.trim(),
      place: _placeController.text.trim(),
      district: _districtController.text.trim(),
      state: _stateController.text.trim(),
      preferredBranch: _selectedPreferredBranch,
      preferredSalesman: _selectedSalesman,
      deliveryDate: _deliveryDate,
      stallPickupDate: _stallPickupDate,
      advanceText: _advanceController.text.trim(),
      cashSplitText: _cashSplitController.text.trim(),
      onlineSplitText: _onlineSplitController.text.trim(),
      paymentMode: _selectedPaymentMode,
      paymentProofPath: _paymentProofFile?.path,
      currentStep: _currentStep,
      items: _items.map((it) {
        return {
          'mtcCode': it.mtcCodeController.text.trim(),
          'itemName': it.itemNameController.text.trim(),
          'description': it.descriptionController.text.trim(),
          'qty': it.qtyController.text.trim(),
          'rate': it.rateController.text.trim(),
          'gst': it.gstController.text.trim(),
          'gstType': it.gstType,
          'baseGst': it.baseGst,
          'gstAboveThreshold': it.gstAboveThreshold,
          'gstThreshold': it.gstThreshold,
          'isSaved': it.isSaved,
          'photoPath': it.photoFile?.path,
        };
      }).toList(),
      updatedAt: DateTime.now(),
    );

    await ExpoDraftService.instance.saveDraft(draft);
    if (showNotice && mounted) {
      _showSnack('Draft saved locally', color: primaryGreen);
    }
  }

  Future<void> _handleBack() async {
    FocusScope.of(context).unfocus();
    if (_currentStep > 0) {
      await _saveAsDraft();
      setState(() => _currentStep--);
      return;
    }

    if (_hasDraftContent) {
      await _saveAsDraft(showNotice: true);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _submitOrder() async {
    FocusScope.of(context).unfocus();
    if (!_validateStep(2)) return;

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();

      // 1. Upload payment proof concurrently if provided to dedicated bucket
      final Future<String?> paymentProofFuture =
          (_paymentProofFile != null &&
                  ExpoOrder.modeRequiresReceipt(_selectedPaymentMode))
              ? ExpoService.instance.uploadFile(
                  _paymentProofFile!,
                  bucketName: ExpoOrder.modeUsesUpiBucket(_selectedPaymentMode)
                      ? ExpoSupabaseConfig.bucketUpiProofs
                      : ExpoSupabaseConfig.bucketBankProofs,
                )
              : Future.value(_existingPaymentProofUrl);

      // 2. Upload item photos concurrently if provided to item bucket
      final List<Future<String?>> itemPhotoFutures = _items.map((it) {
        if (it.photoFile != null) {
          return ExpoService.instance.uploadFile(
            it.photoFile!,
            bucketName: ExpoSupabaseConfig.bucketItemPhotos,
          );
        }
        return Future.value(it.existingPhotoUrl);
      }).toList();

      // Wait for all uploads simultaneously
      final uploadResults = await Future.wait([
        paymentProofFuture,
        ...itemPhotoFutures,
      ]);

      final paymentProofUrl = uploadResults[0];
      final itemPhotoUrls = uploadResults.sublist(1);

      // 3. Build items list
      final List<ExpoOrderItem> orderItems = [];
      for (int i = 0; i < _items.length; i++) {
        final it = _items[i];
        orderItems.add(
          ExpoOrderItem(
            mtcCode: it.mtcCodeController.text.trim(),
            itemName: it.itemNameController.text.trim(),
            description: it.descriptionController.text.trim(),
            qty: it.qty,
            rate: it.rate,
            gst: it.gst,
            gstType: it.gstType,
            total: ExpoOrderItem.calculateTotal(
              it.qty,
              it.rate,
              it.gst,
              gstType: it.gstType,
            ),
            photoUrl: itemPhotoUrls[i],
          ),
        );
      }

      final isSpot = _selectedOrderType == 'Spot Delivery';
      final double paidNow = isSpot ? _netTotal : _advanceAmount;
      final String normalizedMode =
          ExpoOrder.normalizePaymentMode(_selectedPaymentMode);
      final double savedCashAmount;
      final double savedOnlineAmount;
      if (normalizedMode == 'Cash') {
        savedCashAmount = _round2(paidNow);
        savedOnlineAmount = 0.0;
      } else if (ExpoOrder.modeIsSplit(normalizedMode)) {
        savedCashAmount = _cashSplitAmount;
        savedOnlineAmount = _onlineSplitAmount;
      } else {
        savedCashAmount = 0.0;
        savedOnlineAmount = _round2(paidNow);
      }

      final newOrder = ExpoOrder(
        id: '',
        exhibitionId: widget.exhibition.id,
        exhibitionName: widget.exhibition.name,
        orderType: _selectedOrderType,
        orderDate: _orderDate,
        shopName: _shopNameController.text.trim(),
        customerName: _customerNameController.text.trim(),
        place: _placeController.text.trim(),
        district: _districtController.text.trim(),
        state: _stateController.text.trim(),
        phone: _phoneController.text.trim(),
        preferredBranch:
            isSpot ? 'N/A' : (_selectedPreferredBranch ?? 'N/A'),
        preferredSalesman: isSpot ? 'N/A' : _selectedSalesman,
        items: orderItems,
        subtotal: _round2(_subtotal),
        totalGst: _round2(_totalGst),
        roundOff: _roundOff,
        totalAmount: _netTotal,
        totalQty: _totalQty,
        advanceAmount: paidNow,
        balanceAmount: isSpot ? 0.0 : _balanceAmount,
        status: 'Pending Verification',
        paymentMode: normalizedMode,
        cashAmount: savedCashAmount,
        onlineAmount: savedOnlineAmount,
        paymentProofUrl: paymentProofUrl,
        deliveryDate: _selectedOrderType == 'Booking' ? _deliveryDate : null,
        stallPickupDate:
            _selectedOrderType == 'Stall Delivery' ? _stallPickupDate : null,
        isConvertedToBooking: false,
        stallPickupStatus:
            _selectedOrderType == 'Stall Delivery' ? 'Pending Pickup' : null,
        createdUserId: user?.uid ?? '',
        createdUserName: cache.username ?? user?.displayName ?? 'Sales User',
        createdUserBranch: cache.branch ?? '',
        createdAt: DateTime.now(),
      );

      await ExpoService.instance.createOrder(newOrder);
      await ExpoDraftService.instance.deleteDraft(_draftId);

      if (mounted) {
        _showSnack('Order submitted successfully!', color: primaryGreen);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to submit order: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Widget stepBody;
    switch (_currentStep) {
      case 0:
        stepBody = _buildCustomerStep(isDark);
        break;
      case 1:
        stepBody = _buildItemsStep(isDark);
        break;
      default:
        stepBody = _buildPaymentStep(isDark);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSaving) _handleBack();
      },
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New Expo Order',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              Text(
                '${widget.exhibition.name}  •  $_selectedOrderType',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            _buildStepHeader(isDark),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: SingleChildScrollView(
                  key: ValueKey<int>(_currentStep),
                  padding: const EdgeInsets.all(16),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Form(
                    key: _formKeys[_currentStep],
                    child: stepBody,
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomNav(isDark),
      ),
    );
  }

  /// Google-Forms-like section header with progress.
  Widget _buildStepHeader(bool isDark) {
    final step = _steps[_currentStep];
    return Container(
      color: isDark ? const Color(0xFF0F243E) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(step.icon, color: primaryBlue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Text(
                'Section ${_currentStep + 1} of ${_steps.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (int i = 0; i < _steps.length; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < _currentStep
                          ? primaryGreen
                          : (i == _currentStep
                              ? primaryBlue
                              : (isDark
                                  ? Colors.white12
                                  : Colors.black.withValues(alpha: 0.08))),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (i < _steps.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    final isLast = _currentStep == _steps.length - 1;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F243E) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _handleBack,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: primaryBlue),
                    label: const Text(
                      'Back',
                      style: TextStyle(
                        color: primaryBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: primaryBlue, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed:
                      _isSaving ? null : (isLast ? _submitOrder : _goNext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLast ? primaryGreen : primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isLast ? 'Submit Expo Order' : 'Next',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isLast
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 1: Customer Details
  // ---------------------------------------------------------------------------

  Widget _buildCustomerStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildOrderMetaSection(isDark),
        const SizedBox(height: 16),
        _buildCard(
          isDark: isDark,
          title: 'Customer Details',
          icon: Icons.person_pin_rounded,
          trailing: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _clearCustomerDetails,
            icon: const Icon(Icons.clear_all_rounded, size: 16),
            label: const Text(
              'Clear All',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
          ),
          child: Column(
            children: [
              // Phone (first field, searches existing expo customers)
              _buildPhoneAutocomplete(isDark),
              const SizedBox(height: 12),

              // Shop Name
              TextFormField(
                controller: _shopNameController,
                textCapitalization: TextCapitalization.words,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter shop name';
                  }
                  return null;
                },
                decoration: _inputDecoration(
                  label: 'Shop Name',
                  hint: 'Enter shop name',
                  icon: Icons.store_rounded,
                  isDark: isDark,
                ),
              ),
              const SizedBox(height: 12),

              // Customer Name (NO "Optional" label as per AGENTS.md rule)
              TextFormField(
                controller: _customerNameController,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration(
                  label: 'Customer Name',
                  hint: 'Enter customer name',
                  icon: Icons.person_rounded,
                  isDark: isDark,
                ),
              ),
              const SizedBox(height: 12),

              // State
              _buildStateAutocomplete(isDark),
              const SizedBox(height: 12),

              // District & Place (Interchanged: District on left, Place on right)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildDistrictAutocomplete(isDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _placeController,
                      focusNode: _placeFocusNode,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration(
                        label: 'Place',
                        hint: 'Enter place',
                        icon: Icons.place_rounded,
                        isDark: isDark,
                      ),
                    ),
                  ),
                ],
              ),
              if (_selectedOrderType != 'Spot Delivery') ...[
                const SizedBox(height: 12),
                // Preferred Branch (Dropdown - Not auto-selected)
                DropdownButtonFormField<String>(
                  key: ValueKey('branch_$_selectedPreferredBranch'),
                  initialValue: _selectedPreferredBranch,
                  isExpanded: true,
                  items: _allBranches.map((b) {
                    return DropdownMenuItem<String>(
                      value: b,
                      child: Text(b),
                    );
                  }).toList(),
                  onChanged: _onBranchChanged,
                  validator: (val) =>
                      (val == null || val.isEmpty) ? 'Select branch' : null,
                  decoration: _inputDecoration(
                    label: 'Preferred Branch',
                    hint: _isLoadingBranches
                        ? 'Loading branches...'
                        : 'Select branch',
                    icon: Icons.business_rounded,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(height: 12),

                // Preferred Salesman (Dropdown based on branch with N/A)
                DropdownButtonFormField<String>(
                  key: ValueKey(
                      'salesman_${_selectedPreferredBranch}_$_selectedSalesman'),
                  initialValue: _selectedSalesman,
                  isExpanded: true,
                  items: _salesmenForBranch.map((s) {
                    return DropdownMenuItem<String>(
                      value: s,
                      child: Text(s),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedSalesman = val);
                    }
                  },
                  decoration: _inputDecoration(
                    label: 'Preferred Salesman',
                    hint: 'Select salesman',
                    icon: Icons.badge_rounded,
                    isDark: isDark,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneAutocomplete(bool isDark) {
    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: _phoneController,
      focusNode: _phoneFocusNode,
      optionsBuilder: (TextEditingValue textEditingValue) async {
        final query = textEditingValue.text.trim();
        if (query.length < 3) {
          return const Iterable<Map<String, dynamic>>.empty();
        }
        return await ExpoService.instance.searchExpoCustomersByPhone(
          exhibitionName: widget.exhibition.name,
          phoneQuery: query,
        );
      },
      displayStringForOption: (option) => (option['phone'] ?? '').toString(),
      onSelected: (option) => _autofillCustomer(option),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Enter phone number';
            }
            if (val.trim().length != 10) {
              return 'Enter 10 digits';
            }
            return null;
          },
          decoration: _inputDecoration(
            label: 'Phone Number',
            hint: 'Type number to search / auto-fill...',
            icon: Icons.phone_rounded,
            isDark: isDark,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 240,
                maxWidth: 360,
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  final phone = (option['phone'] ?? '').toString();
                  final shop = (option['shopName'] ?? '').toString();
                  final cust = (option['customerName'] ?? '').toString();
                  final place = (option['place'] ?? '').toString();

                  return InkWell(
                    onTap: () => onSelected(option),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                primaryBlue.withValues(alpha: 0.15),
                            child: const Icon(
                              Icons.phone_rounded,
                              size: 16,
                              color: primaryBlue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  phone,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                Text(
                                  [shop, cust, place]
                                      .where((s) => s.isNotEmpty)
                                      .join(' • '),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.touch_app_rounded,
                              size: 16, color: primaryGreen),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStateAutocomplete(bool isDark) {
    return _CachedAutocompleteField(
      controller: _stateController,
      focusNode: _stateFocusNode,
      label: 'State',
      hint: 'Type state name...',
      icon: Icons.map_rounded,
      isDark: isDark,
      optionsBuilder: (query) {
        if (query.trim().isEmpty) return const <String>[];
        return ExpoStatesDistrictsService.instance.filterStates(query);
      },
      onSelected: (selectedState) {
        final normalized =
            ExpoStatesDistrictsService.instance.normalizeState(selectedState);
        _stateController.text = normalized;
        // If current district is invalid for newly selected state, clear it
        if (!ExpoStatesDistrictsService.instance
            .isValidDistrict(normalized, _districtController.text)) {
          _districtController.clear();
        }
        setState(() {});

        // Automatically move to District field and open keyboard
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            FocusScope.of(context).requestFocus(_districtFocusNode);
          }
        });
      },
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          return 'Enter state';
        }
        if (!ExpoStatesDistrictsService.instance.isValidState(val)) {
          return 'Select a valid state from suggestions';
        }
        return null;
      },
    );
  }

  Widget _buildDistrictAutocomplete(bool isDark) {
    return _CachedAutocompleteField(
      controller: _districtController,
      focusNode: _districtFocusNode,
      label: 'District',
      hint: 'Type district name...',
      icon: Icons.location_city_rounded,
      isDark: isDark,
      optionsBuilder: (query) {
        if (query.trim().isEmpty) return const <String>[];
        final stateName = _stateController.text.trim();
        return ExpoStatesDistrictsService.instance.filterDistricts(
          stateName: stateName,
          query: query,
        );
      },
      onSelected: (selectedDistrict) {
        final stateName = _stateController.text.trim();
        final normalized = ExpoStatesDistrictsService.instance
            .normalizeDistrict(stateName, selectedDistrict);
        _districtController.text = normalized;
        setState(() {});

        // Automatically move to Place field and open keyboard
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            FocusScope.of(context).requestFocus(_placeFocusNode);
          }
        });
      },
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          return 'Enter district';
        }
        final stateName = _stateController.text.trim();
        if (!ExpoStatesDistrictsService.instance.isValidDistrict(stateName, val)) {
          return 'Select valid district from suggestions';
        }
        return null;
      },
    );
  }

  /// Read-only order date + order-type specific dates (delivery / pickup).
  Widget _buildOrderMetaSection(bool isDark) {
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(_orderDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Read-only Auto-fetched Date & Order Type
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0F243E)
                : primaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: primaryBlue.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_note_rounded,
                  color: primaryBlue, size: 22),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order Date (Auto-fetched)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedOrderType,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_selectedOrderType == 'Booking') ...[
          const SizedBox(height: 12),
          _buildDateSelector(
            isDark: isDark,
            color: primaryGreen,
            icon: Icons.local_shipping_rounded,
            label: 'Delivery Date',
            placeholder: 'Select Delivery Date',
            value: _deliveryDate,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _deliveryDate ?? DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() => _deliveryDate = picked);
              }
            },
          ),
        ],
        if (_selectedOrderType == 'Stall Delivery') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6F00)
                  .withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF6F00).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFFFF6F00), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Stall Delivery: Customer will pick up from the stall during the exhibition. If not delivered within the exhibition period, it will remain pending as Stall Delivery for reporting.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : const Color(0xFF8C3B00),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildDateSelector(
            isDark: isDark,
            color: const Color(0xFFFF6F00),
            icon: Icons.event_available_rounded,
            label: 'Expected Pickup Date',
            placeholder: 'Select Pickup Date',
            value: _stallPickupDate,
            onTap: () async {
              final first = widget.exhibition.startDate;
              final last = widget.exhibition.endDate;
              final initial = _stallPickupDate ??
                  (DateTime.now().isBefore(last) ? DateTime.now() : first);
              final safeInitial = initial.isBefore(first)
                  ? first
                  : (initial.isAfter(last) ? last : initial);
              final safeLast = last.isBefore(first)
                  ? first.add(const Duration(days: 30))
                  : last;

              final picked = await showDatePicker(
                context: context,
                initialDate: safeInitial,
                firstDate: first,
                lastDate: safeLast,
              );
              if (picked != null) {
                setState(() => _stallPickupDate = picked);
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDateSelector({
    required bool isDark,
    required Color color,
    required IconData icon,
    required String label,
    required String placeholder,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF0F243E)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value != null
                      ? DateFormat('dd MMM yyyy').format(value)
                      : placeholder,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: value != null
                        ? (isDark ? Colors.white : Colors.black87)
                        : color,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.calendar_month_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 2: Item Details
  // ---------------------------------------------------------------------------

  Widget _buildItemsStep(bool isDark) {
    final savedCount = _items.where((it) => it.isSaved).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCard(
          isDark: isDark,
          title: 'Item Details',
          icon: Icons.inventory_2_rounded,
          trailing: savedCount > 0
              ? Text(
                  '$savedCount saved',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryGreen,
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < _items.length; i++)
                _items[i].isSaved
                    ? _buildSavedItemTile(
                        index: i, item: _items[i], isDark: isDark)
                    : _buildItemRowCard(
                        index: i, item: _items[i], isDark: isDark),
              const SizedBox(height: 6),
              // Add Item + Save side by side
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _onAddItemPressed,
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          color: primaryBlue),
                      label: const Text(
                        'Add Item',
                        style: TextStyle(
                          color: primaryBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: primaryBlue, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _saveOpenItems(),
                      icon: const Icon(Icons.save_rounded,
                          color: Colors.white, size: 20),
                      label: const Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Running total preview
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: primaryGreen.withValues(alpha: isDark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Items: ${_items.length}  |  Qty: $_totalQty',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              Text(
                '₹${_grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Widget _buildSavedItemTile({
    required int index,
    required _ItemRowData item,
    required bool isDark,
  }) {
    final code = item.mtcCodeController.text.trim();
    final desc = item.descriptionController.text.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryGreen.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.photoFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                item.photoFile!,
                height: 44,
                width: 44,
                cacheWidth: 160,
                fit: BoxFit.cover,
              ),
            )
          else
            CircleAvatar(
              radius: 22,
              backgroundColor: primaryBlue.withValues(alpha: 0.12),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: primaryBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemNameController.text.trim(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (code.isNotEmpty || desc.isNotEmpty)
                  Text(
                    [if (code.isNotEmpty) 'MTC: $code', if (desc.isNotEmpty) desc]
                        .join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${item.qty} × ₹${_fmtNum(item.rate)}  •  GST ${_fmtNum(item.gst)}% (${item.gstType == 1 ? 'Incl.' : 'Excl.'})',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${item.total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: primaryGreen,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_rounded,
                        size: 18, color: primaryBlue),
                    onPressed: () => setState(() => item.isSaved = false),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (_items.length > 1)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 18, color: Colors.redAccent),
                      onPressed: () => _removeItemRow(index),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 3: Payment (Summary with round off → Payment Mode → Advance)
  // ---------------------------------------------------------------------------

  Widget _buildPaymentStep(bool isDark) {
    final mutedStyle = TextStyle(
      fontSize: 13,
      color: isDark ? Colors.white70 : Colors.black87,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Order Summary with Round Off
        _buildCard(
          isDark: isDark,
          title: 'Order Summary',
          icon: Icons.receipt_long_rounded,
          child: Column(
            children: [
              _summaryRow(
                'Total Items: ${_items.length}  |  Total Qty: $_totalQty',
                '',
                style: mutedStyle.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _summaryRow('Subtotal', '₹${_subtotal.toStringAsFixed(2)}',
                  style: mutedStyle),
              const SizedBox(height: 6),
              _summaryRow(
                'GST Total',
                '+ ₹${_totalGst.toStringAsFixed(2)}',
                style: mutedStyle,
                valueStyle: const TextStyle(
                  fontSize: 13,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Net Total',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '₹${_netTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Balance',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  Text(
                    '₹${_balanceAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _balanceAmount > 0
                          ? const Color(0xFFE65100)
                          : primaryGreen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Payment Mode
        _buildCard(
          isDark: isDark,
          title: 'Payment Mode',
          icon: Icons.payment_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildPaymentOptionChip(
                      mode: 'Cash',
                      label: '1. Cash',
                      icon: Icons.money_rounded,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPaymentOptionChip(
                      mode: 'UPI',
                      label: '2. UPI',
                      icon: Icons.qr_code_2_rounded,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPaymentOptionChip(
                      mode: 'UPI + Cash',
                      label: '3. UPI + Cash',
                      icon: Icons.qr_code_scanner_rounded,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildPaymentOptionChip(
                      mode: 'Bank',
                      label: '4. Bank',
                      icon: Icons.account_balance_rounded,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPaymentOptionChip(
                      mode: 'Bank + Cash',
                      label: '5. Bank + Cash',
                      icon: Icons.account_balance_wallet_rounded,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),

              // Upload receipt for UPI, UPI + Cash, Bank, Bank + Cash
              if (ExpoOrder.modeRequiresReceipt(_selectedPaymentMode)) ...[
                const SizedBox(height: 14),
                _buildPaymentProofSection(isDark),
              ],
            ],
          ),
        ),

        // 3. Advance / Split Payment & Balance
        if (_selectedOrderType != 'Spot Delivery' ||
            ExpoOrder.modeIsSplit(_selectedPaymentMode)) ...[
          const SizedBox(height: 16),
          _buildCard(
            isDark: isDark,
            title: ExpoOrder.modeIsSplit(_selectedPaymentMode)
                ? (_selectedOrderType == 'Spot Delivery'
                    ? 'Split Payment Breakdown'
                    : 'Total Advance & Split Payment')
                : 'Advance & Balance',
            icon: Icons.account_balance_wallet_rounded,
            child: _buildAdvanceSection(isDark),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    required TextStyle style,
    TextStyle? valueStyle,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: style)),
        if (value.isNotEmpty) Text(value, style: valueStyle ?? style),
      ],
    );
  }

  Widget _buildPaymentProofSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primaryBlue.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  color: primaryBlue, size: 20),
              const SizedBox(width: 8),
              Text(
                '$_selectedPaymentMode Receipt / Proof',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_paymentProofFile != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _paymentProofFile!,
                height: 140,
                width: double.infinity,
                cacheWidth: 600,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _pickPaymentProof,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Change Photo'),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _paymentProofFile = null);
                  },
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 16),
                  label: const Text('Remove',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: _pickPaymentProof,
              icon: const Icon(Icons.add_a_photo_rounded, color: primaryBlue),
              label: Text(
                'Upload $_selectedPaymentMode Receipt',
                style: const TextStyle(
                  color: primaryBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: primaryBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdvanceSection(bool isDark) {
    final bool isSpot = _selectedOrderType == 'Spot Delivery';
    final bool isSplit = ExpoOrder.modeIsSplit(_selectedPaymentMode);
    final String onlineLabel =
        ExpoOrder.onlineLabelForMode(_selectedPaymentMode);
    final InputDecoration fieldDeco = InputDecoration(
      hintText: '0.00',
      isDense: true,
      filled: true,
      fillColor: isDark ? const Color(0xFF132847) : const Color(0xFFF1F5F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
    final List<TextInputFormatter> numFormatters = [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isSpot || isSplit) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSplit ? 'Total Advance (₹)' : 'Advance Amount (₹)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _advanceController,
                      readOnly: isSplit,
                      keyboardType: isSplit
                          ? TextInputType.none
                          : const TextInputType.numberWithOptions(
                              decimal: true),
                      inputFormatters: isSplit ? null : numFormatters,
                      onChanged: isSplit ? null : _onTotalAdvanceChanged,
                      decoration: fieldDeco.copyWith(
                        prefixIcon:
                            const Icon(Icons.payments_outlined, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isSpot ? 'Net Total' : 'Balance Amount',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: (!isSpot && _balanceAmount > 0)
                            ? const Color(0xFFE65100)
                                .withValues(alpha: isDark ? 0.2 : 0.1)
                            : primaryGreen.withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (!isSpot && _balanceAmount > 0)
                              ? const Color(0xFFE65100).withValues(alpha: 0.4)
                              : primaryGreen.withValues(alpha: 0.4),
                        ),
                      ),
                      alignment: Alignment.centerRight,
                      child: Text(
                        isSpot
                            ? '₹${_netTotal.toStringAsFixed(2)}'
                            : '₹${_balanceAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: (!isSpot && _balanceAmount > 0)
                              ? const Color(0xFFE65100)
                              : primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (isSplit) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash (₹)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _cashSplitController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: numFormatters,
                      onChanged: _onCashSplitChanged,
                      decoration: fieldDeco.copyWith(
                        prefixIcon: const Icon(Icons.money_rounded, size: 19),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$onlineLabel (₹)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _onlineSplitController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: numFormatters,
                      onChanged: _onOnlineSplitChanged,
                      decoration: fieldDeco.copyWith(
                        prefixIcon: Icon(
                          onlineLabel == 'UPI'
                              ? Icons.qr_code_2_rounded
                              : Icons.account_balance_rounded,
                          size: 19,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: isDark ? Colors.white54 : Colors.black45),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isSplit
                      ? 'Split: Cash ₹${_cashSplitAmount.toStringAsFixed(2)} + $onlineLabel ₹${_onlineSplitAmount.toStringAsFixed(2)} = ₹${_round2(_cashSplitAmount + _onlineSplitAmount).toStringAsFixed(2)}.${isSpot ? ' Net Total: ₹${_netTotal.toStringAsFixed(2)}.' : ' Balance due: ₹${_balanceAmount.toStringAsFixed(2)}.'}'
                      : (_advanceAmount > 0
                          ? 'Advance of ₹${_advanceAmount.toStringAsFixed(2)} paid via $_selectedPaymentMode. Balance due: ₹${_balanceAmount.toStringAsFixed(2)}.'
                          : 'No advance paid. Full balance due on delivery.'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentOptionChip({
    required String mode,
    required String label,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _selectedPaymentMode == mode;

    return InkWell(
      onTap: () => _selectPaymentMode(mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryBlue
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryBlue : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : primaryBlue,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRowCard({
    required int index,
    required _ItemRowData item,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row Header: Item #, Photo status, and Delete Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Item #${index + 1}',
                  style: const TextStyle(
                    color: primaryBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        item.mtcCodeController.clear();
                        item.itemNameController.clear();
                        item.descriptionController.clear();
                        item.qtyController.clear();
                        item.rateController.clear();
                        item.gstController.clear();
                        item.gstType = 0;
                        item.baseGst = 0.0;
                        item.gstAboveThreshold = 0.0;
                        item.gstThreshold = 0.0;
                        item.photoFile = null;
                        item.existingPhotoUrl = null;
                        item.recalculateTotal();
                      });
                    },
                    icon: const Icon(Icons.clear_all_rounded,
                        size: 16, color: Colors.orange),
                    label: const Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: const Size(44, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  // Button to take photo for each item (not mandatory)
                  TextButton.icon(
                    onPressed: () => _pickImageForItem(item),
                    icon: Icon(
                      item.photoFile != null
                          ? Icons.check_circle_rounded
                          : Icons.add_a_photo_outlined,
                      size: 16,
                      color: item.photoFile != null
                          ? primaryGreen
                          : primaryBlue,
                    ),
                    label: Text(
                      item.photoFile != null ? 'Photo Added' : 'Add Photo',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: item.photoFile != null
                            ? primaryGreen
                            : primaryBlue,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: const Size(50, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (_items.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent, size: 20),
                      onPressed: () => _removeItemRow(index),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ],
          ),
          if (item.photoFile != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    item.photoFile!,
                    height: 50,
                    width: 50,
                    cacheWidth: 160,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => item.photoFile = null),
                  child: const Text('Remove Photo',
                      style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // MTC Code & Item Name
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: item.mtcCodeController,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _onMtcCodeSubmitted(item),
                  decoration: _inputDecoration(
                    label: 'MTC CODE',
                    hint: 'Code',
                    isDark: isDark,
                    dense: true,
                    suffixIcon: item.isFetchingMtc
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search_rounded,
                                size: 18, color: primaryBlue),
                            tooltip: 'Lookup Item Details',
                            onPressed: () => _onMtcCodeSubmitted(item),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: item.itemNameController,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Enter name';
                    }
                    return null;
                  },
                  decoration: _inputDecoration(
                    label: 'ITEM NAME',
                    hint: 'Item name',
                    isDark: isDark,
                    dense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Description
          TextFormField(
            controller: item.descriptionController,
            decoration: _inputDecoration(
              label: 'DESCRIPTION',
              hint: 'Item description',
              isDark: isDark,
              dense: true,
            ),
          ),
          const SizedBox(height: 8),

          // QTY, RATE, GST (in percentage)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.qtyController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) {
                    setState(() {
                      item.recalculateTotal();
                    });
                  },
                  decoration: _inputDecoration(
                    label: 'QTY',
                    hint: 'Enter qty',
                    isDark: isDark,
                    dense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item.rateController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    setState(() {
                      item.applyThresholdGst();
                      item.recalculateTotal();
                    });
                  },
                  decoration: _inputDecoration(
                    label: 'RATE (₹)',
                    hint: 'Enter rate',
                    isDark: isDark,
                    dense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item.gstController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    setState(() {
                      if (item.gstThreshold <= 0) {
                        item.baseGst = item.gst;
                      }
                      item.recalculateTotal();
                    });
                  },
                  decoration: _inputDecoration(
                    label: 'GST (%)',
                    hint: 'Enter GST',
                    isDark: isDark,
                    dense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // GST Type badge (EXCL / INCL) & Threshold Rule info
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    item.gstType = item.gstType == 0 ? 1 : 0;
                    item.recalculateTotal();
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (item.gstType == 1 ? primaryBlue : primaryGreen)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (item.gstType == 1 ? primaryBlue : primaryGreen)
                          .withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.gstType == 1
                            ? Icons.check_box_rounded
                            : Icons.add_box_outlined,
                        size: 13,
                        color: item.gstType == 1 ? primaryBlue : primaryGreen,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.gstType == 1
                            ? 'INCL (GST Included in Rate)'
                            : 'EXCL (GST Extra)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: item.gstType == 1 ? primaryBlue : primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (item.gstThreshold > 0 && item.gstAboveThreshold > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (item.rate > item.gstThreshold
                            ? const Color(0xFFE65100)
                            : primaryBlue)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (item.rate > item.gstThreshold
                              ? const Color(0xFFE65100)
                              : primaryBlue)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Rate > ₹${_fmtNum(item.gstThreshold)} → ${_fmtNum(item.gstAboveThreshold)}% GST',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: item.rate > item.gstThreshold
                          ? const Color(0xFFE65100)
                          : (isDark ? Colors.white70 : primaryBlue),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Item Total Calculation
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.gstType == 1
                      ? 'Item Total (GST Incl.):'
                      : 'Item Total (incl. GST):',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '₹${item.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: primaryGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required bool isDark,
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      color: isDark ? const Color(0xFF0F243E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primaryBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    IconData? icon,
    Widget? suffixIcon,
    required bool isDark,
    bool dense = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon:
          icon != null ? Icon(icon, color: primaryBlue, size: 20) : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : const Color(0xFFF1F5F9),
      isDense: dense,
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}

/// Dedicated fast autocomplete field for locally cached States & Districts.
/// Instant zero-lag lookup, shows suggestions after the 1st character.
/// Enforces strict selection from predefined suggestions (custom text disallowed).
class _CachedAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final bool isDark;
  final List<String> Function(String query) optionsBuilder;
  final ValueChanged<String> onSelected;
  final FormFieldValidator<String>? validator;

  const _CachedAutocompleteField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    required this.isDark,
    required this.optionsBuilder,
    required this.onSelected,
    this.validator,
  });

  @override
  State<_CachedAutocompleteField> createState() =>
      _CachedAutocompleteFieldState();
}

class _CachedAutocompleteFieldState extends State<_CachedAutocompleteField> {
  List<String> _currentOptions = [];
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      _removeOverlay();
    } else if (widget.controller.text.trim().isNotEmpty) {
      _search(widget.controller.text.trim());
    }
  }

  void _onTextChanged() {
    if (!widget.focusNode.hasFocus) return;

    final query = widget.controller.text.trim();
    // Rule: Only after the first letter (query.length >= 1) show suggestions
    if (query.isEmpty) {
      _removeOverlay();
      return;
    }

    _search(query);
  }

  void _search(String query) {
    if (!mounted) return;
    final results = widget.optionsBuilder(query);
    _currentOptions = results;
    if (results.isNotEmpty && widget.focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    if (!mounted || _currentOptions.isEmpty) return;

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final isDark = widget.isDark;
        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 6),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: _currentOptions.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                  itemBuilder: (context, index) {
                    final item = _currentOptions[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        widget.onSelected(item);
                        _removeOverlay();
                        widget.focusNode.unfocus();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              widget.icon,
                              size: 16,
                              color: primaryBlue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_outward_rounded,
                              size: 14,
                              color: primaryGreen,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        textCapitalization: TextCapitalization.words,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon, color: primaryBlue, size: 20),
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    widget.controller.clear();
                    _removeOverlay();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: widget.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFF1F5F9),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

