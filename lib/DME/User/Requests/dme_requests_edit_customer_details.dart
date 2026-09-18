import 'dart:convert';
import 'package:flutter/material.dart';
import '../../dme_config.dart';
import '../../dme_constants.dart';

/// Data bundle representing customer detail changes
class DmeEditCustomerDetailsData {
  final String oldName;
  final String newName;
  final int? oldCategoryId;
  final String oldCategoryName;
  final int? newCategoryId;
  final String newCategoryName;
  final int? oldCustomerTypeId;
  final String oldCustomerTypeName;
  final int? newCustomerTypeId;
  final String newCustomerTypeName;
  final String reason;
  final List<String> changedFields;

  DmeEditCustomerDetailsData({
    required this.oldName,
    required this.newName,
    required this.oldCategoryId,
    required this.oldCategoryName,
    required this.newCategoryId,
    required this.newCategoryName,
    required this.oldCustomerTypeId,
    required this.oldCustomerTypeName,
    required this.newCustomerTypeId,
    required this.newCustomerTypeName,
    required this.reason,
    required this.changedFields,
  });

  bool get hasChanges => changedFields.isNotEmpty;

  String toJsonCurrentValue() {
    return jsonEncode({
      'name': oldName,
      'category_id': oldCategoryId,
      'category_name': oldCategoryName,
      'customer_type_id': oldCustomerTypeId,
      'customer_type_name': oldCustomerTypeName,
    });
  }

  String toJsonNewValue() {
    return jsonEncode({
      'name': newName,
      'category_id': newCategoryId,
      'category_name': newCategoryName,
      'customer_type_id': newCustomerTypeId,
      'customer_type_name': newCustomerTypeName,
      'changed_fields': changedFields,
    });
  }

  String toFormattedSummary() {
    final List<String> parts = [];
    if (changedFields.contains('name')) {
      parts.add('Name: "$oldName" ➔ "$newName"');
    }
    if (changedFields.contains('category')) {
      parts.add('Category: $oldCategoryName ➔ $newCategoryName');
    }
    if (changedFields.contains('customer_type')) {
      parts.add('Type: $oldCustomerTypeName ➔ $newCustomerTypeName');
    }
    return '${parts.join(" | ")} | Reason: $reason';
  }
}

/// Form component for requesting changes to Customer Name, Category, or Customer Type.
/// Users can change all of them or any one of them.
class DmeRequestsEditCustomerDetailsForm extends StatefulWidget {
  final Map<String, dynamic> reminder;
  final TextEditingController nameController;
  final TextEditingController reasonController;
  final Function(DmeEditCustomerDetailsData? data)? onChanged;

  const DmeRequestsEditCustomerDetailsForm({
    super.key,
    required this.reminder,
    required this.nameController,
    required this.reasonController,
    this.onChanged,
  });

  @override
  State<DmeRequestsEditCustomerDetailsForm> createState() =>
      DmeRequestsEditCustomerDetailsFormState();
}

