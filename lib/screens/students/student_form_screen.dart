// lib/screens/students/student_form_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/database_helper_wrapper.dart';
import '../../db/database_helper.dart' show StudentLimitExceededException;
import '../../utils/backup_reminder_helper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/admission_settings_helper.dart';

class StudentFormScreen extends StatefulWidget {
  const StudentFormScreen({super.key});

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  // Controllers
  final _surnameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _otherNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _nationalityCtrl = TextEditingController();
  final _stateOfOriginCtrl = TextEditingController();
  final _lgaCtrl = TextEditingController();
  final _parentNameCtrl = TextEditingController();
  final _parentPhoneCtrl = TextEditingController();
  final _parentPhone2Ctrl = TextEditingController();
  final _parentEmailCtrl = TextEditingController();
  final _parentAddressCtrl = TextEditingController();
  final _parentOccupationCtrl = TextEditingController();
  final _parentOfficeAddressCtrl = TextEditingController();
  final _admCtrl = TextEditingController(); // Admission number
  final _parentSearchCtrl = TextEditingController();
  final _dateOfAdmissionCtrl = TextEditingController(); // Date of admission

  String? _selectedGender;
  int? _selectedClass;
  int? _selectedArm;
  int? _selectedParentId; // For linking to existing parent

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  List<Map<String, dynamic>> _searchedParents = [];

  // New intake bill preview
  List<Map<String, dynamic>> _billItems = [];
  bool _loadingBills = false;
  double _billTotal = 0;

