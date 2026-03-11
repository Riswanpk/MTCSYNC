import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';


class ViewerMarketingDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  const ViewerMarketingDetailPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Electorize'),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            (data['formType'] == 'Hotel / Resort Customer')
                ? (data['firmName'] ?? 'Form Details')
                : (data['shopName'] ?? 'Form Details'),
            style: const TextStyle(fontFamily: 'Electorize', fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          centerTitle: true,
          foregroundColor: Colors.white,
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0F0F1E)
            : const Color(0xFFF0F2F5),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1A1A2E)
                    : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 4,
                shadowColor: const Color(0xFF1A1A2E).withOpacity(0.12),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detail(context, 'Form Type', data['formType']),
                      _detail(
                        context,
                        (data['formType'] == 'Hotel / Resort Customer')
                            ? 'Firm Name'
                            : 'Shop Name',
                        (data['formType'] == 'Hotel / Resort Customer')
                            ? data['firmName']
                            : data['shopName'],
                      ),
                      if (data['formType'] == 'Hotel / Resort Customer') ...[
                        _detail(context, 'Place', data['place']),
                        _detail(context, 'Contact Person', data['contactPerson']),
                        _detail(context, 'Contact Number', data['contactNumber']),
                        _detail(context, 'Category', data['category']),
                        _detail(context, 'Feedback Rating', data['feedbackRating']),
                      ],
                      _detail(context, 'Phone No', data['phoneNo']),
                      _detail(context, 'Last Item Purchased Date', _formatDateOrString(data['lastItemPurchasedDate'], data['lastPurchasedMonth'])),
                      _detail(context, 'Last Purchased Item', data['lastPurchasedItem']),
                      _detail(context, 'Current Enquiries', data['currentEnquiries']),
                      _detail(context, 'Current Enquiry', data['currentEnquiry']), // For hotel/resort
                      _detail(context, 'Confirmed Order', data['confirmedOrder']),
                      _detail(context, 'Other Purchases', data['otherPurchases'] == 'yes' ? 'Yes' : (data['otherPurchases'] == 'no' ? 'No' : null)),
                      _detail(context, 'Reason for Other Purchase', data['otherPurchasesReason']),
                      _detail(context, 'Upcoming Big Events Date', _formatDate(data['upcomingEventDate'])),
                      _detail(context, 'Upcoming Big Events Details', data['upcomingEvents']),
                      _detail(context, 'New Product Suggestion', data['newProductSuggestion']),
                      _detail(context, 'Upcoming Trends', data['upcomingTrends']),
                      _detail(context, 'Any Suggestion', data['anySuggestion']), // For hotel/resort
                      _detail(context, 'Feedback', data['feedback']),
                      _detail(context, 'Branch', data['branch']),
                      _detail(context, 'Username', data['username']),
                      _detail(context, 'User ID', data['userid']),
                      const SizedBox(height: 16),
                      if (data['locationString'] != null && data['locationString'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => _openMap(context, data['locationString']),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16213E).withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF16213E).withOpacity(0.12)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A1A2E).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.location_on_rounded, color: Color(0xFF1A1A2E), size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      data['locationString'],
                                      style: const TextStyle(
                                        color: Color(0xFF1A1A2E),
                                        decoration: TextDecoration.underline,
                                        fontSize: 14,
                                        fontFamily: 'Electorize',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // Location info stays above the photo
                      if (data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty)
                        GestureDetector(
                          onTap: () => _showFullScreenImage(context, data['imageUrl']),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              data['imageUrl'],
                              height: 180,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Text('Image not available'),
                            ),
                          ),
                        ),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: Theme.of(context).brightness == Brightness.dark
                    ? [const Color(0xFF0EA5E9), const Color(0xFF3B82F6)]
                    : [const Color(0xFF1A1A2E), const Color(0xFF16213E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : const Color(0xFF2C3E50),
                  fontFamily: 'Electorize',
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  TextSpan(
                    text: value.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : const Color(0xFF444E5C),
                    ),
                  ),
                ],
              ),
            ),
            ),
          
        ],
      ),
    );
  }

  String _formatDateOrString(dynamic date, dynamic month) {
    if (date != null && date is Timestamp) {
      final d = date.toDate();
      return "${d.day}/${d.month}/${d.year}";
    }
    if (month != null && month.toString().isNotEmpty) {
      return month.toString();
    }
    return '';
  }

  String _formatDate(dynamic date) {
    if (date != null && date is Timestamp) {
      final d = date.toDate();
      return "${d.day}/${d.month}/${d.year}";
    }
    return '';
  }

  Future<void> _openMap(BuildContext context, String locationString) async {
    // Try to extract latitude and longitude from the string
    final latLngReg = RegExp(r'Lat ([\d\.\-]+), Long ([\d\.\-]+)');
    final match = latLngReg.firstMatch(locationString);
    String url;
    if (match != null) {
      final lat = match.group(1);
      final lng = match.group(2);
      url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    } else {
      // Fallback: search the whole string
      url = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(locationString)}';
    }
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text('Image not available', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 30,
              right: 30,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(ctx).pop(),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }
}