// lib/screens/staff/staff_view/staff_edit_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';

class StaffEditScreen extends StatefulWidget {
  final Staff staff;

  const StaffEditScreen({super.key, required this.staff});

  @override
  State<StaffEditScreen> createState() => _StaffEditScreenState();
}

class _StaffEditScreenState extends State<StaffEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dbHelper = DatabaseHelper();
  bool _isLoading = false;

  // Controllers for basic info
  late TextEditingController _surnameController;
  late TextEditingController _firstNameController;
  late TextEditingController _otherNameController;
  late TextEditingController _phoneController;
  late TextEditingController _phone2Controller;
  late TextEditingController _emailController;
  late TextEditingController _addressController;
  late TextEditingController _stateController;
  late TextEditingController _lgaController;
  late TextEditingController _nationalityController;

  // Next of Kin controllers
  late TextEditingController _nextOfKinNameController;
  late TextEditingController _nextOfKinPhoneController;
  late TextEditingController _nextOfKinRelationshipController;
  late TextEditingController _nextOfKinAddressController;

  // Referee 1 controllers
  late TextEditingController _referee1NameController;
  late TextEditingController _referee1PhoneController;
  late TextEditingController _referee1RelationshipController;
  late TextEditingController _referee1AddressController;

  // Referee 2 controllers
  late TextEditingController _referee2NameController;
  late TextEditingController _referee2PhoneController;
  late TextEditingController _referee2RelationshipController;
  late TextEditingController _referee2AddressController;

  // Bank details controllers
  late TextEditingController _bankNameController;
  late TextEditingController _accountNameController;
  late TextEditingController _accountNumberController;
  late TextEditingController _salaryController;

  late String _staffType;
  String? _title;
  late String _gender;
  late String _maritalStatus;
  String? _religion;
  DateTime? _dateOfBirth;
  DateTime? _dateOfEmployment;
  String? _photoPath;

  // Dynamic lists
  late List<AcademicRecord> _academicRecords;
  late List<JobExperience> _jobExperiences;
  late List<String> _skills;
  late List<String> _hobbies;

  @override
  void initState() {
    super.initState();
    final s = widget.staff;

    _surnameController = TextEditingController(text: s.surname);
    _firstNameController = TextEditingController(text: s.firstName);
    _otherNameController = TextEditingController(text: s.otherName ?? '');
    _phoneController = TextEditingController(text: s.phone ?? '');
    _phone2Controller = TextEditingController(text: s.phone2 ?? '');
    _emailController = TextEditingController(text: s.email ?? '');
    _addressController = TextEditingController(text: s.address ?? '');
    _stateController = TextEditingController(text: s.stateOfOrigin ?? '');
    _lgaController = TextEditingController(text: s.lga ?? '');
    _nationalityController = TextEditingController(text: s.nationality ?? '');

    _nextOfKinNameController = TextEditingController(text: s.nextOfKinName ?? '');
    _nextOfKinPhoneController = TextEditingController(text: s.nextOfKinPhone ?? '');
    _nextOfKinRelationshipController = TextEditingController(text: s.nextOfKinRelationship ?? '');
    _nextOfKinAddressController = TextEditingController(text: s.nextOfKinAddress ?? '');

    _referee1NameController = TextEditingController(text: s.referee1Name ?? '');
    _referee1PhoneController = TextEditingController(text: s.referee1Phone ?? '');
    _referee1RelationshipController = TextEditingController(text: s.referee1Relationship ?? '');
    _referee1AddressController = TextEditingController(text: s.referee1Address ?? '');

    _referee2NameController = TextEditingController(text: s.referee2Name ?? '');
    _referee2PhoneController = TextEditingController(text: s.referee2Phone ?? '');
    _referee2RelationshipController = TextEditingController(text: s.referee2Relationship ?? '');
    _referee2AddressController = TextEditingController(text: s.referee2Address ?? '');

    _bankNameController = TextEditingController(text: s.bankName ?? '');
    _accountNameController = TextEditingController(text: s.accountName ?? '');
    _accountNumberController = TextEditingController(text: s.accountNumber ?? '');
    _salaryController = TextEditingController(text: s.salary > 0 ? s.salary.toString() : '');

    _staffType = s.staffType;
    _title = s.title;
    _gender = s.gender;
    _maritalStatus = s.maritalStatus ?? 'Single';
    _religion = s.religion;
    _dateOfBirth = s.dateOfBirth != null ? DateTime.tryParse(s.dateOfBirth!) : null;
    _dateOfEmployment = s.dateOfEmployment != null ? DateTime.tryParse(s.dateOfEmployment!) : null;
    _photoPath = s.photoPath;

    _academicRecords = s.academicInfo != null ? List.from(s.academicInfo!) : [];
    _jobExperiences = s.jobExperience != null ? List.from(s.jobExperience!) : [];
    _skills = s.skills != null ? List.from(s.skills!) : [];
    _hobbies = s.hobbies != null ? List.from(s.hobbies!) : [];
  }

  @override
  void dispose() {
    _surnameController.dispose();
    _firstNameController.dispose();
    _otherNameController.dispose();
    _phoneController.dispose();
    _phone2Controller.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _stateController.dispose();
    _lgaController.dispose();
    _nationalityController.dispose();
    _nextOfKinNameController.dispose();
    _nextOfKinPhoneController.dispose();
    _nextOfKinRelationshipController.dispose();
    _nextOfKinAddressController.dispose();
    _referee1NameController.dispose();
    _referee1PhoneController.dispose();
    _referee1RelationshipController.dispose();
    _referee1AddressController.dispose();
    _referee2NameController.dispose();
    _referee2PhoneController.dispose();
    _referee2RelationshipController.dispose();
    _referee2AddressController.dispose();
    _bankNameController.dispose();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();

    // Note: Camera option removed for this complex form to prevent app restart
    // on low-memory devices. Gallery selection is more stable.
    // To add photo via camera, take the photo first, then select from gallery.

    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
        requestFullMetadata: false,
      );

      if (image != null && mounted) {
        final appDir = await getApplicationDocumentsDirectory();
        final staffPhotosDir = Directory('${appDir.path}/staff_photos');
        if (!await staffPhotosDir.exists()) {
          await staffPhotosDir.create(recursive: true);
        }

        // Replace "/" with "_" in staff ID to avoid path issues
        final safeStaffId = widget.staff.staffId.replaceAll('/', '_');
        final fileName = '${safeStaffId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedPath = '${staffPhotosDir.path}/$fileName';

        // Copy the file
        final imageFile = File(image.path);
        if (await imageFile.exists()) {
          await imageFile.copy(savedPath);

          if (mounted) {
            setState(() {
              _photoPath = savedPath;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDate(bool isEmploymentDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isEmploymentDate
          ? (_dateOfEmployment ?? DateTime.now())
          : (_dateOfBirth ?? DateTime(1990)),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isEmploymentDate) {
          _dateOfEmployment = picked;
        } else {
          _dateOfBirth = picked;
        }
      });
    }
  }

  void _addAcademicRecord() {
    final schoolController = TextEditingController();
    final certController = TextEditingController();
    final yearController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Academic Record'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: schoolController,
                decoration: const InputDecoration(
                  labelText: 'School Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: certController,
                decoration: const InputDecoration(
                  labelText: 'Certificate Obtained',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: yearController,
                decoration: const InputDecoration(
                  labelText: 'Year Obtained',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (schoolController.text.isNotEmpty &&
                  certController.text.isNotEmpty &&
                  yearController.text.isNotEmpty) {
                setState(() {
                  _academicRecords.add(AcademicRecord(
                    schoolName: schoolController.text,
                    certificate: certController.text,
                    yearObtained: yearController.text,
                  ));
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addJobExperience() {
    final orgController = TextEditingController();
    final posController = TextEditingController();
    final startController = TextEditingController();
    final endController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Job Experience'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: orgController,
                decoration: const InputDecoration(
                  labelText: 'Organization',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: posController,
                decoration: const InputDecoration(
                  labelText: 'Position',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: startController,
                decoration: const InputDecoration(
                  labelText: 'Start Date (e.g., Jan 2020)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endController,
                decoration: const InputDecoration(
                  labelText: 'End Date (e.g., Dec 2022)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (orgController.text.isNotEmpty && posController.text.isNotEmpty) {
                setState(() {
                  _jobExperiences.add(JobExperience(
                    organization: orgController.text,
                    position: posController.text,
                    startDate: startController.text,
                    endDate: endController.text,
                  ));
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addSkill() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Skill'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Skill',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  _skills.add(controller.text);
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addHobby() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Hobby'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Hobby',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  _hobbies.add(controller.text);
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveStaff() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final staff = Staff(
        id: widget.staff.id,
        staffId: widget.staff.staffId,
        staffType: _staffType,
        title: _title,
        surname: _surnameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        otherName: _otherNameController.text.trim().isEmpty
            ? null
            : _otherNameController.text.trim(),
        gender: _gender,
        dateOfBirth: _dateOfBirth?.toIso8601String(),
        maritalStatus: _maritalStatus,
        stateOfOrigin: _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        lga: _lgaController.text.trim().isEmpty ? null : _lgaController.text.trim(),
        nationality: _nationalityController.text.trim().isEmpty
            ? null
            : _nationalityController.text.trim(),
        religion: _religion,
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        phone2: _phone2Controller.text.trim().isEmpty
            ? null
            : _phone2Controller.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        academicInfo: _academicRecords.isEmpty ? null : _academicRecords,
        jobExperience: _jobExperiences.isEmpty ? null : _jobExperiences,
        skills: _skills.isEmpty ? null : _skills,
        hobbies: _hobbies.isEmpty ? null : _hobbies,
        referee1Name: _referee1NameController.text.trim().isEmpty
            ? null
            : _referee1NameController.text.trim(),
        referee1Phone: _referee1PhoneController.text.trim().isEmpty
            ? null
            : _referee1PhoneController.text.trim(),
        referee1Relationship: _referee1RelationshipController.text.trim().isEmpty
            ? null
            : _referee1RelationshipController.text.trim(),
        referee1Address: _referee1AddressController.text.trim().isEmpty
            ? null
            : _referee1AddressController.text.trim(),
        referee2Name: _referee2NameController.text.trim().isEmpty
            ? null
            : _referee2NameController.text.trim(),
        referee2Phone: _referee2PhoneController.text.trim().isEmpty
            ? null
            : _referee2PhoneController.text.trim(),
        referee2Relationship: _referee2RelationshipController.text.trim().isEmpty
            ? null
            : _referee2RelationshipController.text.trim(),
        referee2Address: _referee2AddressController.text.trim().isEmpty
            ? null
            : _referee2AddressController.text.trim(),
        nextOfKinName: _nextOfKinNameController.text.trim().isEmpty
            ? null
            : _nextOfKinNameController.text.trim(),
        nextOfKinPhone: _nextOfKinPhoneController.text.trim().isEmpty
            ? null
            : _nextOfKinPhoneController.text.trim(),
        nextOfKinRelationship: _nextOfKinRelationshipController.text.trim().isEmpty
            ? null
            : _nextOfKinRelationshipController.text.trim(),
        nextOfKinAddress: _nextOfKinAddressController.text.trim().isEmpty
            ? null
            : _nextOfKinAddressController.text.trim(),
        dateOfEmployment: _dateOfEmployment?.toIso8601String(),
        salary: double.tryParse(_salaryController.text.trim()) ?? widget.staff.salary,
        bankName: _bankNameController.text.trim().isEmpty
            ? null
            : _bankNameController.text.trim(),
        accountName: _accountNameController.text.trim().isEmpty
            ? null
            : _accountNameController.text.trim(),
        accountNumber: _accountNumberController.text.trim().isEmpty
            ? null
            : _accountNumberController.text.trim(),
        photoPath: _photoPath,
        isActive: widget.staff.isActive,
      );

      await _dbHelper.updateStaff(widget.staff.id!, staff.toMap());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Staff ${staff.fullName} updated successfully!'),
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
        title: const Text('Edit Staff'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Staff ID Card (read-only)
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.badge, color: Colors.blue),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Staff ID',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                                Text(
                                  widget.staff.staffId,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Photo Section
                    _buildSectionHeader('Photo'),
                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[400]!),
                          ),
                          child: _photoPath != null && File(_photoPath!).existsSync()
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(_photoPath!),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey[500]),
                                    const SizedBox(height: 8),
                                    Text('Tap to select photo', style: TextStyle(color: Colors.grey[600])),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Staff Type
                    _buildSectionHeader('Staff Type'),
                    DropdownButtonFormField<String>(
                      initialValue: _staffType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.work),
                      ),
                      items: ['Teaching Staff', 'Non-Teaching Staff']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => _staffType = v!),
                    ),
                    const SizedBox(height: 24),

                    // Bio Data Section
                    _buildSectionHeader('Bio Data'),
                    DropdownButtonFormField<String>(
                      initialValue: _title,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                      items: ['Mr.', 'Mrs.', 'Miss', 'Ms.', 'Madam', 'Sir', 'Dr.', 'Prof.', 'Rev.', 'Pst.', 'Alhaji', 'Alhaja', 'Chief', 'Engr.']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => _title = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _surnameController,
                      decoration: const InputDecoration(
                        labelText: 'Surname *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (v) => v?.isEmpty == true ? 'Surname is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (v) => v?.isEmpty == true ? 'First name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _otherNameController,
                      decoration: const InputDecoration(
                        labelText: 'Other Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _gender,
                            decoration: const InputDecoration(
                              labelText: 'Gender *',
                              border: OutlineInputBorder(),
                            ),
                            items: ['Male', 'Female']
                                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (v) => setState(() => _gender = v!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _maritalStatus,
                            decoration: const InputDecoration(
                              labelText: 'Marital Status',
                              border: OutlineInputBorder(),
                            ),
                            items: ['Single', 'Married', 'Divorced', 'Widowed']
                                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (v) => setState(() => _maritalStatus = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => _selectDate(false),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date of Birth',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _dateOfBirth != null
                              ? DateFormat('dd MMM yyyy').format(_dateOfBirth!)
                              : 'Select date',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _stateController,
                            decoration: const InputDecoration(
                              labelText: 'State of Origin',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lgaController,
                            decoration: const InputDecoration(
                              labelText: 'LGA',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nationalityController,
                            decoration: const InputDecoration(
                              labelText: 'Nationality',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _religion,
                            decoration: const InputDecoration(
                              labelText: 'Religion',
                              border: OutlineInputBorder(),
                            ),
                            items: ['Christianity', 'Islamic', 'Hindi', 'Traditional', 'Others']
                                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (v) => setState(() => _religion = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Contact Section
                    _buildSectionHeader('Contact'),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone2Controller,
                      decoration: const InputDecoration(
                        labelText: 'Alternative Phone',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),

                    // Next of Kin Section
                    _buildSectionHeader('Next of Kin Information'),
                    TextFormField(
                      controller: _nextOfKinNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nextOfKinPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _nextOfKinRelationshipController,
                            decoration: const InputDecoration(
                              labelText: 'Relationship',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nextOfKinAddressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Academic Information Section
                    _buildSectionHeader('Academic Information'),
                    _buildListSection(
                      items: _academicRecords
                          .map((e) => '${e.certificate} - ${e.schoolName} (${e.yearObtained})')
                          .toList(),
                      onAdd: _addAcademicRecord,
                      onRemove: (i) => setState(() => _academicRecords.removeAt(i)),
                      addLabel: 'Add Academic Record',
                    ),
                    const SizedBox(height: 24),

                    // Job Experience Section
                    _buildSectionHeader('Job Experience'),
                    _buildListSection(
                      items: _jobExperiences
                          .map((e) => '${e.position} at ${e.organization} (${e.startDate} - ${e.endDate})')
                          .toList(),
                      onAdd: _addJobExperience,
                      onRemove: (i) => setState(() => _jobExperiences.removeAt(i)),
                      addLabel: 'Add Job Experience',
                    ),
                    const SizedBox(height: 24),

                    // Skills Section
                    _buildSectionHeader('Skills'),
                    _buildListSection(
                      items: _skills,
                      onAdd: _addSkill,
                      onRemove: (i) => setState(() => _skills.removeAt(i)),
                      addLabel: 'Add Skill',
                    ),
                    const SizedBox(height: 24),

                    // Hobbies Section
                    _buildSectionHeader('Hobbies'),
                    _buildListSection(
                      items: _hobbies,
                      onAdd: _addHobby,
                      onRemove: (i) => setState(() => _hobbies.removeAt(i)),
                      addLabel: 'Add Hobby',
                    ),
                    const SizedBox(height: 24),

                    // Referee 1 Section
                    _buildSectionHeader('Referee/Guarantor 1'),
                    TextFormField(
                      controller: _referee1NameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _referee1PhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _referee1RelationshipController,
                            decoration: const InputDecoration(
                              labelText: 'Relationship',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _referee1AddressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Referee 2 Section
                    _buildSectionHeader('Referee/Guarantor 2'),
                    TextFormField(
                      controller: _referee2NameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _referee2PhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _referee2RelationshipController,
                            decoration: const InputDecoration(
                              labelText: 'Relationship',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _referee2AddressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Date of Employment
                    _buildSectionHeader('Employment'),
                    InkWell(
                      onTap: () => _selectDate(true),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date of Employment',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _dateOfEmployment != null
                              ? DateFormat('dd MMM yyyy').format(_dateOfEmployment!)
                              : 'Select date',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _salaryController,
                      decoration: const InputDecoration(
                        labelText: 'Monthly Salary',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.payments),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 24),

                    // Salary Account Details Section
                    _buildSectionHeader('Salary Account Details'),
                    TextFormField(
                      controller: _bankNameController,
                      decoration: const InputDecoration(
                        labelText: 'Name of Bank',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _accountNameController,
                      decoration: const InputDecoration(
                        labelText: 'Account Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _accountNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Account Number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.numbers),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _saveStaff,
                        icon: const Icon(Icons.save),
                        label: const Text('Update Staff'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListSection({
    required List<String> items,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
    required String addLabel,
  }) {
    return Column(
      children: [
        if (items.isNotEmpty) ...[
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) => ListTile(
                title: Text(items[i]),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => onRemove(i),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(addLabel),
        ),
      ],
    );
  }
}
