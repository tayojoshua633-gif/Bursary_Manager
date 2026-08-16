// lib/screens/school_profile/school_profile_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/database_helper_wrapper.dart';

class SchoolProfileScreen extends StatefulWidget {
  const SchoolProfileScreen({super.key});

  @override
  State<SchoolProfileScreen> createState() => _SchoolProfileScreenState();
}

class _SchoolProfileScreenState extends State<SchoolProfileScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameCtrl = TextEditingController();
  final _shortNameCtrl = TextEditingController();
  final _mottoCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // Bank Account Controllers (3 accounts)
  final _bankName1Ctrl = TextEditingController();
  final _accountNumber1Ctrl = TextEditingController();
  final _accountName1Ctrl = TextEditingController();
  final _bankName2Ctrl = TextEditingController();
  final _accountNumber2Ctrl = TextEditingController();
  final _accountName2Ctrl = TextEditingController();
  final _bankName3Ctrl = TextEditingController();
  final _accountNumber3Ctrl = TextEditingController();
  final _accountName3Ctrl = TextEditingController();

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

      // Bank accounts
      _bankName1Ctrl.text = p['bankName1'] ?? "";
      _accountNumber1Ctrl.text = p['accountNumber1'] ?? "";
      _accountName1Ctrl.text = p['accountName1'] ?? "";
      _bankName2Ctrl.text = p['bankName2'] ?? "";
      _accountNumber2Ctrl.text = p['accountNumber2'] ?? "";
      _accountName2Ctrl.text = p['accountName2'] ?? "";
      _bankName3Ctrl.text = p['bankName3'] ?? "";
      _accountNumber3Ctrl.text = p['accountNumber3'] ?? "";
      _accountName3Ctrl.text = p['accountName3'] ?? "";
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
      "bankName1": _bankName1Ctrl.text.trim(),
      "accountNumber1": _accountNumber1Ctrl.text.trim(),
      "accountName1": _accountName1Ctrl.text.trim(),
      "bankName2": _bankName2Ctrl.text.trim(),
      "accountNumber2": _accountNumber2Ctrl.text.trim(),
      "accountName2": _accountName2Ctrl.text.trim(),
      "bankName3": _bankName3Ctrl.text.trim(),
      "accountNumber3": _accountNumber3Ctrl.text.trim(),
      "accountName3": _accountName3Ctrl.text.trim(),
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

                    const SizedBox(height: 20),

                    // ====================== BANKING INFO ======================
                    _sectionCard(
                      "Banking Information",
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add up to 3 bank accounts. These will appear on all bills, receipts and reports.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 16),

                          // Bank Account 1
                          _bankAccountGroup(
                            number: 1,
                            bankNameCtrl: _bankName1Ctrl,
                            accountNumberCtrl: _accountNumber1Ctrl,
                            accountNameCtrl: _accountName1Ctrl,
                          ),

                          const SizedBox(height: 16),
                          Divider(color: Colors.grey.shade300),
                          const SizedBox(height: 16),

                          // Bank Account 2
                          _bankAccountGroup(
                            number: 2,
                            bankNameCtrl: _bankName2Ctrl,
                            accountNumberCtrl: _accountNumber2Ctrl,
                            accountNameCtrl: _accountName2Ctrl,
                          ),

                          const SizedBox(height: 16),
                          Divider(color: Colors.grey.shade300),
                          const SizedBox(height: 16),

                          // Bank Account 3
                          _bankAccountGroup(
                            number: 3,
                            bankNameCtrl: _bankName3Ctrl,
                            accountNumberCtrl: _accountNumber3Ctrl,
                            accountNameCtrl: _accountName3Ctrl,
                          ),
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

  Widget _bankAccountGroup({
    required int number,
    required TextEditingController bankNameCtrl,
    required TextEditingController accountNumberCtrl,
    required TextEditingController accountNameCtrl,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance, size: 18, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Text(
              'Bank Account $number',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _input(bankNameCtrl, "Bank Name"),
        const SizedBox(height: 10),
        _input(accountNumberCtrl, "Account Number"),
        const SizedBox(height: 10),
        _input(accountNameCtrl, "Account Name"),
      ],
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
