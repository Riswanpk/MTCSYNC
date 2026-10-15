import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../expo_service.dart';
import 'expo_user_selector.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class ExpoAdminFormPage extends StatefulWidget {
  final Exhibition? existingExhibition;

  const ExpoAdminFormPage({super.key, this.existingExhibition});

  @override
  State<ExpoAdminFormPage> createState() => _ExpoAdminFormPageState();
}

class _ExpoAdminFormPageState extends State<ExpoAdminFormPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _locationController;

  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;

  List<Map<String, dynamic>> _selectedUsers = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.existingExhibition;
    _nameController = TextEditingController(text: ex?.name ?? '');
    _locationController = TextEditingController(text: ex?.location ?? '');

    if (ex != null) {
      _startDate = ex.startDate;
      _startTime = TimeOfDay.fromDateTime(ex.startDate);
      _endDate = ex.endDate;
      _endTime = TimeOfDay.fromDateTime(ex.endDate);
      _selectedUsers = List<Map<String, dynamic>>.from(ex.selectedUsers);
    } else {
      final now = DateTime.now();
      _startDate = now;
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endDate = now.add(const Duration(days: 3));
      _endTime = const TimeOfDay(hour: 21, minute: 0);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickDateInterval() async {
    final now = DateTime.now();
    final initialRange = DateTimeRange(
      start: _startDate ?? now,
      end: _endDate ?? now.add(const Duration(days: 3)),
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });

      // Prompt for Start Time
      final pickedStartTime = await showTimePicker(
        context: context,
        initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
        helpText: 'SELECT START TIME',
      );
      if (pickedStartTime != null && mounted) {
        setState(() => _startTime = pickedStartTime);
      }

      // Prompt for End Time
      if (mounted) {
        final pickedEndTime = await showTimePicker(
          context: context,
          initialTime: _endTime ?? const TimeOfDay(hour: 21, minute: 0),
          helpText: 'SELECT END TIME',
        );
        if (pickedEndTime != null && mounted) {
          setState(() => _endTime = pickedEndTime);
        }
      }
    }
  }

  Future<void> _openUserSelector() async {
    final result = await Navigator.of(context).push<List<Map<String, dynamic>>>(
      MaterialPageRoute(
        builder: (_) => ExpoUserSelectorPage(
          initialSelectedUsers: _selectedUsers,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedUsers = result;
      });
    }
  }

  String _formatDateTimeDisplay(DateTime date, TimeOfDay time) {
    final combined = _combineDateAndTime(date, time);
    return DateFormat('dd MMM yyyy, hh:mm a').format(combined);
  }

  Future<void> _saveExhibition() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startDate == null ||
        _startTime == null ||
        _endDate == null ||
        _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select exhibition duration and time.')),
      );
      return;
    }

    final start = _combineDateAndTime(_startDate!, _startTime!);
    final end = _combineDateAndTime(_endDate!, _endTime!);

    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date/time must be after start date/time.')),
      );
      return;
    }

    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one user for this exhibition.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ExpoService.instance.saveExhibition(
        id: widget.existingExhibition?.id,
        name: _nameController.text.trim(),
        startDate: start,
        endDate: end,
        location: _locationController.text.trim(),
        selectedUsers: _selectedUsers,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingExhibition != null
                  ? 'Exhibition updated successfully'
                  : 'Exhibition created successfully',
            ),
            backgroundColor: primaryGreen,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save exhibition: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.existingExhibition != null;

    // Group selected users by branch for summary
    final Map<String, int> branchCounts = {};
    for (final u in _selectedUsers) {
      final b = (u['branch'] ?? 'Unknown').toString().trim().toUpperCase();
      branchCounts[b] = (branchCounts[b] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Exhibition' : 'New Exhibition',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Exhibition Name
              _buildSectionCard(
                isDark: isDark,
                title: 'Exhibition Name',
                icon: Icons.storefront_rounded,
                child: TextFormField(
                  controller: _nameController,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter exhibition name';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: 'e.g. Grand Expo 2026',
                    prefixIcon: const Icon(Icons.badge_rounded, color: primaryBlue),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Duration (Date Interval with Time)
              _buildSectionCard(
                isDark: isDark,
                title: 'Duration',
                icon: Icons.access_time_filled_rounded,
                subtitle: 'Select date interval and timings',
                child: InkWell(
                  onTap: _pickDateInterval,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: primaryBlue.withValues(alpha: 0.2),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded,
                                color: primaryBlue, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _startDate != null && _startTime != null
                                    ? 'From: ${_formatDateTimeDisplay(_startDate!, _startTime!)}'
                                    : 'Select Start Date & Time',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.event_available_rounded,
                                color: primaryGreen, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _endDate != null && _endTime != null
                                    ? 'To:       ${_formatDateTimeDisplay(_endDate!, _endTime!)}'
                                    : 'Select End Date & Time',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Tap to change date interval & time',
                              style: TextStyle(
                                color: primaryBlue,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Location (manual entry)
              _buildSectionCard(
                isDark: isDark,
                title: 'Location',
                icon: Icons.location_on_rounded,
                child: TextFormField(
                  controller: _locationController,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter exhibition location';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: 'e.g. Calicut Trade Centre, Mini Bypass Road',
                    prefixIcon: const Icon(Icons.pin_drop_rounded, color: primaryBlue),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Select Users Section
              _buildSectionCard(
                isDark: isDark,
                title: 'Assign Users',
                icon: Icons.group_rounded,
                subtitle: 'Selected users can take orders for this exhibition',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _openUserSelector,
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                      label: Text(
                        _selectedUsers.isEmpty
                            ? 'Select Users'
                            : 'Modify Users (${_selectedUsers.length} Selected)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (_selectedUsers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: branchCounts.entries.map((entry) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? primaryGreen.withValues(alpha: 0.2)
                                  : primaryGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: primaryGreen.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              '${entry.key}: ${entry.value}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? primaryGreen : Colors.green[800],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Save Button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveExhibition,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
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
                      : Text(
                          isEditing ? 'Update Exhibition' : 'Create Exhibition',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    required IconData icon,
    String? subtitle,
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
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