class DmeRequestsEditCustomerDetailsFormState
    extends State<DmeRequestsEditCustomerDetailsForm> {
  String _initialName = '';
  int? _initialCategoryId;
  String _initialCategoryName = 'N/A';
  int? _initialCustomerTypeId;
  String _initialCustomerTypeName = 'N/A';

  int? _selectedCategoryId;
  int? _selectedCustomerTypeId;
  bool _isLoadingCurrentValues = false;

  @override
  void initState() {
    super.initState();
    _initInitialValues();
  }

  Future<void> _initInitialValues() async {
    _initialName = (widget.reminder['customer_name'] ?? '').toString().trim();
    if (widget.nameController.text.isEmpty && _initialName.isNotEmpty) {
      widget.nameController.text = _initialName;
    }

    _initialCategoryId = int.tryParse(widget.reminder['category_id']?.toString() ?? '');
    _initialCustomerTypeId = int.tryParse(widget.reminder['customer_type_id']?.toString() ?? '');

    // Fetch branch record if initial values are missing
    final customerId = int.tryParse(widget.reminder['customer_id']?.toString() ?? '');
    if ((_initialCategoryId == null || _initialCustomerTypeId == null) &&
        customerId != null &&
        customerId > 0) {
      setState(() => _isLoadingCurrentValues = true);
      try {
        final client = await DmeConfig.getClient();
        if (client != null) {
          final res = await client
              .from('dme_customer_branches')
              .select('branch_id, category_id, customer_type_id')
              .eq('customer_id', customerId);

          if ((res as List).isNotEmpty) {
            final branchId = int.tryParse(widget.reminder['last_purchase_branch']?.toString() ??
                widget.reminder['branch_id']?.toString() ??
                '');

            final match = (res).firstWhere(
              (b) => branchId != null && int.tryParse(b['branch_id']?.toString() ?? '') == branchId,
              orElse: () => res.first,
            );

            _initialCategoryId ??= int.tryParse(match['category_id']?.toString() ?? '');
            _initialCustomerTypeId ??= int.tryParse(match['customer_type_id']?.toString() ?? '');
          }
        }
      } catch (e) {
        debugPrint('Error resolving customer branch details: $e');
      } finally {
        if (mounted) setState(() => _isLoadingCurrentValues = false);
      }
    }

    _initialCategoryName = DmeConstants.getCategoryName(_initialCategoryId);
    _initialCustomerTypeName = DmeConstants.getCustomerTypeName(_initialCustomerTypeId);

    _selectedCategoryId = _initialCategoryId;
    _selectedCustomerTypeId = _initialCustomerTypeId;

    _notifyChange();
  }

  DmeEditCustomerDetailsData getData() {
    final newName = widget.nameController.text.trim();
    final List<String> changedFields = [];

    if (newName.isNotEmpty && newName != _initialName) {
      changedFields.add('name');
    }
    if (_selectedCategoryId != _initialCategoryId) {
      changedFields.add('category');
    }
    if (_selectedCustomerTypeId != _initialCustomerTypeId) {
      changedFields.add('customer_type');
    }

    return DmeEditCustomerDetailsData(
      oldName: _initialName,
      newName: newName,
      oldCategoryId: _initialCategoryId,
      oldCategoryName: _initialCategoryName,
      newCategoryId: _selectedCategoryId,
      newCategoryName: DmeConstants.getCategoryName(_selectedCategoryId),
      oldCustomerTypeId: _initialCustomerTypeId,
      oldCustomerTypeName: _initialCustomerTypeName,
      newCustomerTypeId: _selectedCustomerTypeId,
      newCustomerTypeName: DmeConstants.getCustomerTypeName(_selectedCustomerTypeId),
      reason: widget.reasonController.text.trim(),
      changedFields: changedFields,
    );
  }

  void _notifyChange() {
    widget.onChanged?.call(getData());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final data = getData();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Notice Info Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF007A87).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF007A87).withValues(alpha: 0.3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.manage_accounts_rounded, color: Color(0xFF007A87), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You can request to edit Customer Name, Customer Type, or Category. Change any one, two, or all three. Admin will review and apply the updates upon approval.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF005B66)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_isLoadingCurrentValues)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: LinearProgressIndicator(minHeight: 2),
          ),

        // 1. Customer Name Field
        TextFormField(
          controller: widget.nameController,
          onChanged: (_) => _notifyChange(),
          decoration: InputDecoration(
            labelText: 'Customer Name *',
            hintText: 'Enter updated customer name',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            helperText: _initialName.isNotEmpty ? 'Current: $_initialName' : null,
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Customer name cannot be empty';
            }
            if (val.trim().length < 2) {
              return 'Customer name must be at least 2 characters';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // 2. Customer Type Dropdown
        DropdownButtonFormField<int?>(
          value: _selectedCustomerTypeId,
          decoration: InputDecoration(
            labelText: 'Customer Type',
            prefixIcon: const Icon(Icons.verified_user_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            helperText: 'Current: $_initialCustomerTypeName',
          ),
          hint: const Text('Select Customer Type'),
          items: [
            ...DmeConstants.customerTypes.map((type) {
              return DropdownMenuItem<int?>(
                value: type.id,
                child: Row(
                  children: [
                    if (type.id == 1) ...[
                      const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      type.name,
                      style: TextStyle(
                        fontWeight: type.id == 1 ? FontWeight.bold : FontWeight.normal,
                        color: type.id == 1 ? Colors.orange.shade800 : null,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: (val) {
            setState(() => _selectedCustomerTypeId = val);
            _notifyChange();
          },
        ),
        const SizedBox(height: 16),

        // 3. Category Dropdown
        DropdownButtonFormField<int?>(
          value: _selectedCategoryId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Customer Category',
            prefixIcon: const Icon(Icons.category_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            helperText: 'Current: $_initialCategoryName',
          ),
          hint: const Text('Select Category'),
          items: [
            ...DmeConstants.categories.map((cat) {
              return DropdownMenuItem<int?>(
                value: cat.id,
                child: Text(cat.name),
              );
            }),
          ],
          onChanged: (val) {
            setState(() => _selectedCategoryId = val);
            _notifyChange();
          },
        ),
        const SizedBox(height: 16),

        // 4. Live Modification Summary Pill
        if (data.hasChanges) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: isDark ? 0.2 : 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 15, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      'Changes to Request (${data.changedFields.length}):',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (data.changedFields.contains('name'))
                  Text(
                    '• Name: "${data.oldName}" ➔ "${data.newName}"',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (data.changedFields.contains('customer_type'))
                  Text(
                    '• Type: ${data.oldCustomerTypeName} ➔ ${data.newCustomerTypeName}',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (data.changedFields.contains('category'))
                  Text(
                    '• Category: ${data.oldCategoryName} ➔ ${data.newCategoryName}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Please modify Name, Type, or Category above to submit a change request.',
                    style: TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 5. Reason Field
        TextFormField(
          controller: widget.reasonController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Reason for Edit *',
            hintText: 'e.g. Registered under wrong category, customer requested name correction...',
            prefixIcon: const Icon(Icons.notes_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter reason for editing customer details';
            }
            if (val.trim().length < 3) {
              return 'Please enter a more descriptive reason';
            }
            return null;
          },
        ),
      ],
    );
  }
}
