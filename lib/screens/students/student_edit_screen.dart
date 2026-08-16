// lib/screens/students/student_edit_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';

import '../../models/student.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/admission_settings_helper.dart';
import '../../data/database_helper_wrapper.dart';

class StudentEditScreen extends StatefulWidget {
  final Student student;

  const StudentEditScreen({super.key, required this.student});

  @override
  State<StudentEditScreen> createState() => _StudentEditScreenState();
}

class _StudentEditScreenState extends State<StudentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  // Controllers
  late TextEditingController _surnameCtrl;
  late TextEditingController _firstNameCtrl;
  late TextEditingController _otherNameCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _parentNameCtrl;
  late TextEditingController _parentPhoneCtrl;
  late TextEditingController _parentPhone2Ctrl;
  late TextEditingController _parentEmailCtrl;
  late TextEditingController _parentAddressCtrl;
  late TextEditingController _parentOccupationCtrl;
  late TextEditingController _parentOfficeAddressCtrl;
  late TextEditingController _nationalityCtrl;
  late TextEditingController _stateOfOriginCtrl;
  late TextEditingController _lgaCtrl;
  late TextEditingController _admCtrl;
  late TextEditingController _dateOfAdmissionCtrl;
  final TextEditingController _parentSearchCtrl = TextEditingController();

  String? _gender;
  int? _classId;
  int? _armId;
  int? _originalClassId; // Track original class for bill generation
  int? _selectedParentId; // For linking to existing parent

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  List<Map<String, dynamic>> _searchedParents = [];

  String? _photoPath;
  bool _loading = true;
  bool _useExistingParent = false;
  bool _searchingParents = false;
  bool _admissionEditable = false;

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
    _parentPhone2Ctrl = TextEditingController(); // Will be populated if parent exists
    _parentEmailCtrl = TextEditingController(text: widget.student.parentEmail);
    _parentAddressCtrl = TextEditingController(text: widget.student.parentAddress);
    _parentOccupationCtrl = TextEditingController(); // Will be populated if parent exists
    _parentOfficeAddressCtrl = TextEditingController(); // Will be populated if parent exists
    _nationalityCtrl = TextEditingController(text: widget.student.nationality);
    _stateOfOriginCtrl = TextEditingController(text: widget.student.stateOfOrigin);
    _lgaCtrl = TextEditingController(text: widget.student.lga);
    _admCtrl = TextEditingController(text: widget.student.admissionNo);
    _dateOfAdmissionCtrl = TextEditingController(text: widget.student.dateOfAdmission ?? '');

    _gender = widget.student.gender;
    _classId = widget.student.classId;
    _armId = widget.student.armId;
    _photoPath = widget.student.photoPath;
    _originalClassId = widget.student.classId; // Store original class

    _loadClasses();
    _loadExistingParentData(); // Load parent data from parents table
    _loadAdmissionSettings();
  }

  Future<void> _loadAdmissionSettings() async {
    final editable = await AdmissionSettingsHelper.isEditable();
    if (mounted) setState(() => _admissionEditable = editable);
  }

  Future<void> _loadClasses() async {
    final cls = await _db.getClasses();
    setState(() => _classes = cls);

    await _loadArms(_classId!);

    setState(() => _loading = false);
  }

  Future<void> _loadArms(int classId) async {
    // FIXED: Use getArmsByClass instead of getArms
    final a = await _db.getArmsByClass(classId);
    setState(() {
      _arms = a;
    });
  }

  // ----------------------------------------------------------
  // LOAD EXISTING PARENT DATA FROM PARENTS TABLE
  // ----------------------------------------------------------
  Future<void> _loadExistingParentData() async {
    try {
      // Search for parent by phone and name
      if (widget.student.parentPhone.trim().isEmpty) return;

      final parents = await _db.searchParents(widget.student.parentPhone);
      final matchingParent = parents.where((p) =>
        p['phoneNumber'] == widget.student.parentPhone &&
        p['parentName'] == widget.student.parentName
      ).firstOrNull;

      if (matchingParent != null) {
        // Found existing parent - populate additional fields
        setState(() {
          _selectedParentId = matchingParent['id'];
          _useExistingParent = true;
          _parentPhone2Ctrl.text = matchingParent['phoneNumber2'] ?? '';
          _parentOccupationCtrl.text = matchingParent['occupation'] ?? '';
          _parentOfficeAddressCtrl.text = matchingParent['officeAddress'] ?? '';
          // Email and address already populated from student record
        });
      }
    } catch (e) {
      debugPrint('Failed to load existing parent data: $e');
    }
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

  Future<void> _pickAdmissionDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDate: DateTime.tryParse(_dateOfAdmissionCtrl.text) ?? now,
    );

    if (picked != null) {
      _dateOfAdmissionCtrl.text =
          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
    }
  }

  // ----------------------------------------------------------
  // PARENT SEARCH
  // ----------------------------------------------------------
  Future<void> _searchParents(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchedParents = [];
        _searchingParents = false;
      });
      return;
    }

    setState(() => _searchingParents = true);

    try {
      final results = await _db.searchParents(query);
      setState(() {
        _searchedParents = results;
        _searchingParents = false;
      });
    } catch (e) {
      setState(() => _searchingParents = false);
    }
  }

  void _selectParent(Map<String, dynamic> parent) {
    setState(() {
      _selectedParentId = parent['id'];
      _useExistingParent = true;
      _parentNameCtrl.text = parent['parentName'] ?? '';
      _parentPhoneCtrl.text = parent['phoneNumber'] ?? '';
      _parentPhone2Ctrl.text = parent['phoneNumber2'] ?? '';
      _parentEmailCtrl.text = parent['emailAddress'] ?? '';
      _parentAddressCtrl.text = parent['homeAddress'] ?? '';
      _parentOccupationCtrl.text = parent['occupation'] ?? '';
      _parentOfficeAddressCtrl.text = parent['officeAddress'] ?? '';
      _parentSearchCtrl.clear();
      _searchedParents = [];
    });
  }

  void _clearParentSelection() {
    setState(() {
      _selectedParentId = null;
      _useExistingParent = false;
      // Keep the current values - don't clear the form
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_admissionEditable) {
      final newAdmNo = _admCtrl.text.trim();
      if (newAdmNo != widget.student.admissionNo) {
        final allStudents = await _db.getStudents(includeInactive: true);
        final duplicate = allStudents.any((s) =>
            s['id'] != widget.student.id &&
            (s['admissionNo'] as String?)?.trim().toUpperCase() == newAdmNo.toUpperCase());
        if (duplicate) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Admission number "$newAdmNo" is already in use'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    // ALWAYS update or create parent record when parent data exists
    if (_parentNameCtrl.text.trim().isNotEmpty && _parentPhoneCtrl.text.trim().isNotEmpty) {
      try {
        final parentData = {
          'parentName': _parentNameCtrl.text.trim(),
          'phoneNumber': _parentPhoneCtrl.text.trim(),
          'phoneNumber2': _parentPhone2Ctrl.text.trim().isEmpty ? null : _parentPhone2Ctrl.text.trim(),
          'homeAddress': _parentAddressCtrl.text.trim(),
          'occupation': _parentOccupationCtrl.text.trim().isEmpty ? null : _parentOccupationCtrl.text.trim(),
          'officeAddress': _parentOfficeAddressCtrl.text.trim().isEmpty ? null : _parentOfficeAddressCtrl.text.trim(),
          'emailAddress': _parentEmailCtrl.text.trim().isEmpty ? null : _parentEmailCtrl.text.trim(),
        };

        if (_selectedParentId != null) {
          // Update the selected existing parent
          await _db.updateParent(_selectedParentId!, parentData);
        } else {
          // Check if parent exists by phone + name
          final existingParents = await _db.searchParents(_parentPhoneCtrl.text.trim());
          final matchingParent = existingParents.where((p) =>
            p['phoneNumber'] == _parentPhoneCtrl.text.trim() &&
            p['parentName'] == _parentNameCtrl.text.trim()
          ).firstOrNull;

          if (matchingParent != null) {
            // Update existing parent
            await _db.updateParent(matchingParent['id'], parentData);
            _selectedParentId = matchingParent['id'];
          } else {
            // Create new parent record
            await _db.insertParent(parentData);
          }
        }
      } catch (e) {
        debugPrint('Failed to update parent record: $e');
      }
    }

    // Update student record (always update parent data here too for backward compatibility)
    final data = {
      'admissionNo': _admCtrl.text.trim(),
      'surname': _surnameCtrl.text.trim(),
      'firstName': _firstNameCtrl.text.trim(),
      'otherName': _otherNameCtrl.text.trim(),
      'gender': _gender,
      'dob': _dobCtrl.text.trim(),
      'classId': _classId,
      'armId': _armId,
      'address': _addressCtrl.text.trim(),
      'nationality': _nationalityCtrl.text.trim().isEmpty ? null : _nationalityCtrl.text.trim(),
      'stateOfOrigin': _stateOfOriginCtrl.text.trim().isEmpty ? null : _stateOfOriginCtrl.text.trim(),
      'lga': _lgaCtrl.text.trim().isEmpty ? null : _lgaCtrl.text.trim(),
      'parentName': _parentNameCtrl.text.trim(),
      'parentPhone': _parentPhoneCtrl.text.trim(),
      'parentEmail': _parentEmailCtrl.text.trim(),
      'parentAddress': _parentAddressCtrl.text.trim(),
      'photoPath': _photoPath,
      'dateOfAdmission': _dateOfAdmissionCtrl.text.trim().isEmpty ? null : _dateOfAdmissionCtrl.text.trim(),
    };

    await _db.updateStudent(widget.student.id!, data);

    // SYNC PARENT INFO ACROSS ALL SIBLINGS
    // Only sync if the student already had a parent (originalParentPhone is not empty)
    final originalParentPhone = widget.student.parentPhone;
    final newParentPhone = _parentPhoneCtrl.text.trim();

    // Only sync siblings if original parent phone was NOT empty
    // This prevents updating unrelated students who also have empty parent phones
    if (originalParentPhone.isNotEmpty) {
      try {
        // Find all siblings (students with the same original parent phone, excluding current student)
        final allStudents = await _db.getStudents();
        final siblings = allStudents.where((s) =>
          s['id'] != widget.student.id &&
          s['parentPhone'] == originalParentPhone &&
          s['isActive'] == 1
        ).toList();

        if (siblings.isNotEmpty) {
          // Update parent info for all siblings
          final siblingParentData = {
            'parentName': _parentNameCtrl.text.trim(),
            'parentPhone': newParentPhone,
            'parentEmail': _parentEmailCtrl.text.trim(),
            'parentAddress': _parentAddressCtrl.text.trim(),
          };

          for (final sibling in siblings) {
            await _db.updateStudent(sibling['id'], siblingParentData);
          }

          debugPrint('Updated parent info for ${siblings.length} sibling(s)');
        }
      } catch (e) {
        debugPrint('Failed to sync parent info across siblings: $e');
      }
    }

    // AUTO-GENERATE BILL IF CLASS CHANGED
    if (_classId != null && _originalClassId != null && _classId != _originalClassId) {
      try {
        await _autoGenerateBillForStudent(widget.student.id!, _classId!);
      } catch (e) {
        debugPrint('Failed to auto-generate bill after class change: $e');
      }
    }

    if (!mounted) return;

    Navigator.pop(context, true);
  }

  // ----------------------------------------------------------
  // AUTO-GENERATE BILL WHEN CLASS CHANGES
  // ----------------------------------------------------------
  Future<void> _autoGenerateBillForStudent(int studentId, int classId) async {
    // Get active term and session
    final activeTerm = await _db.getActiveTerm();
    final activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";

    if (activeTerm.isEmpty || activeSession.isEmpty) {
      debugPrint('No active term/session - skipping auto-bill generation');
      return;
    }

    // Check if class has assigned fees for this term/session
    final classFees = await _db.getClassFees(
      classId,
      activeTerm,
      activeSession,
    );

    if (classFees.isEmpty) {
      debugPrint('No fees assigned to new class - skipping auto-bill generation');
      return;
    }

    // Calculate previous balance
    final previousBalance = await _db.computeOutstandingBeforeTerm(
      studentId,
      term: activeTerm,
      session: activeSession,
    );

    // Calculate total amount from class fees
    final subtotal = classFees.fold<double>(
      0.0,
      (sum, fee) => sum + ((fee['amount'] as num?)?.toDouble() ?? 0.0),
    );
    final grandTotal = subtotal + previousBalance;

    // Create bill data
    final bill = {
      'studentId': studentId,
      'totalAmount': grandTotal,
      'previousBalance': previousBalance,
      'term': activeTerm,
      'session': activeSession,
      'billDate': DateTime.now().toIso8601String(),
    };

    // Create breakdown data
    final breakdown = classFees.map((fee) {
      return {
        'feeItemId': fee['feeItemId'],
        'amount': fee['amount'],
        'label': '', // Will be populated from fee_items table
      };
    }).toList();

    // Insert or update bill
    await _db.insertStudentBill(bill, breakdown);

    debugPrint('Auto-generated bill for student $studentId after class change to $classId');
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
    _parentPhone2Ctrl.dispose();
    _parentEmailCtrl.dispose();
    _parentAddressCtrl.dispose();
    _parentOccupationCtrl.dispose();
    _parentOfficeAddressCtrl.dispose();
    _nationalityCtrl.dispose();
    _stateOfOriginCtrl.dispose();
    _lgaCtrl.dispose();
    _admCtrl.dispose();
    _dateOfAdmissionCtrl.dispose();
    _parentSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Edit Student")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // PHOTO (display only - no editing)
              Center(
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey[300],
                  backgroundImage:
                      _photoPath != null ? FileImage(File(_photoPath!)) : null,
                  child: _photoPath == null
                      ? const Icon(Icons.person, size: 60)
                      : null,
                ),
              ),

              SizedBox(height: ds.cardPadding * 1.25),

              // Admission Number
              TextFormField(
                controller: _admCtrl,
                readOnly: !_admissionEditable,
                decoration: InputDecoration(
                  labelText: "Admission Number",
                  border: const OutlineInputBorder(),
                  suffixIcon: _admissionEditable ? const Icon(Icons.edit) : null,
                  filled: !_admissionEditable,
                  fillColor: !_admissionEditable ? const Color(0xFFF5F5F5) : null,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
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

              // FIXED: Changed 'value' to 'initialValue' (Line 198)
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                    labelText: "Gender", border: OutlineInputBorder()),
                initialValue: _gender,  // ✅ FIXED: was 'value'
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

              // Date of Admission
              TextFormField(
                controller: _dateOfAdmissionCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Date of Admission",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_month, color: Colors.blue),
                ),
                onTap: _pickAdmissionDate,
                validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
              ),

              const SizedBox(height: 20),

              // FIXED: Changed 'value' to 'initialValue' (Line 225)
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                    labelText: "Class", border: OutlineInputBorder()),
                initialValue: _classId,  // ✅ FIXED: was 'value'
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

              // FIXED: Changed 'value' to 'initialValue' (Line 245)
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                    labelText: "Arm", border: OutlineInputBorder()),
                initialValue: _armId,  // ✅ FIXED: was 'value'
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

              // NATIONALITY, STATE OF ORIGIN, LGA
              TextFormField(
                controller: _nationalityCtrl,
                decoration: const InputDecoration(
                    labelText: "Nationality", border: OutlineInputBorder()),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _stateOfOriginCtrl,
                decoration: const InputDecoration(
                    labelText: "State of Origin", border: OutlineInputBorder()),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _lgaCtrl,
                decoration: const InputDecoration(
                    labelText: "LGA (Local Govt. Area)", border: OutlineInputBorder()),
              ),

              const SizedBox(height: 20),

              // ======================================================
              // PARENT DATA SECTION
              // ======================================================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Parent/Guardian Information",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // SEARCH EXISTING PARENT
                    TextField(
                      controller: _parentSearchCtrl,
                      decoration: const InputDecoration(
                        labelText: "Search Existing Parent",
                        hintText: "Search by name or phone number",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: _searchParents,
                    ),

                    // SEARCH RESULTS DROPDOWN
                    if (_searchingParents)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),

                    if (_searchedParents.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _searchedParents.length > 5 ? 5 : _searchedParents.length,
                          itemBuilder: (context, index) {
                            final parent = _searchedParents[index];
                            return ListTile(
                              leading: const Icon(Icons.person, color: Colors.blue),
                              title: Text(
                                parent['parentName'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Phone: ${parent['phoneNumber'] ?? ''}\n'
                                'Address: ${parent['homeAddress'] ?? ''}',
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () => _selectParent(parent),
                            );
                          },
                        ),
                      ),

                    // SELECTED PARENT INDICATOR
                    if (_useExistingParent && _selectedParentId != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Using existing parent: ${_parentNameCtrl.text}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _clearParentSelection,
                              icon: const Icon(Icons.clear, size: 16),
                              label: const Text("Clear"),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    // PARENT FORM FIELDS
                    const Text(
                      "Parent Details",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _parentNameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Parent/Guardian Name",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _parentPhoneCtrl,
                      decoration: const InputDecoration(
                        labelText: "Phone Number (WhatsApp)",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _parentPhone2Ctrl,
                      decoration: const InputDecoration(
                        labelText: "Phone Number 2 (Optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _parentAddressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Home Address",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _parentOccupationCtrl,
                      decoration: const InputDecoration(
                        labelText: "Occupation (Optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _parentOfficeAddressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Office Address (Optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _parentEmailCtrl,
                      decoration: const InputDecoration(
                        labelText: "Email Address (Optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
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