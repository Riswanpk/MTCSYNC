import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../Leads/leadsform.dart';

class AddToLeadsButton extends StatefulWidget {
  final Map<String, dynamic> customer;
  final bool called;
  final bool remarksEntered;
  final bool remarksSaved;
  final Color primaryColor;
  final VoidCallback? onLeadAdded;

  const AddToLeadsButton({
    super.key,
    required this.customer,
    required this.called,
    required this.remarksEntered,
    required this.remarksSaved,
    required this.primaryColor,
    this.onLeadAdded,
  });

  @override
  State<AddToLeadsButton> createState() => _AddToLeadsButtonState();
}

class _AddToLeadsButtonState extends State<AddToLeadsButton> {
  bool _checkingLead = false;
  bool _leadExists = false;

  @override
  void initState() {
    super.initState();
    _leadExists = widget.customer['leadAdded'] == true;
    if (!_leadExists) {
      _checkIfLeadAlreadyExists();
    }
  }

  @override
  void didUpdateWidget(covariant AddToLeadsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customer['leadAdded'] == true && !_leadExists) {
      setState(() {
        _leadExists = true;
      });
    }
  }

  Future<void> _checkIfLeadAlreadyExists() async {
    final phone = widget.customer['lastCalledNumber'] ??
        widget.customer['contact1'] ??
        widget.customer['contact'] ??
        widget.customer['phone'];
    if (phone == null || phone.toString().trim().isEmpty) return;

    final clean = phone.toString().replaceAll(RegExp(r'\D'), '');
    final last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;

    setState(() => _checkingLead = true);
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final nextMonth = (now.month == 12)
          ? DateTime(now.year + 1, 1, 1)
          : DateTime(now.year, now.month + 1, 1);

      final snap = await FirebaseFirestore.instance
          .collection('follow_ups')
          .where('source', isEqualTo: 'CC')
          .get();

      bool found = false;
      for (final doc in snap.docs) {
        final data = doc.data();
        DateTime? docDate;
        if (data['created_at'] is Timestamp) {
          docDate = (data['created_at'] as Timestamp).toDate();
        } else if (data['date'] is Timestamp) {
          docDate = (data['date'] as Timestamp).toDate();
        } else if (data['date'] is String) {
          docDate = DateTime.tryParse(data['date']);
        }

        // Only consider leads created in the current month
        if (docDate != null) {
          if (docDate.isBefore(startOfMonth) || !docDate.isBefore(nextMonth)) {
            continue;
          }
        }

        final docPhone = (data['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        if (docPhone.isNotEmpty && last10.isNotEmpty && docPhone.endsWith(last10)) {
          found = true;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _leadExists = found || widget.customer['leadAdded'] == true;
          if (found) {
            widget.customer['leadAdded'] = true;
          }
          _checkingLead = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkingLead = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.called &&
        widget.remarksEntered &&
        widget.remarksSaved &&
        !_leadExists &&
        !_checkingLead;

    final String buttonText = _checkingLead
        ? 'Checking...'
        : _leadExists
            ? 'Lead Added'
            : 'Add To Leads';

    final IconData buttonIcon = _leadExists ? Icons.check_circle : Icons.add;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            gradient: enabled
                ? LinearGradient(
                    colors: [
                      widget.primaryColor,
                      widget.primaryColor.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: enabled ? null : Colors.grey[400],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled
                  ? () async {
                      String? phone = widget.customer['lastCalledNumber'] ??
                          widget.customer['contact1'] ??
                          widget.customer['contact'] ??
                          widget.customer['phone'];
                      String? name = widget.customer['name'];
                      String? address = widget.customer['address'];
                      Map<String, dynamic>? customerData;

                      if (phone != null && phone.isNotEmpty) {
                        final snap = await FirebaseFirestore.instance
                            .collection('customer')
                            .where('phone', isEqualTo: phone)
                            .limit(1)
                            .get();
                        if (snap.docs.isNotEmpty) {
                          customerData = snap.docs.first.data();
                        }
                      }

                      final prefillName = customerData?['name'] ?? name ?? '';
                      final prefillPhone = customerData?['phone'] ?? phone ?? '';
                      final prefillAddress = customerData?['address'] ?? address ?? '';

                      if (context.mounted) {
                        final result = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => FollowUpForm(
                              key: UniqueKey(),
                              initialName: prefillName,
                              initialPhone: prefillPhone,
                              initialAddress: prefillAddress,
                              source: 'CC',
                            ),
                          ),
                        );

                        if (result == true || result == 'saved') {
                          if (mounted) {
                            setState(() {
                              _leadExists = true;
                              widget.customer['leadAdded'] = true;
                            });
                          }
                          if (widget.onLeadAdded != null) {
                            widget.onLeadAdded!();
                          }
                        }
                      }
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_checkingLead)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      )
                    else
                      Icon(buttonIcon,
                          color: enabled || _leadExists ? Colors.white : Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      buttonText,
                      style: TextStyle(
                        color: enabled || _leadExists ? Colors.white : Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
