import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../Navigation/user_cache_service.dart';
import '../expo_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class ExpoOrderFormPage extends StatefulWidget {
  final Exhibition exhibition;
  final String initialOrderType;

  const ExpoOrderFormPage({
    super.key,
    required this.exhibition,
    this.initialOrderType = 'Spot Delivery',
  });

  @override
  State<ExpoOrderFormPage> createState() => _ExpoOrderFormPageState();
}

class _ItemRowData {
  final TextEditingController mtcCodeController = TextEditingController();
  final TextEditingController itemNameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController qtyController = TextEditingController(text: '1');
  final TextEditingController rateController = TextEditingController(text: '0');
  final TextEditingController gstController = TextEditingController(text: '18');

  File? photoFile;
  String? existingPhotoUrl;
  bool isFetchingMtc = false;
  double total = 0.0;

  void recalculateTotal() {
    final qty = int.tryParse(qtyController.text.trim()) ?? 0;
    final rate = double.tryParse(rateController.text.trim()) ?? 0.0;
    final gst = double.tryParse(gstController.text.trim()) ?? 0.0;
    total = ExpoOrderItem.calculateTotal(qty, rate, gst);
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

class _ExpoOrderFormPageState extends State<ExpoOrderFormPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  // Auto-fetched date (read-only)
  final DateTime _orderDate = DateTime.now();

  // Order Type selected from dialog or preset
  late String _selectedOrderType;

  // Customer Details Controllers
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _placeController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _stateController =
      TextEditingController(text: 'Kerala');
  final TextEditingController _phoneController = TextEditingController();

  // Booking Delivery Date
  DateTime? _deliveryDate;

  // Stall Delivery Pickup Date
  DateTime? _stallPickupDate;

  // Advance & Balance (for booking / stall delivery)
  final TextEditingController _advanceController =
      TextEditingController(text: '0');

  final FocusNode _shopFocusNode = FocusNode();

  // Preferred Branch & Preferred Salesman (Do not auto-select branch)
  List<String> _allBranches = [];
  String? _selectedPreferredBranch;
  List<String> _salesmenForBranch = ['N/A'];
  String _selectedSalesman = 'N/A';
  bool _isLoadingBranches = true;

  // Payment Selection: Cash, Bank Transfer, UPI
  String _selectedPaymentMode = 'Cash';
  File? _paymentProofFile;
  String? _existingPaymentProofUrl;

  // Item Details
  final List<_ItemRowData> _items = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedOrderType = widget.initialOrderType;
    _addItemRow();
    _loadBranches();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _customerNameController.dispose();
    _placeController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    _phoneController.dispose();
    _advanceController.dispose();
    _shopFocusNode.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _autofillCustomer(Map<String, dynamic> customer) async {
    setState(() {
      _shopNameController.text = customer['shopName'] ?? '';
      _customerNameController.text = customer['customerName'] ?? '';
      _placeController.text = customer['place'] ?? '';
      _districtController.text = customer['district'] ?? '';
      if ((customer['state'] ?? '').toString().isNotEmpty) {
        _stateController.text = customer['state'];
      }
      _phoneController.text = customer['phone'] ?? '';
    });

    if (_selectedOrderType != 'Spot Delivery') {
      final branch = (customer['preferredBranch'] ?? '').toString().trim();
      if (branch.isNotEmpty) {
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

  void _addItemRow() {
    final newRow = _ItemRowData();
    newRow.recalculateTotal();
    setState(() {
      _items.add(newRow);
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
          if (details['itemName'] != null &&
              details['itemName'].toString().isNotEmpty) {
            item.itemNameController.text = details['itemName'].toString();
          }
          if (details['gst'] != null) {
            item.gstController.text = details['gst'].toString();
          }
          if (details['rate'] != null && details['rate'] > 0) {
            item.rateController.text = details['rate'].toString();
          }
          if (details['description'] != null &&
              details['description'].toString().isNotEmpty) {
            item.descriptionController.text =
                details['description'].toString();
          }
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

  double get _subtotal {
    double sum = 0.0;
    for (final it in _items) {
      final qty = int.tryParse(it.qtyController.text.trim()) ?? 0;
      final rate = double.tryParse(it.rateController.text.trim()) ?? 0.0;
      sum += (qty * rate);
    }
    return sum;
  }

  double get _totalGst {
    double sum = 0.0;
    for (final it in _items) {
      final qty = int.tryParse(it.qtyController.text.trim()) ?? 0;
      final rate = double.tryParse(it.rateController.text.trim()) ?? 0.0;
      final gst = double.tryParse(it.gstController.text.trim()) ?? 0.0;
      sum += (qty * rate) * (gst / 100.0);
    }
    return sum;
  }

  double get _grandTotal => _subtotal + _totalGst;

  double get _advanceAmount {
    if (_selectedOrderType == 'Spot Delivery') return _grandTotal;
    final val = double.tryParse(_advanceController.text.trim()) ?? 0.0;
    return val.clamp(0.0, _grandTotal);
  }

  double get _balanceAmount {
    if (_selectedOrderType == 'Spot Delivery') return 0.0;
    final bal = _grandTotal - _advanceAmount;
    return bal < 0 ? 0.0 : bal;
  }

  int get _totalQty {
    int sum = 0;
    for (final it in _items) {
      sum += int.tryParse(it.qtyController.text.trim()) ?? 0;
    }
    return sum;
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedOrderType != 'Spot Delivery') {
      if (_selectedPreferredBranch == null || _selectedPreferredBranch!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select preferred branch')),
        );
        return;
      }
      final advanceEntered =
          double.tryParse(_advanceController.text.trim()) ?? 0.0;
      if (advanceEntered > _grandTotal) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Advance amount cannot exceed Grand Total'),
          ),
        );
        return;
      }
    }

    // Validate items
    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.itemNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter item name for Item #${i + 1}')),
        );
        return;
      }
      final qty = int.tryParse(it.qtyController.text.trim()) ?? 0;
      if (qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Please enter a valid quantity (>0) for Item #${i + 1}'),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();

      // 1. Upload payment proof concurrently if provided
      final Future<String?> paymentProofFuture = (_paymentProofFile != null)
          ? ExpoService.instance.uploadFile(_paymentProofFile!, 'payment_proofs')
          : Future.value(_existingPaymentProofUrl);

      // 2. Upload item photos concurrently if provided
      final List<Future<String?>> itemPhotoFutures = _items.map((it) {
        if (it.photoFile != null) {
          return ExpoService.instance.uploadFile(it.photoFile!, 'item_photos');
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
        final qty = int.tryParse(it.qtyController.text.trim()) ?? 0;
        final rate = double.tryParse(it.rateController.text.trim()) ?? 0.0;
        final gst = double.tryParse(it.gstController.text.trim()) ?? 0.0;
        final total = ExpoOrderItem.calculateTotal(qty, rate, gst);

        orderItems.add(
          ExpoOrderItem(
            mtcCode: it.mtcCodeController.text.trim(),
            itemName: it.itemNameController.text.trim(),
            description: it.descriptionController.text.trim(),
            qty: qty,
            rate: rate,
            gst: gst,
            total: total,
            photoUrl: itemPhotoUrls[i],
          ),
        );
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
        preferredBranch: _selectedOrderType == 'Spot Delivery'
            ? 'N/A'
            : (_selectedPreferredBranch ?? 'N/A'),
        preferredSalesman: _selectedOrderType == 'Spot Delivery'
            ? 'N/A'
            : _selectedSalesman,
        items: orderItems,
        subtotal: _subtotal,
        totalGst: _totalGst,
        totalAmount: _grandTotal,
        totalQty: _totalQty,
        advanceAmount: _selectedOrderType == 'Spot Delivery'
            ? _grandTotal
            : _advanceAmount,
        balanceAmount:
            _selectedOrderType == 'Spot Delivery' ? 0.0 : _balanceAmount,
        status: 'Pending Verification',
        paymentMode: _selectedPaymentMode,
        paymentProofUrl: paymentProofUrl,
        deliveryDate: _selectedOrderType == 'Booking' ? _deliveryDate : null,
        stallPickupDate:
            _selectedOrderType == 'Stall Delivery' ? _stallPickupDate : null,
        isConvertedToBooking: false,
        stallPickupStatus: _selectedOrderType == 'Stall Delivery'
            ? 'Pending Pickup'
            : null,
        createdUserId: user?.uid ?? '',
        createdUserName: cache.username ?? user?.displayName ?? 'Sales User',
        createdUserBranch: cache.branch ?? '',
        createdAt: DateTime.now(),
      );

      await ExpoService.instance.createOrder(newOrder);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order submitted successfully!'),
            backgroundColor: primaryGreen,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit order: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formattedDate =
        DateFormat('dd MMM yyyy, hh:mm a').format(_orderDate);

    return Scaffold(
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Read-only Auto-fetched Date & Order Type on Top
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
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
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _deliveryDate ??
                          DateTime.now().add(const Duration(days: 3)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _deliveryDate = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F243E)
                          : primaryGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: primaryGreen.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping_rounded,
                            color: primaryGreen, size: 22),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delivery Date',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _deliveryDate != null
                                  ? DateFormat('dd MMM yyyy')
                                      .format(_deliveryDate!)
                                  : 'Select Delivery Date',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _deliveryDate != null
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : primaryGreen,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.calendar_month_rounded,
                            color: primaryGreen, size: 20),
                      ],
                    ),
                  ),
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
                          'Stall Delivery: Customer will pick up from the stall during the exhibition. If not picked up before the exhibition ends, it will convert to a normal booking for branch delivery.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF8C3B00),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final first = widget.exhibition.startDate;
                    final last = widget.exhibition.endDate;
                    final initial = _stallPickupDate ??
                        (DateTime.now().isBefore(last)
                            ? DateTime.now()
                            : first);
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
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F243E)
                          : const Color(0xFFFF6F00).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF6F00).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_available_rounded,
                            color: Color(0xFFFF6F00), size: 22),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Expected Pickup Date',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _stallPickupDate != null
                                  ? DateFormat('dd MMM yyyy')
                                      .format(_stallPickupDate!)
                                  : 'Select Pickup Date',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _stallPickupDate != null
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : const Color(0xFFFF6F00),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.calendar_month_rounded,
                            color: Color(0xFFFF6F00), size: 20),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // 2. Customer Details Section
              _buildCard(
                isDark: isDark,
                title: 'Customer Details',
                icon: Icons.person_pin_rounded,
                child: Column(
                  children: [
                    // Shop Name (with Autocomplete from expo_customers)
                    RawAutocomplete<Map<String, dynamic>>(
                      textEditingController: _shopNameController,
                      focusNode: _shopFocusNode,
                      optionsBuilder: (TextEditingValue textEditingValue) async {
                        final query = textEditingValue.text.trim();
                        if (query.isEmpty) {
                          return const Iterable<Map<String, dynamic>>.empty();
                        }
                        return await ExpoService.instance.searchExpoCustomers(
                          exhibitionName: widget.exhibition.name,
                          query: query,
                        );
                      },
                      displayStringForOption: (option) =>
                          option['shopName'] ?? '',
                      onSelected: (option) => _autofillCustomer(option),
                      fieldViewBuilder: (context, controller, focusNode,
                          onFieldSubmitted) {
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter shop name';
                            }
                            return null;
                          },
                          decoration: _inputDecoration(
                            label: 'Shop Name',
                            hint: 'Type shop name to search/auto-fill...',
                            icon: Icons.store_rounded,
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
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 240,
                                maxWidth: 360,
                              ),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 4),
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  final shop = option['shopName'] ?? '';
                                  final cust = option['customerName'] ?? '';
                                  final phone = option['phone'] ?? '';
                                  final place = option['place'] ?? '';

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
                                            backgroundColor: primaryBlue
                                                .withValues(alpha: 0.15),
                                            child: const Icon(
                                              Icons.store_rounded,
                                              size: 16,
                                              color: primaryBlue,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  shop,
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 13,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                  ),
                                                ),
                                                Text(
                                                  [cust, place, phone]
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
                    ),
                    const SizedBox(height: 12),

                    // Customer Name (NO "Optional" label as per AGENTS.md rule)
                    TextFormField(
                      controller: _customerNameController,
                      decoration: _inputDecoration(
                        label: 'Customer Name',
                        hint: 'Enter customer name',
                        icon: Icons.person_rounded,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Place & District
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _placeController,
                            decoration: _inputDecoration(
                              label: 'Place',
                              hint: 'Enter place',
                              icon: Icons.place_rounded,
                              isDark: isDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _districtController,
                            decoration: _inputDecoration(
                              label: 'District',
                              hint: 'Enter district',
                              icon: Icons.location_city_rounded,
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // State & Phone
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _stateController,
                            decoration: _inputDecoration(
                              label: 'State',
                              hint: 'Enter state',
                              icon: Icons.map_rounded,
                              isDark: isDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
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
                              label: 'Phone',
                              hint: '10-digit number',
                              icon: Icons.phone_rounded,
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
                        value: _selectedPreferredBranch,
                        items: _allBranches.map((b) {
                          return DropdownMenuItem<String>(
                            value: b,
                            child: Text(b),
                          );
                        }).toList(),
                        onChanged: _onBranchChanged,
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
                        value: _selectedSalesman,
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
              const SizedBox(height: 16),

              // 3. Item Details Section (list of rows, photo button on each item, MTC auto lookup)
              _buildCard(
                isDark: isDark,
                title: 'Item Details',
                icon: Icons.inventory_2_rounded,
                child: Column(
                  children: [
                    for (int i = 0; i < _items.length; i++)
                      _buildItemRowCard(
                          index: i, item: _items[i], isDark: isDark),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _addItemRow,
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
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. Payment Mode Selection (Cash, Bank Transfer, UPI)
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
                            icon: Icons.money_rounded,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildPaymentOptionChip(
                            mode: 'Bank Transfer',
                            icon: Icons.account_balance_rounded,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildPaymentOptionChip(
                            mode: 'UPI',
                            icon: Icons.qr_code_2_rounded,
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),

                    // If Bank or UPI selected: show option to upload picture from gallery or take photo now
                    if (_selectedPaymentMode == 'Bank Transfer' ||
                        _selectedPaymentMode == 'UPI') ...[
                      const SizedBox(height: 14),
                      Container(
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
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton.icon(
                                    onPressed: _pickPaymentProof,
                                    icon: const Icon(Icons.refresh_rounded,
                                        size: 16),
                                    label: const Text('Change Photo'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(
                                          () => _paymentProofFile = null);
                                    },
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.redAccent,
                                        size: 16),
                                    label: const Text('Remove',
                                        style: TextStyle(
                                            color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            ] else ...[
                              OutlinedButton.icon(
                                onPressed: _pickPaymentProof,
                                icon: const Icon(Icons.add_a_photo_rounded,
                                    color: primaryBlue),
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
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 5. Order Summary Calculation Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: isDark ? const Color(0xFF0F243E) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Items: ${_items.length}  |  Total Qty: $_totalQty',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Text(
                            'Subtotal: ₹${_subtotal.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'GST Total:',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          Text(
                            '+ ₹${_totalGst.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Grand Total',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₹${_grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen,
                            ),
                          ),
                        ],
                      ),
                      if (_selectedOrderType != 'Spot Delivery') ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(height: 1),
                        ),
                        // Advance & Balance Section
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Advance Amount (₹)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _advanceController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d{0,2}')),
                                    ],
                                    onChanged: (_) {
                                      setState(() {});
                                    },
                                    decoration: InputDecoration(
                                      hintText: '0.00',
                                      prefixIcon: const Icon(
                                          Icons.payments_outlined,
                                          size: 20),
                                      isDense: true,
                                      filled: true,
                                      fillColor: isDark
                                          ? const Color(0xFF132847)
                                          : const Color(0xFFF1F5F9),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
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
                                    'Balance Amount',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 11),
                                    decoration: BoxDecoration(
                                      color: _balanceAmount > 0
                                          ? const Color(0xFFE65100).withValues(
                                              alpha: isDark ? 0.2 : 0.1)
                                          : primaryGreen.withValues(
                                              alpha: isDark ? 0.2 : 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _balanceAmount > 0
                                            ? const Color(0xFFE65100)
                                                .withValues(alpha: 0.4)
                                            : primaryGreen
                                                .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '₹${_balanceAmount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _balanceAmount > 0
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
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 16,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _advanceAmount > 0
                                      ? 'Advance of ₹${_advanceAmount.toStringAsFixed(2)} paid via $_selectedPaymentMode. Balance due: ₹${_balanceAmount.toStringAsFixed(2)}.'
                                      : 'No advance paid. Full balance due on delivery.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 6. Submit Button
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _submitOrder,
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white),
                  label: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Expo Order',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentOptionChip({
    required String mode,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _selectedPaymentMode == mode;

    return InkWell(
      onTap: () => setState(() => _selectedPaymentMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
              size: 22,
              color: isSelected ? Colors.white : primaryBlue,
            ),
            const SizedBox(height: 4),
            Text(
              mode,
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
                    hint: '1',
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
                      item.recalculateTotal();
                    });
                  },
                  decoration: _inputDecoration(
                    label: 'RATE (₹)',
                    hint: '0',
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
                      item.recalculateTotal();
                    });
                  },
                  decoration: _inputDecoration(
                    label: 'GST (%)',
                    hint: '18',
                    isDark: isDark,
                    dense: true,
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
                const Text(
                  'Item Total (incl. GST):',
                  style: TextStyle(
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
  }) {
    return Card(
      elevation: 1,
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
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
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
