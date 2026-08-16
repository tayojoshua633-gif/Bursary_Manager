// lib/screens/parents/parent_form_screen.dart

import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/parent.dart';

class ParentFormScreen extends StatefulWidget {
  final Parent? parent; // For editing existing parent

  const ParentFormScreen({super.key, this.parent});

  @override
  State<ParentFormScreen> createState() => _ParentFormScreenState();
}

class _ParentFormScreenState extends State<ParentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  // Controllers
  final _parentNameCtrl = TextEditingController();
  final _phoneNumberCtrl = TextEditingController();
  final _phoneNumber2Ctrl = TextEditingController();
  final _homeAddressCtrl = TextEditingController();
  final _occupationCtrl = TextEditingController();
  final _officeAddressCtrl = TextEditingController();
  final _emailAddressCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.parent != null) {
      _loadParentData();
    }
  }

  void _loadParentData() {
    final parent = widget.parent!;
    _parentNameCtrl.text = parent.parentName;
    _phoneNumberCtrl.text = parent.phoneNumber;
    _phoneNumber2Ctrl.text = parent.phoneNumber2 ?? '';
    _homeAddressCtrl.text = parent.homeAddress;
    _occupationCtrl.text = parent.occupation ?? '';
    _officeAddressCtrl.text = parent.officeAddress ?? '';
    _emailAddressCtrl.text = parent.emailAddress ?? '';
  }

  @override
  void dispose() {
    _parentNameCtrl.dispose();
    _phoneNumberCtrl.dispose();
    _phoneNumber2Ctrl.dispose();
    _homeAddressCtrl.dispose();
    _occupationCtrl.dispose();
    _officeAddressCtrl.dispose();
    _emailAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final parentData = {
        'parentName': _parentNameCtrl.text.trim(),
        'phoneNumber': _phoneNumberCtrl.text.trim(),
        'phoneNumber2': _phoneNumber2Ctrl.text.trim().isEmpty ? null : _phoneNumber2Ctrl.text.trim(),
        'homeAddress': _homeAddressCtrl.text.trim(),
        'occupation': _occupationCtrl.text.trim().isEmpty ? null : _occupationCtrl.text.trim(),
        'officeAddress': _officeAddressCtrl.text.trim().isEmpty ? null : _officeAddressCtrl.text.trim(),
        'emailAddress': _emailAddressCtrl.text.trim().isEmpty ? null : _emailAddressCtrl.text.trim(),
      };

      if (widget.parent == null) {
        // Create new parent
        await _db.insertParent(parentData);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parent added successfully!')),
        );
      } else {
        // Update existing parent
        await _db.updateParent(widget.parent!.id!, parentData);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parent updated successfully!')),
        );
      }

      Navigator.pop(context, true); // Return true to indicate success
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving parent: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.parent != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Parent' : 'Add New Parent'),
        backgroundColor: Colors.indigo,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Parent Name
              TextFormField(
                controller: _parentNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Parent Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Parent name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone Number (WhatsApp)
              TextFormField(
                controller: _phoneNumberCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phone Number (WhatsApp) *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  hintText: 'e.g. 08012345678',
                ),
                keyboardType: TextInputType.phone,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Phone number is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone Number 2 (Optional)
              TextFormField(
                controller: _phoneNumber2Ctrl,
                decoration: const InputDecoration(
                  labelText: 'Phone Number 2 (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_android),
                  hintText: 'e.g. 08087654321',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              // Home Address
              TextFormField(
                controller: _homeAddressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Parent Address *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.home),
                ),
                maxLines: 2,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Home address is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Occupation (Optional)
              TextFormField(
                controller: _occupationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Occupation (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
                ),
              ),
              const SizedBox(height: 16),

              // Office Address (Optional)
              TextFormField(
                controller: _officeAddressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Office Address (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Email Address (Optional)
              TextFormField(
                controller: _emailAddressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email Address (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                  hintText: 'e.g. parent@email.com',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (val) {
                  if (val != null && val.trim().isNotEmpty) {
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                      return 'Enter a valid email address';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          isEdit ? 'UPDATE PARENT' : 'ADD PARENT',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
