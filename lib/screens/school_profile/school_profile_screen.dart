// lib/screens/school_profile/school_profile_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../db/database_helper.dart';

class SchoolProfileScreen extends StatefulWidget {
  const SchoolProfileScreen({super.key});

  @override
  State<SchoolProfileScreen> createState() => _SchoolProfileScreenState();
}

class _SchoolProfileScreenState extends State<SchoolProfileScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameCtrl = TextEditingController();
  final _shortNameCtrl = TextEditingController();
  final _mottoCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _logoPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // -------------------------------------------------------------------
  // LOAD PROFILE
  // -------------------------------------------------------------------
  Future<void> _loadProfile() async {
    final p = await _db.getSchoolProfile();

    if (p != null) {
      _nameCtrl.text = p['name'] ?? "";
      _shortNameCtrl.text = p['shortName'] ?? "";
      _mottoCtrl.text = p['motto'] ?? "";
      _addressCtrl.text = p['address'] ?? "";
      _phoneCtrl.text = p['phone'] ?? "";
      _emailCtrl.text = p['email'] ?? "";
      _logoPath = p['logoPath'];
    }

    if (mounted) setState(() => _loading = false);
  }

  // -------------------------------------------------------------------
  // PICK LOGO
  // -------------------------------------------------------------------
  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final f = await picker.pickImage(source: ImageSource.gallery);

    if (f != null) {
      setState(() => _logoPath = f.path);
    }
  }

  // -------------------------------------------------------------------
  // SAVE PROFILE
  // -------------------------------------------------------------------
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      "name": _nameCtrl.text.trim(),
      "shortName": _shortNameCtrl.text.trim(),
      "motto": _mottoCtrl.text.trim(),
      "address": _addressCtrl.text.trim(),
      "phone": _phoneCtrl.text.trim(),
      "email": _emailCtrl.text.trim(),
      "logoPath": _logoPath,
    };

    await _db.saveSchoolProfile(data);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("School profile saved successfully")),
    );
  }

  // -------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final hasLogo = _logoPath != null && File(_logoPath!).existsSync();

    return Scaffold(
      appBar: AppBar(title: const Text("School Profile")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // ====================== LOGO CARD ======================
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            hasLogo
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      File(_logoPath!),
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(Icons.school, size: 80),

                            const SizedBox(height: 10),

                            TextButton.icon(
                              icon: const Icon(Icons.image),
                              label: const Text("Change Logo"),
                              onPressed: _pickLogo,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ====================== SCHOOL INFO ======================
                    _sectionCard(
                      "School Information",
                      Column(
                        children: [
                          _input(_nameCtrl, "School Name", requiredField: true),
                          const SizedBox(height: 12),

                          _input(_shortNameCtrl,
                              "School Short Name (e.g. DAWOT)",
                              requiredField: true),
                          const SizedBox(height: 12),

                          _input(_mottoCtrl, "Motto"),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ====================== CONTACT INFO ======================
                    _sectionCard(
                      "Contact Information",
                      Column(
                        children: [
                          _input(_addressCtrl, "Address",
                              requiredField: true, maxLines: 2),
                          const SizedBox(height: 12),

                          _input(_phoneCtrl, "Phone Number"),
                          const SizedBox(height: 12),

                          _input(_emailCtrl, "Email"),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),

                    // ====================== SAVE BUTTON ======================
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _save,
                        child: const Text("Save Profile"),
                      ),
                    )
                  ],
                ),
              ),
            ),
    );
  }

  // -------------------------------------------------------------------
  // REUSABLE WIDGETS
  // -------------------------------------------------------------------
  Widget _sectionCard(String title, Widget child) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String label,
      {bool requiredField = false, int maxLines = 1}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      validator: requiredField
          ? (v) => (v == null || v.isEmpty) ? "Required" : null
          : null,
    );
  }
}
