import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../expo_service.dart';

enum CouponManageMode { issue, remove, edit }

class ExpoCouponManagePage extends StatefulWidget {
  final String exhibitionId;
  final String customerKey;
  final String customerName;
  final String shopName;
  final int couponsTaken;
  final int totalEligibleCoupons;
  final int remainingCoupons;
  final List<Map<String, dynamic>> existingSerials;
  final Map<String, List<Map<String, dynamic>>> allExhibitionSerials;
  final CouponManageMode mode;
  final int serialMin;
  final int serialMax;
  final int serialDigits;

  const ExpoCouponManagePage({
    super.key,
    required this.exhibitionId,
    required this.customerKey,
    required this.customerName,
    required this.shopName,
    required this.couponsTaken,
    required this.totalEligibleCoupons,
    required this.remainingCoupons,
    required this.existingSerials,
    required this.allExhibitionSerials,
    required this.mode,
    this.serialMin = 1,
    this.serialMax = 4000,
    this.serialDigits = 4,
  });

  @override
  State<ExpoCouponManagePage> createState() => _ExpoCouponManagePageState();
}

class _ExpoCouponManagePageState extends State<ExpoCouponManagePage> {
  static const Color _primaryBlue = Color(0xFF005BAC);
  static const Color _primaryGreen = Color(0xFF00897B);

  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _controllers = [];
  final List<int> _editIndices = [];
  final Set<int> _selectedRemoveIndices = {};
  bool _isSaving = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    if (widget.mode == CouponManageMode.issue) {
      for (int i = 0; i < widget.remainingCoupons; i++) {
        _controllers.add(TextEditingController());
      }
    } else if (widget.mode == CouponManageMode.edit) {
      for (int i = 0; i < widget.existingSerials.length; i++) {
        if (_isIssuedToday(widget.existingSerials[i])) {
          _editIndices.add(i);
          _controllers.add(TextEditingController(
              text: (widget.existingSerials[i]['serial'] ?? '').toString()));
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isIssuedToday(Map<String, dynamic> entry) {
    final raw = (entry['issued_at'] ?? '').toString();
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  String? _validateSerial(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Required';
    final numVal = int.tryParse(trimmed);
    if (numVal == null || numVal < widget.serialMin || numVal > widget.serialMax) {
      final minStr = widget.serialMin.toString().padLeft(widget.serialDigits, '0');
      final maxStr = widget.serialMax.toString().padLeft(widget.serialDigits, '0');
      return 'Enter $minStr - $maxStr';
    }
    return null;
  }

  bool _isSerialUsedElsewhere(
    String paddedSerial, {
    Set<int>? excludeOwnIndices,
  }) {
    final targetNum = int.tryParse(paddedSerial);
    for (final entry in widget.allExhibitionSerials.entries) {
      for (int i = 0; i < entry.value.length; i++) {
        if (entry.key == widget.customerKey &&
            excludeOwnIndices != null &&
            excludeOwnIndices.contains(i)) {
          continue;
        }
        final s = (entry.value[i]['serial'] ?? '').toString().trim();
        final sNum = int.tryParse(s);
        if (targetNum != null && sNum != null) {
          if (sNum == targetNum) return true;
        } else if (s == paddedSerial) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _submit() async {
    setState(() => _errorMsg = null);

    if (widget.mode == CouponManageMode.remove) {
      if (_selectedRemoveIndices.isEmpty) {
        setState(() => _errorMsg = 'Select at least one coupon to remove.');
        return;
      }
      setState(() => _isSaving = true);
      try {
        final updated = <Map<String, dynamic>>[];
        for (int i = 0; i < widget.existingSerials.length; i++) {
          if (!_selectedRemoveIndices.contains(i)) {
            updated.add(widget.existingSerials[i]);
          }
        }
        final newTaken =
            (widget.couponsTaken - _selectedRemoveIndices.length)
                .clamp(0, widget.totalEligibleCoupons);
        await ExpoService.instance.upsertCustomerCouponsTaken(
          exhibitionId: widget.exhibitionId,
          customerPhone: widget.customerKey,
          couponsTaken: newTaken,
          couponSerials: updated,
        );
        if (!mounted) return;
        Navigator.of(context).pop({
          'couponsTaken': newTaken,
          'couponSerials': updated,
        });
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSaving = false;
            _errorMsg = 'Failed to remove coupons: $e';
          });
        }
      }
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    final normalized = _controllers
        .map((c) => int.parse(c.text.trim())
            .toString()
            .padLeft(widget.serialDigits, '0'))
        .toList();
    if (normalized.toSet().length != normalized.length) {
      setState(() => _errorMsg = 'Duplicate serial numbers are not allowed.');
      return;
    }

    final excludeSet =
        widget.mode == CouponManageMode.edit ? _editIndices.toSet() : null;
    for (final s in normalized) {
      if (_isSerialUsedElsewhere(s, excludeOwnIndices: excludeSet)) {
        setState(() =>
            _errorMsg = 'Serial $s is already assigned to another coupon.');
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      // Re-fetch latest from Supabase to prevent concurrent issue/duplicate race conditions
      final latestSerialsMap = await ExpoService.instance
          .fetchCustomerCouponSerialsForExhibition(widget.exhibitionId);
      final latestTakenMap = await ExpoService.instance
          .fetchCustomerCouponsForExhibition(widget.exhibitionId);
      final latestTaken = latestTakenMap[widget.customerKey] ?? 0;
      final latestCustomerSerials =
          List<Map<String, dynamic>>.from(latestSerialsMap[widget.customerKey] ?? []);

      if (widget.mode == CouponManageMode.issue) {
        if (latestTaken != widget.couponsTaken) {
          if (mounted) {
            setState(() {
              _isSaving = false;
              _errorMsg =
                  'Coupons for this customer were just updated by another user. Please go back and refresh.';
            });
          }
          return;
        }
        for (final s in normalized) {
          final targetNum = int.tryParse(s);
          for (final entry in latestSerialsMap.entries) {
            if (entry.value.any((e) {
              final existingStr = (e['serial'] ?? '').toString().trim();
              final existingNum = int.tryParse(existingStr);
              if (targetNum != null && existingNum != null) {
                return existingNum == targetNum;
              }
              return existingStr == s;
            })) {
              if (mounted) {
                setState(() {
                  _isSaving = false;
                  _errorMsg = 'Serial $s was just assigned by another user.';
                });
              }
              return;
            }
          }
        }
      }

      final updated = latestCustomerSerials.isNotEmpty
          ? latestCustomerSerials
          : List<Map<String, dynamic>>.from(widget.existingSerials);
      int newTaken = latestTaken;

      if (widget.mode == CouponManageMode.issue) {
        final nowIso = DateTime.now().toIso8601String();
        for (final s in normalized) {
          updated.add({'serial': s, 'issued_at': nowIso});
        }
        newTaken = latestTaken + normalized.length;
      } else {
        for (int i = 0; i < _editIndices.length; i++) {
          final idx = _editIndices[i];
          if (idx < updated.length) {
            updated[idx] = {
              ...updated[idx],
              'serial': normalized[i],
            };
          }
        }
      }

      await ExpoService.instance.upsertCustomerCouponsTaken(
        exhibitionId: widget.exhibitionId,
        customerPhone: widget.customerKey,
        couponsTaken: newTaken,
        couponSerials: updated,
      );
      if (!mounted) return;
      Navigator.of(context).pop({
        'couponsTaken': newTaken,
        'couponSerials': updated,
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMsg = 'Failed to save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF0A192F) : const Color(0xFFF4F7FA);
    final cardColor = isDark ? const Color(0xFF0F243E) : Colors.white;

    final String title;
    final String actionLabel;
    final Color accentColor;
    switch (widget.mode) {
      case CouponManageMode.issue:
        title = 'Issue ${widget.remainingCoupons} Coupon${widget.remainingCoupons > 1 ? 's' : ''}';
        actionLabel = 'Confirm & Issue';
        accentColor = _primaryBlue;
        break;
      case CouponManageMode.remove:
        title = 'Remove Coupons';
        actionLabel = 'Remove Selected (${_selectedRemoveIndices.length})';
        accentColor = Colors.redAccent;
        break;
      case CouponManageMode.edit:
        title = "Edit Today's Serials";
        actionLabel = 'Save Changes';
        accentColor = _primaryGreen;
        break;
    }

    final displayName = widget.customerName.isNotEmpty
        ? widget.customerName
        : widget.shopName;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Customer Header Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _primaryBlue.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _primaryBlue.withValues(alpha: 0.12),
                  child: const Icon(Icons.confirmation_number_rounded,
                      color: _primaryBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Taken: ${widget.couponsTaken} / ${widget.totalEligibleCoupons}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: widget.mode == CouponManageMode.remove
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: widget.existingSerials.length,
                    itemBuilder: (context, index) {
                      final entry = widget.existingSerials[index];
                      final serial = (entry['serial'] ?? '').toString();
                      final dt = DateTime.tryParse(
                              (entry['issued_at'] ?? '').toString())
                          ?.toLocal();
                      final dateLabel = dt != null
                          ? DateFormat('dd MMM yyyy, hh:mm a').format(dt)
                          : '';
                      final selected = _selectedRemoveIndices.contains(index);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: selected
                                ? Colors.redAccent
                                : _primaryBlue.withValues(alpha: 0.15),
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: CheckboxListTile(
                          value: selected,
                          activeColor: Colors.redAccent,
                          onChanged: _isSaving
                              ? null
                              : (val) {
                                  setState(() {
                                    _errorMsg = null;
                                    if (val == true) {
                                      _selectedRemoveIndices.add(index);
                                    } else {
                                      _selectedRemoveIndices.remove(index);
                                    }
                                  });
                                },
                          title: Text(
                            'Serial #$serial',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          subtitle: dateLabel.isNotEmpty
                              ? Text(
                                  'Issued: $dateLabel',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  )
                : Form(
                    key: _formKey,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: _controllers.length,
                      itemBuilder: (context, i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextFormField(
                            controller: _controllers[i],
                            keyboardType: TextInputType.number,
                            maxLength: widget.serialDigits,
                            decoration: InputDecoration(
                              labelText:
                                  'Coupon ${i + 1} Serial (${widget.serialMin.toString().padLeft(widget.serialDigits, '0')} - ${widget.serialMax.toString().padLeft(widget.serialDigits, '0')})',
                              counterText: '',
                              filled: true,
                              fillColor: cardColor,
                              prefixIcon: const Icon(Icons.tag_rounded,
                                  color: _primaryBlue),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (v) => _validateSerial(v ?? ''),
                          ),
                        );
                      },
                    ),
                  ),
          ),

          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                _errorMsg!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          actionLabel,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
