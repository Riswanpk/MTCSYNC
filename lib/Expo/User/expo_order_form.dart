import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../Navigation/user_cache_service.dart';
import '../expo_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class ExpoOrderFormPage extends StatefulWidget {
  final Exhibition exhibition;

  const ExpoOrderFormPage({
    super.key,
    required this.exhibition,
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

  // Auto-fetched date (read-only)
  final DateTime _orderDate = DateTime.now();

  // Order Type: 'Spot Delivery', 'Booking', 'Stall Delivery'
  String _selectedOrderType = 'Spot Delivery';

  // Customer Details Controllers
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _placeController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _stateController =
      TextEditingController(text: 'Kerala');
  final TextEditingController _phoneController = TextEditingController();

  // Preferred Branch & Preferred Salesman
  List<String> _allBranches = [];
  String? _selectedPreferredBranch;
  List<String> _salesmenForBranch = ['N/A'];
  String _selectedSalesman = 'N/A';
  bool _isLoadingBranches = true;

  // Item Details
  final List<_ItemRowData> _items = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Initialize with 1 item row
    _addItemRow();
    _loadBranchesAndUser();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _customerNameController.dispose();
    _placeController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    _phoneController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
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

  Future<void> _loadBranchesAndUser() async {
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      final branches = await cache.getBranches();

      final userBranch = cache.branch ?? '';
      String? defaultBranch;
      if (userBranch.isNotEmpty && branches.contains(userBranch)) {
        defaultBranch = userBranch;
      } else if (branches.isNotEmpty) {
        defaultBranch = branches.first;
      }

      if (mounted) {
        setState(() {
          _allBranches = branches;
          _selectedPreferredBranch = defaultBranch;
        });
      }

      if (defaultBranch != null) {
        await _onBranchChanged(defaultBranch);
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

    if (_selectedPreferredBranch == null || _selectedPreferredBranch!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select preferred branch')),
      );
      return;
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
          SnackBar(content: Text('Please enter a valid quantity (>0) for Item #${i + 1}')),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();

      final List<ExpoOrderItem> orderItems = _items.map((it) {
        final qty = int.tryParse(it.qtyController.text.trim()) ?? 0;
        final rate = double.tryParse(it.rateController.text.trim()) ?? 0.0;
        final gst = double.tryParse(it.gstController.text.trim()) ?? 0.0;
        final total = ExpoOrderItem.calculateTotal(qty, rate, gst);

        return ExpoOrderItem(
          mtcCode: it.mtcCodeController.text.trim(),
          itemName: it.itemNameController.text.trim(),
          description: it.descriptionController.text.trim(),
          qty: qty,
          rate: rate,
          gst: gst,
          total: total,
        );
      }).toList();

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
        preferredBranch: _selectedPreferredBranch!,
        preferredSalesman: _selectedSalesman,
        items: orderItems,
        subtotal: _subtotal,
        totalGst: _totalGst,
        totalAmount: _grandTotal,
        totalQty: _totalQty,
        status: 'Pending',
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
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New Expo Order',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              widget.exhibition.name,
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
              // 1. Read-only Auto-fetched Date on Top
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
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: primaryBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Read Only',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Order Type Selection (3 types: Spot Delivery, Booking, Stall Delivery)
              _buildCard(
                isDark: isDark,
                title: 'Order Type',
                icon: Icons.local_shipping_rounded,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildOrderTypeChip(
                        type: 'Spot Delivery',
                        color: const Color(0xFF00897B),
                        icon: Icons.flash_on_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildOrderTypeChip(
                        type: 'Booking',
                        color: primaryBlue,
                        icon: Icons.bookmark_add_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildOrderTypeChip(
                        type: 'Stall Delivery',
                        color: const Color(0xFFFF6F00),
                        icon: Icons.storefront_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Customer Details Section
              _buildCard(
                isDark: isDark,
                title: 'Customer Details',
                icon: Icons.person_pin_rounded,
                child: Column(
                  children: [
                    // Shop Name
                    TextFormField(
                      controller: _shopNameController,
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
                    const SizedBox(height: 12),

                    // Preferred Branch (Dropdown)
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
                ),
              ),
              const SizedBox(height: 16),

              // 4. Item Details Section (list of rows, initially 1 row, + add after each item)
              _buildCard(
                isDark: isDark,
                title: 'Item Details',
                icon: Icons.inventory_2_rounded,
                child: Column(
                  children: [
                    for (int i = 0; i < _items.length; i++)
                      _buildItemRowCard(index: i, item: _items[i], isDark: isDark),
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

  Widget _buildOrderTypeChip({
    required String type,
    required Color color,
    required IconData icon,
  }) {
    final isSelected = _selectedOrderType == type;

    return InkWell(
      onTap: () => setState(() => _selectedOrderType = type),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(height: 4),
            Text(
              type,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
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
          // Row Header: Item # and Delete Button
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
          const SizedBox(height: 10),

          // MTC Code & Item Name
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: item.mtcCodeController,
                  decoration: _inputDecoration(
                    label: 'MTC CODE',
                    hint: 'Code',
                    isDark: isDark,
                    dense: true,
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
    required bool isDark,
    bool dense = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: primaryBlue, size: 20) : null,
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
