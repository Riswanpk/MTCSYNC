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
          ),
          backgroundColor: const Color(0xFF2C3E50),
        ),
        backgroundColor: const Color(0xFFE3E8EA),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                color: const Color(0xFFF7F2F2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detail('Form Type', data['formType']),
                      _detail(
                        (data['formType'] == 'Hotel / Resort Customer')
                            ? 'Firm Name'
                            : 'Shop Name',
                        (data['formType'] == 'Hotel / Resort Customer')
                            ? data['firmName']
                            : data['shopName'],
                      ),
                      if (data['formType'] == 'Hotel / Resort Customer') ...[
                        _detail('Place', data['place']),
                        _detail('Contact Person', data['contactPerson']),
                        _detail('Contact Number', data['contactNumber']),
                        _detail('Category', data['category']),
                        _detail('Feedback Rating', data['feedbackRating']),
                      ],
                      _detail('Phone No', data['phoneNo']),
                      _detail('Last Item Purchased Date', _formatDateOrString(data['lastItemPurchasedDate'], data['lastPurchasedMonth'])),
                      _detail('Last Purchased Item', data['lastPurchasedItem']),
                      _detail('Current Enquiries', data['currentEnquiries']),
                      _detail('Current Enquiry', data['currentEnquiry']), // For hotel/resort
                      _detail('Confirmed Order', data['confirmedOrder']),
                      _detail('Other Purchases', data['otherPurchases'] == 'yes' ? 'Yes' : (data['otherPurchases'] == 'no' ? 'No' : null)),
                      _detail('Reason for Other Purchase', data['otherPurchasesReason']),
                      _detail('Upcoming Big Events Date', _formatDate(data['upcomingEventDate'])),
                      _detail('Upcoming Big Events Details', data['upcomingEvents']),
                      _detail('New Product Suggestion', data['newProductSuggestion']),
                      _detail('Upcoming Trends', data['upcomingTrends']),
                      _detail('Any Suggestion', data['anySuggestion']), // For hotel/resort
                      _detail('Feedback', data['feedback']),
                      _detail('Branch', data['branch']),
                      _detail('Username', data['username']),
                      _detail('User ID', data['userid']),
                      const SizedBox(height: 16),
                      if (data['locationString'] != null && data['locationString'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => _openMap(context, data['locationString']),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      data['locationString'],
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                        fontSize: 15,
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

  Widget _detail(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 16, color: Color(0xFF2C3E50)),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: value.toString(),
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          ],
        ),
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