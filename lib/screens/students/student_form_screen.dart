// lib/screens/students/student_form_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../db/database_helper.dart';

class StudentFormScreen extends StatefulWidget {
  const StudentFormScreen({super.key});

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _db = DatabaseHelper();

  // Controllers
  final _surnameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _otherNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _parentNameCtrl = TextEditingController();
  final _parentPhoneCtrl = TextEditingController();
  final _parentEmailCtrl = TextEditingController();
  final _parentAddressCtrl = TextEditingController();
  final _admCtrl = TextEditingController(); // Admission number

  String? _selectedGender;
  int? _selectedClass;
  int? _selectedArm;

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];

  bool _loading = true;
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _initForm();
  }

  // ----------------------------------------------------------
  // INITIAL LOAD
  // ----------------------------------------------------------
  Future<void> _initForm() async {
    await _loadClasses();
    await _loadAdmissionNumber();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadClasses() async {
    _classes = await _db.getClasses();
  }

  Future<void> _loadArms(int classId) async {
    _arms = await _db.getArms(classId);
    _selectedArm = null;
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------
  // LOAD ADMISSION NUMBER (DB GENERATED)
  // ----------------------------------------------------------
  Future<void> _loadAdmissionNumber() async {
    final adm = await _db.generateAdmissionNumber();
    _admCtrl.text = adm;
  }

  // ----------------------------------------------------------
  // DATE PICKER
  // ----------------------------------------------------------
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
    );

    if (picked != null) {
      _dobCtrl.text =
          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
    }
  }

  // ----------------------------------------------------------
  // PHOTO CAPTURE
  // ----------------------------------------------------------
  Future<void> _capturePhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera);

    if (file != null) {
      setState(() => _photoPath = file.path);
    }
  }

  // ----------------------------------------------------------
  // SAVE STUDENT
  // ----------------------------------------------------------
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_admCtrl.text.trim().isEmpty) {
      _admCtrl.text = await _db.generateAdmissionNumber();
    }

    final data = {
      'admissionNo': _admCtrl.text.trim(),
      'surname': _surnameCtrl.text.trim(),
      'firstName': _firstNameCtrl.text.trim(),
      'otherName': _otherNameCtrl.text.trim(),
      'gender': _selectedGender,
      'dob': _dobCtrl.text.trim(),
      'classId': _selectedClass,
      'armId': _selectedArm,
      'address': _addressCtrl.text.trim(),
      'parentName': _parentNameCtrl.text.trim(),
      'parentPhone': _parentPhoneCtrl.text.trim(),
      'parentEmail': _parentEmailCtrl.text.trim(),
      'parentAddress': _parentAddressCtrl.text.trim(),
      'photoPath': _photoPath,
    };

    await _db.insertStudent(data);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _surnameCtrl.dispose();
    _firstNameCtrl.dispose();
    _otherNameCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    _parentNameCtrl.dispose();
    _parentPhoneCtrl.dispose();
    _parentEmailCtrl.dispose();
    _parentAddressCtrl.dispose();
    _admCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // UI
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("New Student Registration")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PHOTO
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[300],
                      backgroundImage:
                          _photoPath != null ? FileImage(File(_photoPath!)) : null,
                      child: _photoPath == null
                          ? const Icon(Icons.person, size: 60)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt, size: 30),
                      onPressed: _capturePhoto,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ADMISSION NUMBER
              TextFormField(
                controller: _admCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Admission Number",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 20),

              // NAMES
              _input(_surnameCtrl, "Surname", required: true),
              const SizedBox(height: 12),
              _input(_firstNameCtrl, "First Name", required: true),
              const SizedBox(height: 12),
              _input(_otherNameCtrl, "Other Name"),

              const SizedBox(height: 20),

              // GENDER
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: "Gender",
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: "Male", child: Text("Male")),
                  DropdownMenuItem(value: "Female", child: Text("Female")),
                ],
                onChanged: (v) => setState(() => _selectedGender = v),
                validator: (v) => v == null ? "Required" : null,
              ),

              const SizedBox(height: 20),

              // DATE OF BIRTH
              TextFormField(
                controller: _dobCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Date of Birth",
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                onTap: _pickDate,
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),

              const SizedBox(height: 20),

              // CLASS
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: "Class",
                  border: OutlineInputBorder(),
                ),
                items: _classes
                    .map(
                      (c) => DropdownMenuItem<int>(
                        value: c['id'] as int,
                        child: Text(c['name']),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedClass = v;
                    _arms = [];
                    _selectedArm = null;
                  });
                  if (v != null) _loadArms(v);
                },
                validator: (v) => v == null ? "Required" : null,
              ),

              const SizedBox(height: 20),

              // ARM
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: "Arm",
                  border: OutlineInputBorder(),
                ),
                items: _arms
                    .map(
                      (a) => DropdownMenuItem<int>(
                        value: a['id'] as int,
                        child: Text(a['name']),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedArm = v),
                validator: (v) => v == null ? "Required" : null,
              ),

              const SizedBox(height: 20),

              _input(_addressCtrl, "Home Address",
                  required: true, maxLines: 2),

              const SizedBox(height: 20),

              // PARENT INFO
              _input(_parentNameCtrl, "Parent/Guardian Name", required: true),
              const SizedBox(height: 12),
              _input(_parentPhoneCtrl, "Parent Phone", required: true),
              const SizedBox(height: 12),
              _input(_parentEmailCtrl, "Parent Email"),
              const SizedBox(height: 12),
              _input(_parentAddressCtrl, "Parent Address", maxLines: 2),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text("Save Student"),
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // REUSABLE INPUT WIDGET
  // ----------------------------------------------------------
  Widget _input(
    TextEditingController c,
    String label, {
    bool required = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
      ).copyWith(labelText: label),
      validator:
          required ? (v) => (v == null || v.isEmpty) ? "Required" : null : null,
    );
  }
}
