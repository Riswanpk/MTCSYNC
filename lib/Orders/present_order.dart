import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../Leads/leads_detail_widgets.dart';

class PresentOrderPage extends StatefulWidget {
  final String docId;
  final bool editMode;

  const PresentOrderPage({super.key, required this.docId, this.editMode = false});

  @override
  State<PresentOrderPage> createState() => _PresentOrderPageState();
}

class _OrderItemControllers {
  final TextEditingController itemController;
  final TextEditingController qtyController;

  _OrderItemControllers({String item = '', String qty = ''})
      : itemController = TextEditingController(text: item),
        qtyController = TextEditingController(text: qty);

  void dispose() {
    itemController.dispose();
    qtyController.dispose();
  }
}

class _PresentOrderPageState extends State<PresentOrderPage> {
  final _formKey = GlobalKey<FormState>();

  bool _isEditing = false;
  bool _isSaving = false;
  Map<String, dynamic>? _data;

  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _deliveryController;
  late TextEditingController _branchController;

  String _status = 'In Progress';
  String _priority = 'High';
  DateTime? _selectedDeliveryDate;
  final List<_OrderItemControllers> _items = [];

  @override
  void initState() {
    super.initState();
    _isEditing = widget.editMode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _deliveryController.dispose();
    _branchController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _initControllers(Map<String, dynamic> data) {
    _nameController = TextEditingController(text: data['name'] ?? '');
    _addressController = TextEditingController(text: data['address'] ?? '');
    _phoneController = TextEditingController(text: data['phone'] ?? '');
    _branchController = TextEditingController(text: data['branch'] ?? '');
    _status = data['status'] ?? 'In Progress';
    _priority = data['priority'] ?? 'High';

    _selectedDeliveryDate = _extractDateTime(data['delivery_datetime'], data['delivery_date']);
    _deliveryController = TextEditingController(
      text: _selectedDeliveryDate != null
          ? DateFormat('dd-MM-yyyy hh:mm a').format(_selectedDeliveryDate!)
          : (data['delivery_date'] ?? ''),
    );

    final items = (data['items_list'] as List?) ?? [];
    if (items.isEmpty) {
      _items.add(_OrderItemControllers());
    } else {
      for (final raw in items) {
        final map = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
        _items.add(_OrderItemControllers(
          item: (map['item'] ?? '').toString(),
          qty: (map['qty'] ?? '').toString(),
        ));
      }
    }
  }

  DateTime? _extractDateTime(dynamic timestampValue, dynamic textValue) {
    if (timestampValue is Timestamp) return timestampValue.toDate();
    if (textValue is String && textValue.isNotEmpty) {
      try {
        return DateFormat('dd-MM-yyyy hh:mm a').parse(textValue);
      } catch (_) {
        try {
          return DateTime.parse(textValue);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _buildItemsPayload() {
    final payload = <Map<String, dynamic>>[];
    for (final row in _items) {
      final itemName = row.itemController.text.trim();
      final qty = row.qtyController.text.trim();
      if (itemName.isNotEmpty || qty.isNotEmpty) {
        payload.add({'item': itemName, 'qty': qty});
      }
    }
    return payload;
  }

  void _addItemRow() {
    setState(() {
      _items.add(_OrderItemControllers());
    });
  }

  void _removeItemRow(int index) {
    if (_items.length == 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  Future<void> _pickDeliveryDateTime() async {
    final now = DateTime.now();
    final initial = _selectedDeliveryDate ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;

    setState(() {
      _selectedDeliveryDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _deliveryController.text = DateFormat('dd-MM-yyyy hh:mm a').format(_selectedDeliveryDate!);
    });
  }

  Future<void> _markCompleted() async {
    await FirebaseFirestore.instance.collection('follow_ups').doc(widget.docId).update({
      'status': 'Completed',
      'completed_at': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    setState(() {
      _data?['status'] = 'Completed';
      _status = 'Completed';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order marked as Completed')),
    );
  }

  Future<void> _saveEdits() async {
    if (!_formKey.currentState!.validate()) return;

    final itemsPayload = _buildItemsPayload();
    if (itemsPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item with qty')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'priority': _priority,
        'status': _status,
        'delivery_date': _deliveryController.text.trim(),
        if (_selectedDeliveryDate != null)
          'delivery_datetime': Timestamp.fromDate(_selectedDeliveryDate!),
        'items_list': itemsPayload,
      };

      if (_status == 'Completed') {
        updateData['completed_at'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance.collection('follow_ups').doc(widget.docId).update(updateData);

      if (!mounted) return;
      setState(() {
        _isEditing = false;
        _data = {...?_data, ...updateData};
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update order: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildItemsView(bool isDark) {
    final items = (_data?['items_list'] as List?) ?? [];
    if (items.isEmpty) {
      return leadInfoTile(
        Icons.inventory_2_outlined,
        'Items List',
        Text('N/A', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        isDark,
      );
    }

    final lines = <String>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final name = (item['item'] ?? '').toString();
      final qty = (item['qty'] ?? '').toString();
      lines.add('${i + 1}. $name - Qty: $qty');
    }

    return leadInfoTile(
      Icons.inventory_2_outlined,
      'Items List',
      Text(lines.join('\n'), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
      isDark,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('follow_ups').doc(widget.docId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Order Details'),
              backgroundColor: const Color(0xFF005BAC),
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Order Details'),
              backgroundColor: const Color(0xFF005BAC),
              foregroundColor: Colors.white,
            ),
            body: const Center(child: Text('Order not found.')),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        if ((data['lead_type'] ?? '') != 'order_confirmed') {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Order Details'),
              backgroundColor: const Color(0xFF005BAC),
              foregroundColor: Colors.white,
            ),
            body: const Center(child: Text('This lead is not an order record.')),
          );
        }
        if (_data == null) {
          _data = data;
          _initControllers(data);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Order Details'),
            backgroundColor: const Color(0xFF005BAC),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(_isEditing ? Icons.close : Icons.edit),
                onPressed: () => setState(() => _isEditing = !_isEditing),
              ),
            ],
          ),
          body: Stack(
            children: [
              _isEditing ? _buildEditBody(isDark) : _buildViewBody(isDark),
              if (_isSaving)
                Container(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditBody(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Confirmed Order', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 16),
            leadEditField('Name', _nameController, isDark),
            leadEditField('Address', _addressController, isDark),
            leadEditField('Phone', _phoneController, isDark, keyboardType: TextInputType.phone),
            leadEditDropdown('Priority', ['High', 'Medium', 'Low'], _priority, (v) => setState(() => _priority = v ?? _priority), isDark),
            leadEditDropdown('Status', ['In Progress', 'Completed'], _status, (v) => setState(() => _status = v ?? _status), isDark),
            leadEditField(
              'Delivery Date',
              _deliveryController,
              isDark,
              readOnly: true,
              onTap: _pickDeliveryDateTime,
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text('Items List', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: _addItemRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(_items.length, (index) {
              final row = _items[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: Text('${index + 1}.')),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: row.itemController,
                        decoration: const InputDecoration(labelText: 'Item'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: row.qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Qty'),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _removeItemRow(index),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveEdits,
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewBody(bool isDark) {
    final statusText = (_data?['status'] ?? 'In Progress').toString();
    final deliveryText = (_data?['delivery_date'] ?? '').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Info', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 16),
          leadInfoTile(Icons.person, 'Name', Text(_data?['name'] ?? 'N/A'), isDark),
          leadInfoTile(Icons.location_on, 'Address', Text(_data?['address'] ?? 'N/A'), isDark),
          leadInfoTile(Icons.phone, 'Phone', Text(_data?['phone'] ?? 'N/A'), isDark),
          leadInfoTile(Icons.flag, 'Priority', Text(_data?['priority'] ?? 'N/A'), isDark),
          leadInfoTile(Icons.local_shipping_outlined, 'Delivery Date', Text(deliveryText.isEmpty ? 'N/A' : deliveryText), isDark),
          leadInfoTile(Icons.check_circle_outline, 'Status', Text(statusText), isDark),
          _buildItemsView(isDark),
          const SizedBox(height: 10),
          if (statusText != 'Completed')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _markCompleted,
                icon: const Icon(Icons.check_circle),
                label: const Text('Mark Completed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
