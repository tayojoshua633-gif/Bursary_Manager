// lib/screens/students/student_edit_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/student.dart';
import '../../db/database_helper.dart';

class StudentEditScreen extends StatefulWidget {
  final Student student;

  const StudentEditScreen({super.key, required this.student});

  @override
  State<StudentEditScreen> createState() => _StudentEditScreenState();
}

class _StudentEditScreenState extends State<StudentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _db = DatabaseHelper();

  // Controllers
  late TextEditingController _surnameCtrl;
  late TextEditingController _firstNameCtrl;
  late TextEditingController _otherNameCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _parentNameCtrl;
  late TextEditingController _parentPhoneCtrl;
  late TextEditingController _parentEmailCtrl;
  late TextEditingController _parentAddressCtrl;

  String? _gender;
  int? _classId;
  int? _armId;

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];

  String? _photoPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    // Init controllers
    _surnameCtrl = TextEditingController(text: widget.student.surname);
    _firstNameCtrl = TextEditingController(text: widget.student.firstName);
    _otherNameCtrl = TextEditingController(text: widget.student.otherName);
    _dobCtrl = TextEditingController(text: widget.student.dob);
    _addressCtrl = TextEditingController(text: widget.student.address);
    _parentNameCtrl = TextEditingController(text: widget.student.parentName);
    _parentPhoneCtrl = TextEditingController(text: widget.student.parentPhone);
    _parentEmailCtrl = TextEditingController(text: widget.student.parentEmail);
    _parentAddressCtrl = TextEditingController(text: widget.student.parentAddress);

    _gender = widget.student.gender;
    _classId = widget.student.classId;
    _armId = widget.student.armId;
    _photoPath = widget.student.photoPath;

    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final cls = await _db.getClasses();
    setState(() => _classes = cls);

    await _loadArms(_classId!);

    setState(() => _loading = false);
  }

  Future<void> _loadArms(int classId) async {
    final a = await _db.getArms(classId);
    setState(() {
      _arms = a;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1990),
      lastDate: now,
      initialDate: DateTime.tryParse(widget.student.dob) ?? now,
    );

    if (picked != null) {
      _dobCtrl.text = "${picked.year}-${picked.month}-${picked.day}";
    }
  }

  Future<void> _capturePhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera);

    if (file != null) {
      setState(() => _photoPath = file.path);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'surname': _surnameCtrl.text.trim(),
      'firstName': _firstNameCtrl.text.trim(),
      'otherName': _otherNameCtrl.text.trim(),
      'gender': _gender,
      'dob': _dobCtrl.text.trim(),
      'classId': _classId,
      'armId': _armId,
      'address': _addressCtrl.text.trim(),
      'parentName': _parentNameCtrl.text.trim(),
      'parentPhone': _parentPhoneCtrl.text.trim(),
      'parentEmail': _parentEmailCtrl.text.trim(),
      'parentAddress': _parentAddressCtrl.text.trim(),
      'photoPath': _photoPath,
    };

    await _db.updateStudent(widget.student.id!, data);

    if (!mounted) return;

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Edit Student")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
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

              // FORM FIELDS
              TextFormField(
                controller: _surnameCtrl,
                decoration: const InputDecoration(
                    labelText: "Surname", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _firstNameCtrl,
                decoration: const InputDecoration(
                    labelText: "First Name", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _otherNameCtrl,
                decoration: const InputDecoration(
                    labelText: "Other Name", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),

              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                    labelText: "Gender", border: OutlineInputBorder()),
                initialValue: _gender,
                items: const [
                  DropdownMenuItem(value: "Male", child: Text("Male")),
                  DropdownMenuItem(value: "Female", child: Text("Female")),
                ],
                onChanged: (v) => setState(() => _gender = v),
                validator: (v) => v == null ? "Required" : null,
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _dobCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Date of Birth",
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                onTap: _pickDate,
              ),

              const SizedBox(height: 20),

              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                    labelText: "Class", border: OutlineInputBorder()),
                initialValue: _classId,
                items: _classes
                    .map((c) => DropdownMenuItem<int>(
                        value: c['id'], child: Text(c['name'])))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _classId = v;
                    _armId = null;
                  });
                  if (v != null) _loadArms(v);
                },
                validator: (v) => v == null ? "Required" : null,
              ),

              const SizedBox(height: 20),

              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                    labelText: "Arm", border: OutlineInputBorder()),
                initialValue: _armId,
                items: _arms
                    .map((a) => DropdownMenuItem<int>(
                        value: a['id'], child: Text(a['name'])))
                    .toList(),
                onChanged: (v) => setState(() => _armId = v),
                validator: (v) => v == null ? "Required" : null,
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: "Home Address", border: OutlineInputBorder()),
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _parentNameCtrl,
                decoration: const InputDecoration(
                    labelText: "Parent Name", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _parentPhoneCtrl,
                decoration: const InputDecoration(
                    labelText: "Parent Phone", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _parentEmailCtrl,
                decoration: const InputDecoration(
                    labelText: "Parent Email", border: OutlineInputBorder()),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _parentAddressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: "Parent Address", border: OutlineInputBorder()),
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text("Save Changes"),
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