  bool _loading = true;
  bool _useExistingParent = false;
  bool _searchingParents = false;
  bool _admissionEditable = false;

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
    _admissionEditable = await AdmissionSettingsHelper.isEditable();
    _setDefaultAdmissionDate();
    if (mounted) setState(() => _loading = false);
  }

  // Set default admission date to current date
  void _setDefaultAdmissionDate() {
    final now = DateTime.now();
    _dateOfAdmissionCtrl.text =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Future<void> _loadClasses() async {
    _classes = await _db.getClasses();
  }

  Future<void> _loadArms(int classId) async {
    // FIXED: Use getArmsByClass instead of getArms
    _arms = await _db.getArmsByClass(classId);
    _selectedArm = null;
    _billItems = [];
    _billTotal = 0;
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------
  // LOAD NEW INTAKE BILLS FOR SELECTED CLASS/ARM
  // ----------------------------------------------------------
  Future<void> _loadNewIntakeBills() async {
    if (_selectedClass == null || _selectedArm == null) return;

    setState(() => _loadingBills = true);

    try {
      final activeTerm = await _db.getActiveTerm();
      final activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";

      if (activeTerm.isEmpty || activeSession.isEmpty) {
        setState(() {
          _billItems = [];
          _billTotal = 0;
          _loadingBills = false;
        });
        return;
      }

      final result = await _db.getNewIntakeBillForClass(
        _selectedClass!,
        activeTerm,
        activeSession,
        armId: _selectedArm,
      );

      final List<Map<String, dynamic>> items = [];

      // Add regular fees
      for (final fee in (result['regularFees'] as List)) {
        items.add({
          'name': fee['feeItemName'] ?? 'Fee',
          'amount': (fee['amount'] as num).toDouble(),
          'feeItemId': fee['feeItemId'],
          'type': 'regular',
        });
      }

      // Add special fees
      for (final fee in (result['specialFees'] as List)) {
        items.add({
          'name': fee['feeItemName'] ?? 'Special Fee',
          'amount': (fee['amount'] as num).toDouble(),
          'specialFeeItemId': fee['specialFeeItemId'],
          'type': 'special',
        });
      }

      final total = items.fold<double>(
        0.0, (sum, item) => sum + (item['amount'] as double),
      );

      if (mounted) {
        setState(() {
          _billItems = items;
          _billTotal = total;
          _loadingBills = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading new intake bills: $e');
      if (mounted) setState(() => _loadingBills = false);
    }
  }

  void _recalculateBillTotal() {
    _billTotal = _billItems.fold<double>(
      0.0, (sum, item) => sum + ((item['amount'] as num).toDouble()),
    );
  }

  void _removeBillItem(int index) {
    setState(() {
      _billItems.removeAt(index);
      _recalculateBillTotal();
    });
  }

  void _showAddFeeDialog() {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Fee Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Fee Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
                prefixText: '₦',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (name.isEmpty || amount <= 0) return;

              setState(() {
                _billItems.add({
                  'name': name,
                  'amount': amount,
                  'type': 'custom',
                });
                _recalculateBillTotal();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
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

  // Date picker for admission date
  Future<void> _pickAdmissionDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
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
      _parentNameCtrl.clear();
      _parentPhoneCtrl.clear();
      _parentPhone2Ctrl.clear();
      _parentEmailCtrl.clear();
      _parentAddressCtrl.clear();
      _parentOccupationCtrl.clear();
      _parentOfficeAddressCtrl.clear();
    });
  }

  // ----------------------------------------------------------
  // SAVE STUDENT
  // ----------------------------------------------------------
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_admCtrl.text.trim().isEmpty) {
      _admCtrl.text = await _db.generateAdmissionNumber();
    } else if (_admissionEditable) {
      final allStudents = await _db.getStudents(includeInactive: true);
      final duplicate = allStudents.any((s) =>
          (s['admissionNo'] as String?)?.trim().toUpperCase() ==
          _admCtrl.text.trim().toUpperCase());
      if (duplicate) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Admission number "${_admCtrl.text.trim()}" is already in use'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Create or update parent record if parent data exists
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
          // Check if parent already exists by phone + name
          final existingParents = await _db.searchParents(_parentPhoneCtrl.text.trim());
          final matchingParent = existingParents.where((p) =>
            p['phoneNumber'] == _parentPhoneCtrl.text.trim() &&
            p['parentName'] == _parentNameCtrl.text.trim()
          ).firstOrNull;

          if (matchingParent != null) {
            // Update existing parent instead of creating duplicate
            await _db.updateParent(matchingParent['id'], parentData);
          } else {
            // Create new parent record
            await _db.insertParent(parentData);
          }
        }
      } catch (e) {
        debugPrint('Failed to create/update parent record: $e');
      }
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
      'nationality': _nationalityCtrl.text.trim().isEmpty ? null : _nationalityCtrl.text.trim(),
      'stateOfOrigin': _stateOfOriginCtrl.text.trim().isEmpty ? null : _stateOfOriginCtrl.text.trim(),
      'lga': _lgaCtrl.text.trim().isEmpty ? null : _lgaCtrl.text.trim(),
      'parentName': _parentNameCtrl.text.trim(),
      'parentPhone': _parentPhoneCtrl.text.trim(),
      'parentEmail': _parentEmailCtrl.text.trim(),
      'parentAddress': _parentAddressCtrl.text.trim(),
      'photoPath': null,
      'dateOfAdmission': _dateOfAdmissionCtrl.text.trim(),
    };

    int studentId;
    try {
      studentId = await _db.insertStudent(data);
    } catch (e) {
      if (!mounted) return;
      final message = e is StudentLimitExceededException
          ? e.message
          : e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Track activity for backup reminder
    await BackupReminderHelper.incrementTransactionCount();

    // GENERATE BILL FROM PREVIEW (new intake bills) OR AUTO-GENERATE
    if (_billItems.isNotEmpty) {
      try {
        await _generateBillFromPreview(studentId);
      } catch (e) {
        debugPrint('Failed to generate bill from preview: $e');
      }
    } else if (_selectedClass != null) {
      try {
        await _autoGenerateBillForStudent(studentId, _selectedClass!);
      } catch (e) {
        debugPrint('Failed to auto-generate bill for new student: $e');
      }
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  // ----------------------------------------------------------
  // AUTO-GENERATE BILL FOR NEW STUDENT
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
      debugPrint('No fees assigned to this class - skipping auto-bill generation');
      return;
    }

    // Calculate previous balance (should be 0 for new students)
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

    // Insert bill
    await _db.insertStudentBill(bill, breakdown);

    debugPrint('Auto-generated bill for student $studentId (Class $classId)');
  }

  // ----------------------------------------------------------
  // GENERATE BILL FROM PREVIEW (New Intake Bills)
  // ----------------------------------------------------------
  Future<void> _generateBillFromPreview(int studentId) async {
    if (_billItems.isEmpty) return;

    final activeTerm = await _db.getActiveTerm();
    final activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";

    if (activeTerm.isEmpty || activeSession.isEmpty) {
      debugPrint('No active term/session - skipping bill generation from preview');
      return;
    }

    // Calculate previous balance (should be 0 for new students)
    final previousBalance = await _db.computeOutstandingBeforeTerm(
      studentId,
      term: activeTerm,
      session: activeSession,
    );

    final subtotal = _billTotal;
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

    // Create breakdown data from preview items
    // Use 0 as feeItemId for custom items (they don't have a feeItemId or specialFeeItemId)
    final breakdown = _billItems.map((item) {
      return {
        'feeItemId': item['feeItemId'] ?? item['specialFeeItemId'] ?? 0,
        'amount': item['amount'],
        'label': item['name'] ?? '',
      };
    }).toList();

    // Insert bill
    await _db.insertStudentBill(bill, breakdown);

    debugPrint('Generated bill from preview for student $studentId (${_billItems.length} items, total: $grandTotal)');
  }

  @override
  void dispose() {
    _surnameCtrl.dispose();
    _firstNameCtrl.dispose();
    _otherNameCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    _nationalityCtrl.dispose();
    _stateOfOriginCtrl.dispose();
    _lgaCtrl.dispose();
    _parentNameCtrl.dispose();
    _parentPhoneCtrl.dispose();
    _parentPhone2Ctrl.dispose();
    _parentEmailCtrl.dispose();
    _parentAddressCtrl.dispose();
    _parentOccupationCtrl.dispose();
    _parentOfficeAddressCtrl.dispose();
    _parentSearchCtrl.dispose();
    _admCtrl.dispose();
    _dateOfAdmissionCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // UI
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("New Student Registration")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ADMISSION NUMBER
              TextFormField(
                controller: _admCtrl,
                readOnly: !_admissionEditable,
                decoration: InputDecoration(
                  labelText: "Admission Number",
                  border: const OutlineInputBorder(),
                  suffixIcon: _admissionEditable ? const Icon(Icons.edit) : null,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
              ),

              SizedBox(height: ds.cardPadding * 1.5),

              // ======================================================
              // STUDENT BIO DATA SECTION
              // ======================================================
              Container(
                padding: EdgeInsets.all(ds.cardPadding * 0.75),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.indigo.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Student Bio Data",
                          style: TextStyle(
                            fontSize: ds.titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ds.cardPadding),

                    // NAMES
                    _input(_surnameCtrl, "Surname", required: true),
                    SizedBox(height: ds.cardPadding * 0.75),
                    _input(_firstNameCtrl, "First Name", required: true),
                    SizedBox(height: ds.cardPadding * 0.75),
                    _input(_otherNameCtrl, "Other Name"),

                    SizedBox(height: ds.cardPadding),

                    // GENDER
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: "Gender",
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: const [
                        DropdownMenuItem(value: "Male", child: Text("Male")),
                        DropdownMenuItem(value: "Female", child: Text("Female")),
                      ],
                      onChanged: (v) => setState(() => _selectedGender = v),
                      validator: (v) => v == null ? "Required" : null,
                    ),

                    SizedBox(height: ds.cardPadding),

                    // DATE OF BIRTH
                    TextFormField(
                      controller: _dobCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: "Date of Birth",
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onTap: _pickDate,
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),

                    SizedBox(height: ds.cardPadding),

                    // HOME ADDRESS
                    _input(_addressCtrl, "Home Address",
                        required: true, maxLines: 2),

                    SizedBox(height: ds.cardPadding),

                    // NATIONALITY, STATE OF ORIGIN, LGA (Optional)
                    _input(_nationalityCtrl, "Nationality (Optional)"),
                    SizedBox(height: ds.cardPadding * 0.75),
                    _input(_stateOfOriginCtrl, "State of Origin (Optional)"),
                    SizedBox(height: ds.cardPadding * 0.75),
                    _input(_lgaCtrl, "Local Government Area - LGA (Optional)"),
                  ],
                ),
              ),

              SizedBox(height: ds.cardPadding * 1.5),

              // ======================================================
              // PARENT DATA SECTION
              // ======================================================
              Container(
                padding: EdgeInsets.all(ds.cardPadding * 0.75),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Parent/Guardian Information",
                      style: TextStyle(
                        fontSize: ds.titleFontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: ds.cardPadding * 0.75),

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
                      Padding(
                        padding: EdgeInsets.all(ds.cardPadding * 0.5),
                        child: const Center(child: CircularProgressIndicator()),
                      ),

                    if (_searchedParents.isNotEmpty)
                      Container(
                        margin: EdgeInsets.only(top: ds.cardPadding * 0.5),
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
                        margin: EdgeInsets.only(top: ds.cardPadding * 0.75),
                        padding: EdgeInsets.all(ds.cardPadding * 0.75),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: ds.cardPadding * 0.5),
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

                    SizedBox(height: ds.cardPadding),
                    const Divider(),
                    SizedBox(height: ds.cardPadding),

                    // PARENT FORM FIELDS
                    Text(
                      "Parent Details",
                      style: TextStyle(
                        fontSize: ds.bodyFontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: ds.cardPadding * 0.75),

                    _input(_parentNameCtrl, "Parent/Guardian Name", required: true),
                    SizedBox(height: ds.cardPadding * 0.75),

                    _input(_parentPhoneCtrl, "Phone Number (WhatsApp)", required: true),
                    SizedBox(height: ds.cardPadding * 0.75),

                    _input(_parentPhone2Ctrl, "Phone Number 2 (Optional)"),
                    SizedBox(height: ds.cardPadding * 0.75),

                    _input(_parentAddressCtrl, "Home Address", required: true, maxLines: 2),
                    SizedBox(height: ds.cardPadding * 0.75),

                    _input(_parentOccupationCtrl, "Occupation (Optional)"),
                    SizedBox(height: ds.cardPadding * 0.75),

                    _input(_parentOfficeAddressCtrl, "Office Address (Optional)", maxLines: 2),
                    SizedBox(height: ds.cardPadding * 0.75),

                    _input(_parentEmailCtrl, "Email Address (Optional)"),
                  ],
                ),
              ),

              SizedBox(height: ds.cardPadding * 1.5),

              // ======================================================
              // CLASS & ADMISSION DETAILS SECTION
              // ======================================================
              Container(
                padding: EdgeInsets.all(ds.cardPadding * 0.75),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.school, color: Colors.teal.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Class & Admission Details",
                          style: TextStyle(
                            fontSize: ds.titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ds.cardPadding),

                    // DATE OF ADMISSION
                    TextFormField(
                      controller: _dateOfAdmissionCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: "Date of Admission",
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onTap: _pickAdmissionDate,
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),

                    SizedBox(height: ds.cardPadding),

                    // CLASS
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: "Class",
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
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
                          _billItems = [];
                          _billTotal = 0;
                        });
                        if (v != null) _loadArms(v);
                      },
                      validator: (v) => v == null ? "Required" : null,
                    ),

                    SizedBox(height: ds.cardPadding),

                    // ARM
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: "Arm",
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _arms
                          .map(
                            (a) => DropdownMenuItem<int>(
                              value: a['id'] as int,
                              child: Text(a['name']),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() => _selectedArm = v);
                        if (v != null) _loadNewIntakeBills();
                      },
                      validator: (v) => v == null ? "Required" : null,
                    ),

                    // NEW INTAKE BILLS PREVIEW
                    if (_loadingBills)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: ds.cardPadding),
                        child: const Center(child: CircularProgressIndicator()),
                      ),

                    if (!_loadingBills && _billItems.isNotEmpty) ...[
                      SizedBox(height: ds.cardPadding),
                      _buildBillPreview(ds),
                    ],
                  ],
                ),
              ),

              SizedBox(height: ds.cardPadding * 1.875),

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
  // BILL PREVIEW WIDGET
  // ----------------------------------------------------------
  Widget _buildBillPreview(DisplaySettings ds) {
    final formatter = NumberFormat('#,##0.00');

    return Container(
      padding: EdgeInsets.all(ds.cardPadding * 0.75),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'New Intake Bills',
                  style: TextStyle(
                    fontSize: ds.titleFontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _showAddFeeDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Fee'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const Divider(),

          // Fee items list
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _billItems.length,
            itemBuilder: (context, index) {
              final item = _billItems[index];
              final type = item['type'] as String;
              final Color tagColor;
              final String tagLabel;

              switch (type) {
                case 'special':
                  tagColor = Colors.orange;
                  tagLabel = 'Special';
                  break;
                case 'custom':
                  tagColor = Colors.purple;
                  tagLabel = 'Custom';
                  break;
                default:
                  tagColor = Colors.blue;
                  tagLabel = 'Regular';
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    // Tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: tagColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tagLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: tagColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Fee name
                    Expanded(
                      child: Text(
                        item['name'] as String,
                        style: TextStyle(fontSize: ds.bodyFontSize),
                      ),
                    ),
                    // Amount
                    Text(
                      '₦${formatter.format(item['amount'])}',
                      style: TextStyle(
                        fontSize: ds.bodyFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // Delete button
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: Colors.red.shade400),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _removeBillItem(index),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              );
            },
          ),

          // Total row
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: ds.titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade900,
                ),
              ),
              Text(
                '₦${formatter.format(_billTotal)}',
                style: TextStyle(
                  fontSize: ds.titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade900,
                ),
              ),
            ],
          ),
        ],
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