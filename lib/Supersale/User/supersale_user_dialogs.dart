import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'supersale_phone_utils.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class DeliveryConfirmationResult {
  final int deliveredQty;
  final String billedPhone;
  final DateTime? nextReminderDate;

  DeliveryConfirmationResult({
    required this.deliveredQty,
    required this.billedPhone,
    this.nextReminderDate,
  });
}

class SupersaleDialogs {
  /// Shows dialog to choose between 'booking' and 'spot_sale'.
  static Future<String?> showSaleTypeDialog(BuildContext context) async {
    String selectedType = 'booking';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Select Sale Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: Text(
                      'Booking',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      'Standard booking (Default)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    value: 'booking',
                    groupValue: selectedType,
                    activeColor: primaryBlue,
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedType = val);
                      }
                    },
                  ),
                  RadioListTile<String>(
                    title: Text(
                      'Spot-sale',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      'Directly delivered, advance disabled & same day delivery date',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    value: 'spot_sale',
                    groupValue: selectedType,
                    activeColor: primaryBlue,
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedType = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, selectedType),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Shows the cancel booking dialog asking for a mandatory cancellation reason.
  static Future<String?> showCancelBookingDialog(BuildContext context) async {
    final cancelController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter the cancellation reason (mandatory):'),
              const SizedBox(height: 12),
              TextFormField(
                controller: cancelController,
                decoration: const InputDecoration(
                  labelText: 'Cancellation Reason',
                  hintText: 'Enter reason',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter cancellation reason';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Booking'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Cancel Booking', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      return cancelController.text.trim();
    }
    return null;
  }

  /// Shows the confirm delivery dialog with billed phone and partial delivery options.
  static Future<DeliveryConfirmationResult?> showConfirmDeliveryDialog({
    required BuildContext context,
    required String customerName,
    required String item,
    required int quantity,
    required dynamic initialDeliveryReminder,
  }) async {
    final phoneController = TextEditingController();
    final quantityController = TextEditingController(text: '$quantity');
    final formKey = GlobalKey<FormState>();
    DateTime? nextReminderDate = (initialDeliveryReminder is Timestamp)
        ? initialDeliveryReminder.toDate()
        : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final int currentDeliveredQty = int.tryParse(quantityController.text.trim()) ?? quantity;
          final bool isPartial = quantity > 1 && currentDeliveredQty < quantity;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Confirm Delivery', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer: $customerName',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      'Item: $item (Total Booked: $quantity)',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    if (quantity > 1) ...[
                      TextFormField(
                        controller: quantityController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Delivering Quantity (Max $quantity)',
                          hintText: 'Enter quantity delivered now',
                          prefixIcon: const Icon(Icons.inventory_2_rounded, size: 20),
                          border: const OutlineInputBorder(),
                          helperText: isPartial
                              ? 'Partial Delivery: ${quantity - currentDeliveredQty} will remain pending'
                              : 'Full Delivery: all $quantity units delivered',
                          helperStyle: TextStyle(
                            color: isPartial ? Colors.orange[800] : Colors.green[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onChanged: (val) => setDialogState(() {}),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter quantity';
                          }
                          final val = int.tryParse(value.trim());
                          if (val == null || val <= 0) {
                            return 'Quantity must be greater than 0';
                          }
                          if (val > quantity) {
                            return 'Cannot deliver more than $quantity';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        TenDigitPhoneInputFormatter(),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Billed Phone',
                        hintText: 'Enter 10-digit phone number',
                        prefixIcon: Icon(Icons.phone_rounded, size: 20),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter phone number';
                        }
                        final digits = SupersalePhoneUtils.extract10Digits(value);
                        if (digits.length != 10) {
                          return 'Please enter exactly 10 digits';
                        }
                        return null;
                      },
                    ),
                    if (isPartial) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 16, color: Colors.orange),
                                SizedBox(width: 6),
                                Text(
                                  'Next Delivery / Reminder Date',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate: nextReminderDate ?? DateTime.now().add(const Duration(days: 2)),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (pickedDate != null && context.mounted) {
                                  final pickedTime = await showTimePicker(
                                    context: context,
                                    initialTime: nextReminderDate != null
                                        ? TimeOfDay.fromDateTime(nextReminderDate!)
                                        : const TimeOfDay(hour: 10, minute: 0),
                                  );
                                  setDialogState(() {
                                    nextReminderDate = DateTime(
                                      pickedDate.year,
                                      pickedDate.month,
                                      pickedDate.day,
                                      pickedTime?.hour ?? 10,
                                      pickedTime?.minute ?? 0,
                                    );
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      nextReminderDate != null
                                          ? DateFormat('dd MMM yyyy, hh:mm a').format(nextReminderDate!)
                                          : 'Select Next Delivery Date',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: nextReminderDate != null
                                            ? (isDark ? Colors.white : Colors.black87)
                                            : Colors.grey,
                                      ),
                                    ),
                                    const Icon(Icons.edit_calendar_rounded, size: 16, color: primaryBlue),
                                  ],
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  isPartial ? 'Deliver ($currentDeliveredQty)' : 'Deliver All',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      final int deliveredQty = int.tryParse(quantityController.text.trim()) ?? quantity;
      final String billedPhoneText = SupersalePhoneUtils.extract10Digits(phoneController.text.trim());
      return DeliveryConfirmationResult(
        deliveredQty: deliveredQty,
        billedPhone: billedPhoneText,
        nextReminderDate: nextReminderDate,
      );
    }
    return null;
  }
}
