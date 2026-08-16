// lib/screens/staff/staff_view/staff_details_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import '../../../utils/permission_helper.dart';
import 'staff_edit_screen.dart';

class StaffDetailsScreen extends StatefulWidget {
  final int staffId;
  final Map<String, dynamic> currentUser;

  const StaffDetailsScreen({
    super.key,
    required this.staffId,
    required this.currentUser,
  });

  @override
  State<StaffDetailsScreen> createState() => _StaffDetailsScreenState();
}

class _StaffDetailsScreenState extends State<StaffDetailsScreen> {
  final _dbHelper = DatabaseHelper();
  Staff? _staff;
  bool _isLoading = true;
  List<Map<String, dynamic>> _classAllocations = [];
  List<Map<String, dynamic>> _officeAllocations = [];

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final staffData = await _dbHelper.getStaffById(widget.staffId);
      if (staffData != null) {
        final classAlloc = await _dbHelper.getStaffClassAllocations(widget.staffId);
        final officeAlloc = await _dbHelper.getStaffOfficeAllocations(widget.staffId);
        setState(() {
          _staff = Staff.fromMap(staffData);
          _classAllocations = classAlloc;
          _officeAllocations = officeAlloc;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Staff not found'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_staff?.fullName ?? 'Staff Details'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          FutureBuilder<bool>(
            future: PermissionHelper.hasPermission(widget.currentUser, 'staff_edit'),
            builder: (context, snapshot) {
              if (snapshot.data == true && _staff != null) {
                return IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StaffEditScreen(staff: _staff!),
                      ),
                    );
                    if (result == true) _loadStaff();
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _staff == null
              ? const Center(child: Text('Staff not found'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Card with Photo
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: _staff!.photoPath != null &&
                                        File(_staff!.photoPath!).existsSync()
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.file(
                                          File(_staff!.photoPath!),
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          _staff!.fullName[0].toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 40,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _staff!.fullName,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _staff!.staffId,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _staff!.isTeachingStaff
                                            ? Colors.green.withValues(alpha: 0.2)
                                            : Colors.orange.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _staff!.staffType,
                                        style: TextStyle(
                                          color: _staff!.isTeachingStaff
                                              ? Colors.green[700]
                                              : Colors.orange[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Bio Data Section
                      _buildSection(
                        'Bio Data',
                        Icons.person,
                        [
                          _buildInfoRow('Gender', _staff!.gender),
                          _buildInfoRow('Date of Birth', _formatDate(_staff!.dateOfBirth)),
                          _buildInfoRow('Marital Status', _staff!.maritalStatus ?? 'N/A'),
                          _buildInfoRow('State of Origin', _staff!.stateOfOrigin ?? 'N/A'),
                          _buildInfoRow('LGA', _staff!.lga ?? 'N/A'),
                          _buildInfoRow('Nationality', _staff!.nationality ?? 'N/A'),
                          _buildInfoRow('Religion', _staff!.religion ?? 'N/A'),
                        ],
                      ),

                      // Contact Section
                      _buildSection(
                        'Contact',
                        Icons.phone,
                        [
                          _buildInfoRow('Phone', _staff!.phone ?? 'N/A'),
                          _buildInfoRow('Phone 2', _staff!.phone2 ?? 'N/A'),
                          _buildInfoRow('Email', _staff!.email ?? 'N/A'),
                          _buildInfoRow('Address', _staff!.address ?? 'N/A'),
                        ],
                      ),

                      // Next of Kin Section
                      if (_staff!.nextOfKinName != null &&
                          _staff!.nextOfKinName!.isNotEmpty)
                        _buildSection(
                          'Next of Kin',
                          Icons.family_restroom,
                          [
                            _buildInfoRow('Name', _staff!.nextOfKinName!),
                            _buildInfoRow('Phone', _staff!.nextOfKinPhone ?? 'N/A'),
                            _buildInfoRow('Relationship', _staff!.nextOfKinRelationship ?? 'N/A'),
                            _buildInfoRow('Address', _staff!.nextOfKinAddress ?? 'N/A'),
                          ],
                        ),

                      // Academic Information
                      if (_staff!.academicInfo != null &&
                          _staff!.academicInfo!.isNotEmpty)
                        _buildSection(
                          'Academic Information',
                          Icons.school,
                          _staff!.academicInfo!
                              .map((a) => _buildInfoRow(
                                    a.certificate,
                                    '${a.schoolName} (${a.yearObtained})',
                                  ))
                              .toList(),
                        ),

                      // Job Experience
                      if (_staff!.jobExperience != null &&
                          _staff!.jobExperience!.isNotEmpty)
                        _buildSection(
                          'Job Experience',
                          Icons.work,
                          _staff!.jobExperience!
                              .map((j) => _buildInfoRow(
                                    j.position,
                                    '${j.organization} (${j.startDate} - ${j.endDate})',
                                  ))
                              .toList(),
                        ),

                      // Skills
                      if (_staff!.skills != null && _staff!.skills!.isNotEmpty)
                        _buildChipsSection('Skills', Icons.star, _staff!.skills!),

                      // Hobbies
                      if (_staff!.hobbies != null && _staff!.hobbies!.isNotEmpty)
                        _buildChipsSection('Hobbies', Icons.favorite, _staff!.hobbies!),

                      // Referee 1
                      if (_staff!.referee1Name != null &&
                          _staff!.referee1Name!.isNotEmpty)
                        _buildSection(
                          'Referee/Guarantor 1',
                          Icons.person_outline,
                          [
                            _buildInfoRow('Name', _staff!.referee1Name!),
                            _buildInfoRow('Phone', _staff!.referee1Phone ?? 'N/A'),
                            _buildInfoRow('Relationship', _staff!.referee1Relationship ?? 'N/A'),
                            _buildInfoRow('Address', _staff!.referee1Address ?? 'N/A'),
                          ],
                        ),

                      // Referee 2
                      if (_staff!.referee2Name != null &&
                          _staff!.referee2Name!.isNotEmpty)
                        _buildSection(
                          'Referee/Guarantor 2',
                          Icons.person_outline,
                          [
                            _buildInfoRow('Name', _staff!.referee2Name!),
                            _buildInfoRow('Phone', _staff!.referee2Phone ?? 'N/A'),
                            _buildInfoRow('Relationship', _staff!.referee2Relationship ?? 'N/A'),
                            _buildInfoRow('Address', _staff!.referee2Address ?? 'N/A'),
                          ],
                        ),

                      // Employment
                      _buildSection(
                        'Employment',
                        Icons.badge,
                        [
                          _buildInfoRow('Date of Employment', _formatDate(_staff!.dateOfEmployment)),
                          _buildInfoRow(
                            'Salary',
                            _staff!.salary > 0
                                ? NumberFormat.currency(symbol: 'N', decimalDigits: 2)
                                    .format(_staff!.salary)
                                : 'Not set',
                          ),
                        ],
                      ),

                      // Bank Account Details
                      if (_staff!.bankName != null && _staff!.bankName!.isNotEmpty)
                        _buildSection(
                          'Salary Account Details',
                          Icons.account_balance,
                          [
                            _buildInfoRow('Bank Name', _staff!.bankName!),
                            _buildInfoRow('Account Name', _staff!.accountName ?? 'N/A'),
                            _buildInfoRow('Account Number', _staff!.accountNumber ?? 'N/A'),
                          ],
                        ),

                      // Class Allocations
                      if (_classAllocations.isNotEmpty)
                        _buildSection(
                          'Class Allocations',
                          Icons.class_,
                          _classAllocations
                              .map((a) => _buildInfoRow(
                                    '${a['className']} - ${a['armName']}',
                                    a['subjectsTaught'] ?? '',
                                  ))
                              .toList(),
                        ),

                      // Office Allocations
                      if (_officeAllocations.isNotEmpty)
                        _buildChipsSection(
                          'Office Allocations',
                          Icons.business,
                          _officeAllocations.map((a) => a['officeName'] as String).toList(),
                        ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'N/A' : value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipsSection(String title, IconData icon, List<String> items) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items
                  .map((item) => Chip(
                        label: Text(item),
                        backgroundColor: Colors.blue.withValues(alpha: 0.1),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
