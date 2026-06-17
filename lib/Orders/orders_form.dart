import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../Leads/leads_helpers.dart';
import 'orders.dart';

class OrderFormPage extends StatefulWidget {
  const OrderFormPage({super.key});

  @override
  State<OrderFormPage> createState() => _OrderFormPageState();
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

class _OrderFormPageState extends State<OrderFormPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(text: '+91 ');
  final TextEditingController _deliveryController = TextEditingController();

  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();

  String _priority = 'High';
  DateTime? _selectedDeliveryDateTime;
  bool _isSaving = false;

  final List<_OrderItemControllers> _items = [
    _OrderItemControllers(),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _deliveryController.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
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
    final initial = _selectedDeliveryDateTime ?? now.add(const Duration(minutes: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;

    setState(() {
      _selectedDeliveryDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _deliveryController.text = DateFormat('dd-MM-yyyy hh:mm a').format(_selectedDeliveryDateTime!);
    });
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

  Future<void> _saveOrder() async {
    if (!_formKey.currentState!.validate()) return;

    final itemPayload = _buildItemsPayload();
    if (itemPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item with qty')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final branch = userDoc.data()?['branch'] ?? 'Unknown';

      await FirebaseFirestore.instance.collection('follow_ups').add({
        'lead_type': 'order_confirmed',
        'date': DateTime.now(),
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'priority': _priority,
        'status': 'In Progress',
        'delivery_date': _deliveryController.text.trim(),
        if (_selectedDeliveryDateTime != null)
          'delivery_datetime': Timestamp.fromDate(_selectedDeliveryDateTime!),
        'items_list': itemPayload,
        'branch': branch,
        'created_by': user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'source': 'Sales',
      });

      await FirebaseFirestore.instance.collection('customer').doc(_phoneController.text.trim()).set({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'branch': branch,
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OrdersPage(branch: branch)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save order: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('New Confirmed Order'),
            backgroundColor: const Color(0xFF005BAC),
            foregroundColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser!.uid)
                        .get(),
                    builder: (context, userSnap) {
                      if (!userSnap.hasData) return const SizedBox.shrink();
                      final branch = userSnap.data!.get('branch') ?? '';

                      return RawAutocomplete<Map<String, dynamic>>(
                        textEditingController: _nameController,
                        focusNode: _nameFocusNode,
                        optionsBuilder: (value) async {
                          if (value.text.isEmpty) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                          return fetchCustomerSuggestions(value.text, branch);
                        },
                        displayStringForOption: (option) => option['name'] ?? '',
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Customer Name',
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (value) => (value == null || value.trim().isEmpty)
                                ? 'Enter customer name'
                                : null,
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          if (options.isEmpty) return const SizedBox.shrink();
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              child: SizedBox(
                                height: 200,
                                child: ListView.builder(
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      title: Text(option['name'] ?? ''),
                                      subtitle: Text(option['phone'] ?? ''),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        onSelected: (selectedCustomer) {
                          setState(() {
                            _nameController.text = selectedCustomer['name'] ?? '';
                            _addressController.text = selectedCustomer['address'] ?? '';
                            _phoneController.text = formatIndianPhone(selectedCustomer['phone'] ?? '');
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Enter address'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  RawAutocomplete<Map<String, dynamic>>(
                    textEditingController: _phoneController,
                    focusNode: _phoneFocusNode,
                    optionsBuilder: (value) async {
                      if (value.text.isEmpty) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      final userDoc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .get();
                      final branch = userDoc.data()?['branch'] ?? '';
                      return fetchCustomerSuggestions(value.text, branch);
                    },
                    displayStringForOption: (option) => option['phone'] ?? '',
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          prefixIcon: Icon(Icons.phone),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty || !value.startsWith('+91 ')) {
                            return 'Phone must start with +91';
                          }
                          final digits = value.replaceAll(RegExp(r'\D'), '');
                          if (digits.length != 12) {
                            return 'Enter valid 10-digit number after +91';
                          }
                          return null;
                        },
                        onChanged: (val) {
                          if (!val.startsWith('+91 ')) {
                            controller.text = '+91 ';
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                            return;
                          }

                          String raw = val.replaceAll('+91 ', '').replaceAll(' ', '');
                          if (raw.length > 10) raw = raw.substring(0, 10);
                          final formatted = raw.length > 5
                              ? '+91 ${raw.substring(0, 5)} ${raw.substring(5)}'
                              : '+91 $raw';
                          if (controller.text != formatted) {
                            controller.text = formatted;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: formatted.length),
                            );
                          }
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      if (options.isEmpty) return const SizedBox.shrink();
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          child: SizedBox(
                            height: 200,
                            child: ListView.builder(
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  title: Text(option['phone'] ?? ''),
                                  subtitle: Text(option['name'] ?? ''),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                    onSelected: (selectedCustomer) {
                      setState(() {
                        _nameController.text = selectedCustomer['name'] ?? '';
                        _addressController.text = selectedCustomer['address'] ?? '';
                        _phoneController.text = formatIndianPhone(selectedCustomer['phone'] ?? '');
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _priority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      prefixIcon: Icon(Icons.flag),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'High', child: Text('High')),
                      DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'Low', child: Text('Low')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _priority = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _deliveryController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Delivery Date',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    onTap: _pickDeliveryDateTime,
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Select delivery date and time'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Items List',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addItemRow,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Item'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_items.length, (index) {
                    final row = _items[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text('${index + 1}.', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: row.itemController,
                              decoration: const InputDecoration(
                                labelText: 'Item',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: row.qtyController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Qty',
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: () => _removeItemRow(index),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF005BAC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Save Confirmed Order',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isSaving)
          Container(
            color: Colors.black.withValues(alpha: 0.25),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
