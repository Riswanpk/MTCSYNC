import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HotelResortCustomerForm extends StatefulWidget {
  final String username;
  final String userid;
  final String branch;

  const HotelResortCustomerForm({
    super.key,
    required this.username,
    required this.userid,
    required this.branch,
  });

  @override
  State<HotelResortCustomerForm> createState() => _HotelResortCustomerFormState();
}

class _HotelResortCustomerFormState extends State<HotelResortCustomerForm> {
  final _formKey = GlobalKey<FormState>();
  String shopName = '';
  DateTime? date;
  String firmName = '';
  String place = '';
  String contactPerson = '';
  String contactNumber = '';
  String category = '';
  String currentEnquiry = '';
  String confirmedOrder = '';
  String newProductSuggestion = '';
  String feedback1 = '';
  String feedback2 = '';
  String feedback3 = '';
  String feedback4 = '';
  String feedback5 = '';
  String anySuggestion = '';
  bool isLoading = false;

  InputDecoration _inputDecoration(String label, {bool required = false}) => InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: const TextStyle(
          fontSize: 16,
          fontFamily: 'Electorize',
        ),
        filled: true,
        fillColor: const Color(0xFFF7F2F2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      );

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || category.isEmpty || date == null) {
      setState(() {}); // Show error
      return;
    }
    setState(() => isLoading = true);

    await FirebaseFirestore.instance.collection('marketing').add({
      'formType': 'Hotel / Resort Customer',
      'username': widget.username,
      'userid': widget.userid,
      'branch': widget.branch,
      'shopName': shopName,
      'date': date,
      'firmName': firmName,
      'place': place,
      'contactPerson': contactPerson,
      'contactNumber': contactNumber,
      'category': category,
      'currentEnquiry': currentEnquiry,
      'confirmedOrder': confirmedOrder,
      'newProductSuggestion': newProductSuggestion,
      'feedback1': feedback1,
      'feedback2': feedback2,
      'feedback3': feedback3,
      'feedback4': feedback4,
      'feedback5': feedback5,
      'anySuggestion': anySuggestion,
      'timestamp': FieldValue.serverTimestamp(),
    });

    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Form submitted successfully!')),
    );
    _formKey.currentState!.reset();
    setState(() {
      category = '';
      date = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Electorize'),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // SHOP NAME
                    TextFormField(
                      decoration: _inputDecoration('SHOP NAME', required: true),
                      validator: (v) => v == null || v.isEmpty ? 'Enter shop name' : null,
                      onChanged: (v) => shopName = v,
                    ),
                    const SizedBox(height: 16),

                    // DATE
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          setState(() {
                            date = picked;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: _inputDecoration('DATE', required: true),
                        child: Text(
                          date != null
                              ? "${date!.day}/${date!.month}/${date!.year}"
                              : 'Select date',
                          style: TextStyle(
                            color: date != null ? Colors.black : Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                    if (date == null)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 8, top: 4),
                        child: Text(
                          'Please select a date',
                          style: TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Electorize'),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // FIRM NAME
                    TextFormField(
                      decoration: _inputDecoration('FIRM NAME', required: true),
                      validator: (v) => v == null || v.isEmpty ? 'Enter firm name' : null,
                      onChanged: (v) => firmName = v,
                    ),
                    const SizedBox(height: 16),

                    // PLACE
                    TextFormField(
                      decoration: _inputDecoration('PLACE', required: true),
                      validator: (v) => v == null || v.isEmpty ? 'Enter place' : null,
                      onChanged: (v) => place = v,
                    ),
                    const SizedBox(height: 16),

                    // CONTACT PERSON NAME
                    TextFormField(
                      decoration: _inputDecoration('CONTACT PERSON NAME', required: true),
                      validator: (v) => v == null || v.isEmpty ? 'Enter contact person name' : null,
                      onChanged: (v) => contactPerson = v,
                    ),
                    const SizedBox(height: 16),

                    // CONTACT NUMBER
                    TextFormField(
                      decoration: _inputDecoration('CONTACT NUMBER', required: true),
                      keyboardType: TextInputType.phone,
                      validator: (v) => v == null || v.isEmpty ? 'Enter contact number' : null,
                      onChanged: (v) => contactNumber = v,
                    ),
                    const SizedBox(height: 16),

                    // CATEGORY
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'CATEGORY *',
                        style: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'Electorize',
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('HOTEL', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'HOTEL',
                          groupValue: category,
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('RESORT', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'RESORT',
                          groupValue: category,
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('RESTAURANT', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'RESTAURANT',
                          groupValue: category,
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('AUDITORIUM', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'AUDITORIUM',
                          groupValue: category,
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                        RadioListTile<String>(
                          title: const Text('OTHERS', style: TextStyle(fontFamily: 'Electorize')),
                          value: 'OTHERS',
                          groupValue: category,
                          onChanged: (v) => setState(() => category = v ?? ''),
                        ),
                      ],
                    ),
                    if (category.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 8),
                        child: Text(
                          'Please select a category',
                          style: TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Electorize'),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // CURRENT ENQUIRY
                    TextFormField(
                      decoration: _inputDecoration('CURRENT ENQUIRY', required: true),
                      validator: (v) => v == null || v.isEmpty ? 'Enter current enquiry' : null,
                      onChanged: (v) => currentEnquiry = v,
                    ),
                    const SizedBox(height: 16),

                    // CONFIRMED ORDER
                    TextFormField(
                      decoration: _inputDecoration('CONFIRMED ORDER'),
                      onChanged: (v) => confirmedOrder = v,
                    ),
                    const SizedBox(height: 16),

                    // NEW PRODUCT SUGGESTION
                    TextFormField(
                      decoration: _inputDecoration('NEW PRODUCT SUGGESTION', required: true),
                      validator: (v) => v == null || v.isEmpty ? 'Enter new product suggestion' : null,
                      onChanged: (v) => newProductSuggestion = v,
                    ),
                    const SizedBox(height: 16),

                    // CUSTOMER FEEDBACK ABOUT OUR PRODUCT & SERVICE (1-5)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'CUSTOMER FEEDBACK ABOUT OUR PRODUCT & SERVICE',
                        style: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'Electorize',
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    TextFormField(
                      decoration: _inputDecoration('1'),
                      onChanged: (v) => feedback1 = v,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      decoration: _inputDecoration('2'),
                      onChanged: (v) => feedback2 = v,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      decoration: _inputDecoration('3'),
                      onChanged: (v) => feedback3 = v,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      decoration: _inputDecoration('4'),
                      onChanged: (v) => feedback4 = v,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      decoration: _inputDecoration('5'),
                      onChanged: (v) => feedback5 = v,
                    ),
                    const SizedBox(height: 16),

                    // ANY SUGGESTION
                    TextFormField(
                      decoration: _inputDecoration('ANY SUGGESTION'),
                      onChanged: (v) => anySuggestion = v,
                    ),
                    const SizedBox(height: 28),

                    ElevatedButton(
                      onPressed: _submitForm,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: const Text('Submit'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}