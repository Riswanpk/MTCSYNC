import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'expo_service.dart';
import 'expo_supabase_config.dart';

const Color _kPrimaryBlue = Color(0xFF005BAC);
const Color _kPrimaryGreen = Color(0xFF8CC63F);

/// Prompts for confirming a Stall Delivery pickup and collecting any remaining
/// balance using one of the 5 supported payment modes (plus split inputs and
/// receipt upload when applicable). Returns true if the pickup was saved.
Future<bool> showStallPickupPaymentDialog(
  BuildContext context, {
  required ExpoOrder order,
  required bool isAccountsUser,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _StallPickupPaymentDialog(
      order: order,
      isAccountsUser: isAccountsUser,
    ),
  );
  return result == true;
}

class _StallPickupPaymentDialog extends StatefulWidget {
  final ExpoOrder order;
  final bool isAccountsUser;

  const _StallPickupPaymentDialog({
    required this.order,
    required this.isAccountsUser,
  });

  @override
  State<_StallPickupPaymentDialog> createState() =>
      _StallPickupPaymentDialogState();
}

class _StallPickupPaymentDialogState extends State<_StallPickupPaymentDialog> {
  final ImagePicker _picker = ImagePicker();
  late final TextEditingController _totalAdvanceController;
  late final TextEditingController _cashController;
  late final TextEditingController _onlineController;

  String _selectedMode = 'Cash';
  File? _receiptFile;
  bool _isSaving = false;
  String? _errorText;

  double get _balanceDue => widget.order.balanceAmount > 0.01
      ? widget.order.balanceAmount
      : 0.0;

  @override
  void initState() {
    super.initState();
    _totalAdvanceController = TextEditingController();
    _cashController = TextEditingController();
    _onlineController = TextEditingController();
  }

