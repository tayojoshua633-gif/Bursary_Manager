// lib/screens/stock/supplier_form_screen.dart
import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';

class SupplierFormScreen extends StatefulWidget {
  final Map<String, dynamic>? supplier;

  const SupplierFormScreen({super.key, this.supplier});

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _formKey = GlobalKey<FormState>();

  final _supplierNameCtrl = TextEditingController();
  final _contactPersonCtrl = TextEditingController();
  final _phoneNumberCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.supplier != null) {
      // Pre-fill for editing
      _supplierNameCtrl.text = widget.supplier!['supplierName'] ?? '';
      _contactPersonCtrl.text = widget.supplier!['contactPerson'] ?? '';
      _phoneNumberCtrl.text = widget.supplier!['phoneNumber'] ?? '';
      _emailCtrl.text = widget.supplier!['email'] ?? '';
      _addressCtrl.text = widget.supplier!['address'] ?? '';
      _notesCtrl.text = widget.supplier!['notes'] ?? '';
    }
  }

  @override
  void dispose() {
    _supplierNameCtrl.dispose();
    _contactPersonCtrl.dispose();
    _phoneNumberCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final payload = {
        'supplierName': _supplierNameCtrl.text.trim(),
        'contactPerson': _contactPersonCtrl.text.trim(),
        'phoneNumber': _phoneNumberCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      };

      if (widget.supplier == null) {
        await _db.insertSupplier(payload);
      } else {
        await _db.updateSupplier(widget.supplier!['id'], payload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.supplier == null
                ? 'Supplier added successfully'
                : 'Supplier updated successfully',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.supplier != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Supplier' : 'Add Supplier'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Supplier Name
            TextFormField(
              controller: _supplierNameCtrl,
              decoration: InputDecoration(
                labelText: 'Supplier Name *',
                prefixIcon: const Icon(Icons.business),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.brown.shade50,
                helperText: 'Company or business name',
              ),
              validator: (v) => v == null || v.isEmpty ? 'Enter supplier name' : null,
              textCapitalization: TextCapitalization.words,
            ),

            const SizedBox(height: 16),

            // Contact Person
            TextFormField(
              controller: _contactPersonCtrl,
              decoration: InputDecoration(
                labelText: 'Contact Person (Optional)',
                prefixIcon: const Icon(Icons.person),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
                helperText: 'Primary contact name',
              ),
              textCapitalization: TextCapitalization.words,
            ),

            const SizedBox(height: 16),

            // Phone Number
            TextFormField(
              controller: _phoneNumberCtrl,
              decoration: InputDecoration(
                labelText: 'Phone Number (Optional)',
                prefixIcon: const Icon(Icons.phone),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: 16),

            // Email
            TextFormField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: 'Email (Optional)',
                prefixIcon: const Icon(Icons.email),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                if (!v.contains('@')) return 'Enter valid email';
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Address
            TextFormField(
              controller: _addressCtrl,
              decoration: InputDecoration(
                labelText: 'Address (Optional)',
                prefixIcon: const Icon(Icons.location_on),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: 'Notes (Optional)',
                prefixIcon: const Icon(Icons.note),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
                helperText: 'Additional information about the supplier',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving...' : 'Save Supplier'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
