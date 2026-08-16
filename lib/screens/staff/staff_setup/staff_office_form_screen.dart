// lib/screens/staff/staff_setup/staff_office_form_screen.dart
import 'package:flutter/material.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff_office.dart';

class StaffOfficeFormScreen extends StatefulWidget {
  final StaffOffice? office;

  const StaffOfficeFormScreen({super.key, this.office});

  @override
  State<StaffOfficeFormScreen> createState() => _StaffOfficeFormScreenState();
}

class _StaffOfficeFormScreenState extends State<StaffOfficeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dbHelper = DatabaseHelper();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  bool get _isEditing => widget.office != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.office!.name;
      _descriptionController.text = widget.office!.description ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_isEditing) {
        await _dbHelper.updateStaffOffice(widget.office!.id!, {
          'name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
        });
      } else {
        await _dbHelper.insertStaffOffice({
          'name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Office updated' : 'Office created'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Office' : 'Add Office'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Office Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.business),
                      ),
                      validator: (v) =>
                          v?.isEmpty == true ? 'Office name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: Text(_isEditing ? 'Update Office' : 'Create Office'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
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