  @override
  void dispose() {
    _totalAdvanceController.dispose();
    _cashController.dispose();
    _onlineController.dispose();
    super.dispose();
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  String _fmtMoney(double v) {
    final r = _round2(v);
    if (r <= 0) return '';
    return (r - r.roundToDouble()).abs() < 0.005
        ? r.round().toString()
        : r.toStringAsFixed(2);
  }

  void _syncReadOnlySplitTotal() {
    final cash = double.tryParse(_cashController.text.trim()) ?? 0.0;
    final online = double.tryParse(_onlineController.text.trim()) ?? 0.0;
    _totalAdvanceController.text = _fmtMoney(cash + online);
  }

  void _selectMode(String mode) {
    setState(() {
      _selectedMode = mode;
      _errorText = null;
      if (!ExpoOrder.modeRequiresReceipt(mode)) {
        _receiptFile = null;
      }
      if (ExpoOrder.modeIsSplit(mode)) {
        _syncReadOnlySplitTotal();
      }
    });
  }

  void _onCashChanged(String raw) {
    setState(() {
      _errorText = null;
      _syncReadOnlySplitTotal();
    });
  }

  void _onOnlineChanged(String raw) {
    setState(() {
      _errorText = null;
      _syncReadOnlySplitTotal();
    });
  }

  Future<File> _compressImage(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/pickup_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 55,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.jpeg,
      );
      if (compressed != null) {
        final f = File(compressed.path);
        if (f.existsSync()) return f;
      }
    } catch (e) {
      debugPrint('Error compressing pickup receipt: $e');
    }
    return file;
  }

  Future<void> _pickReceipt(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 60,
      );
      if (picked != null && mounted) {
        final compressed = await _compressImage(File(picked.path));
        if (mounted) {
          setState(() => _receiptFile = compressed);
        }
      }
    } catch (e) {
      debugPrint('Error picking pickup receipt: $e');
    }
  }

  Future<void> _showReceiptPickerSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = await showModalBottomSheet<ImageSource>(
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
              const Text(
                'Pickup Payment Receipt',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: _kPrimaryBlue),
                title: const Text('Take Photo Now'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: _kPrimaryGreen),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null) {
      await _pickReceipt(source);
    }
  }

  Future<void> _submit() async {
    final double balance = _balanceDue;
    double pickupCash = 0.0;
    double pickupOnline = 0.0;

    if (balance > 0) {
      if (_selectedMode == 'Cash') {
        pickupCash = _round2(balance);
      } else if (ExpoOrder.modeIsSplit(_selectedMode)) {
        pickupCash = _round2(double.tryParse(_cashController.text.trim()) ?? 0.0);
        pickupOnline =
            _round2(double.tryParse(_onlineController.text.trim()) ?? 0.0);
        if ((pickupCash + pickupOnline - balance).abs() > 0.05) {
          final label = ExpoOrder.onlineLabelForMode(_selectedMode);
          setState(() {
            _errorText =
                'Cash + $label must equal ₹${balance.toStringAsFixed(2)}';
          });
          return;
        }
      } else {
        pickupOnline = _round2(balance);
      }
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      String? proofUrl;
      if (_receiptFile != null &&
          ExpoOrder.modeRequiresReceipt(_selectedMode)) {
        proofUrl = await ExpoService.instance.uploadFile(
          _receiptFile!,
          bucketName: ExpoOrder.modeUsesUpiBucket(_selectedMode)
              ? ExpoSupabaseConfig.bucketUpiProofs
              : ExpoSupabaseConfig.bucketBankProofs,
        );
      }

      final bool completeImmediately = balance <= 0
          ? (widget.isAccountsUser || widget.order.status == 'Completed')
          : widget.isAccountsUser;

      await ExpoService.instance.markStallDeliveryPickedUp(
        widget.order.id,
        currentBalance: widget.order.balanceAmount,
        pickupPaymentMode: balance > 0 ? _selectedMode : null,
        pickupAmount: balance,
        pickupCashAmount: pickupCash,
        pickupOnlineAmount: pickupOnline,
        pickupPaymentProofUrl: proofUrl,
        completeImmediately: completeImmediately,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorText = 'Failed to save pickup: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasBalance = _balanceDue > 0;
    final bool isSplit = ExpoOrder.modeIsSplit(_selectedMode);
    final bool requiresReceipt = ExpoOrder.modeRequiresReceipt(_selectedMode);
    final String onlineLabel = ExpoOrder.onlineLabelForMode(_selectedMode);
    final numFormatters = [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
    ];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.storefront_rounded, color: _kPrimaryBlue),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Stall Delivery Pickup',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.order.shopName.isNotEmpty
                    ? widget.order.shopName
                    : widget.order.customerName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _infoLine(
                      'Net Total',
                      '₹${widget.order.totalAmount.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 4),
                    _infoLine(
                      'Advance Paid (${widget.order.paymentMode})',
                      '₹${widget.order.advanceAmount.toStringAsFixed(2)}',
                    ),
                    const Divider(height: 14),
                    _infoLine(
                      'Balance Due at Pickup',
                      '₹${_balanceDue.toStringAsFixed(2)}',
                      valueColor:
                          hasBalance ? const Color(0xFFE65100) : _kPrimaryGreen,
                      bold: true,
                    ),
                  ],
                ),
              ),
              if (!hasBalance) ...[
                const SizedBox(height: 12),
                Text(
                  'No balance remaining. Confirm that the customer has picked up the items at the stall.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 14),
                const Text(
                  'Balance Payment Mode',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _modeChip('Cash', '1. Cash', Icons.money_rounded, isDark),
                    _modeChip('UPI', '2. UPI', Icons.qr_code_2_rounded, isDark),
                    _modeChip('UPI + Cash', '3. UPI + Cash',
                        Icons.qr_code_scanner_rounded, isDark),
                    _modeChip('Bank', '4. Bank', Icons.account_balance_rounded,
                        isDark),
                    _modeChip('Bank + Cash', '5. Bank + Cash',
                        Icons.account_balance_wallet_rounded, isDark),
                  ],
                ),
                if (isSplit) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _totalAdvanceController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Total Advance (₹)',
                      isDense: true,
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF1F5F9),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cashController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: numFormatters,
                          onChanged: _onCashChanged,
                          decoration: const InputDecoration(
                            labelText: 'Cash (₹)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _onlineController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: numFormatters,
                          onChanged: _onOnlineChanged,
                          decoration: InputDecoration(
                            labelText: '$onlineLabel (₹)',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (requiresReceipt) ...[
                  const SizedBox(height: 12),
                  if (_receiptFile != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _receiptFile!,
                        height: 110,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _isSaving ? null : _showReceiptPickerSheet,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Change'),
                        ),
                        TextButton.icon(
                          onPressed: _isSaving
                              ? null
                              : () => setState(() => _receiptFile = null),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent, size: 16),
                          label: const Text('Remove',
                              style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _showReceiptPickerSheet,
                        icon: const Icon(Icons.add_a_photo_rounded,
                            color: _kPrimaryBlue),
                        label: Text(
                          'Upload $_selectedMode Receipt',
                          style: const TextStyle(color: _kPrimaryBlue),
                        ),
                      ),
                    ),
                ],
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _submit,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_rounded, size: 18),
          label: Text(_isSaving
              ? 'Saving...'
              : (hasBalance ? 'Confirm Pickup & Payment' : 'Confirm Pickup')),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimaryGreen,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _modeChip(String mode, String label, IconData icon, bool isDark) {
    final selected = _selectedMode == mode;
    return ChoiceChip(
      selected: selected,
      onSelected: _isSaving ? null : (_) => _selectMode(mode),
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : _kPrimaryBlue,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: selected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
      selectedColor: _kPrimaryBlue,
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : const Color(0xFFF1F5F9),
    );
  }

  Widget _infoLine(
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 14 : 12.5,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
