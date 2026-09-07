import 'package:flutter/material.dart';

class CustomerHeaderCard extends StatelessWidget {
  final String? customerName;
  final String? contact1;
  final String? contact2;
  final bool called;
  final Color primaryColor;
  final VoidCallback onCallPressed;
  final bool isCallDisabled;

  const CustomerHeaderCard({
    Key? key,
    required this.customerName,
    required this.contact1,
    required this.contact2,
    required this.called,
    required this.primaryColor,
    required this.onCallPressed,
    this.isCallDisabled = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCallDisabled
                    ? Icons.hourglass_top_rounded
                    : (called ? Icons.check_circle : Icons.person),
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (customerName != null) ...[
              Text(
                customerName!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (contact1 != null && contact1!.isNotEmpty)
                isCallDisabled
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(25),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onCallPressed,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.phone_disabled, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text(
                                      'Approval Pending',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : called
                        ? Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(25),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: null,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.phone, color: primaryColor),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Call Completed',
                                              style: TextStyle(
                                                color: primaryColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(25),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        primaryColor,
                                        primaryColor.withValues(alpha: 0.8),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: onCallPressed,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.phone, color: Colors.white),
                                            SizedBox(width: 8),
                                            Text(
                                              'Call Again',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    primaryColor,
                                    primaryColor.withValues(alpha: 0.8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: onCallPressed,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.phone, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text(
                                          'Make Call',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
            ],
          ],
        ),
      ),
    );
  }
}
