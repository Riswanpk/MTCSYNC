import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../Leads/leadsform.dart';

class AddToLeadsButton extends StatelessWidget {
  final Map<String, dynamic> customer;
  final bool called;
  final bool remarksEntered;
  final bool remarksSaved;
  final Color primaryColor;

  const AddToLeadsButton({
    Key? key,
    required this.customer,
    required this.called,
    required this.remarksEntered,
    required this.remarksSaved,
    required this.primaryColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final enabled = called && remarksEntered && remarksSaved;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            gradient: enabled
                ? LinearGradient(
                    colors: [
                      primaryColor,
                      primaryColor.withValues(alpha: 0.8),
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
                      String? phone = customer['lastCalledNumber'] ?? customer['contact1'] ?? customer['contact'] ?? customer['phone'];
                      String? name = customer['name'];
                      String? address = customer['address'];
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
                        Navigator.of(context).push(
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
                      }
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: enabled ? Colors.white : Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      'Add To Leads',
                      style: TextStyle(
                        color: enabled ? Colors.white : Colors.white70,
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
