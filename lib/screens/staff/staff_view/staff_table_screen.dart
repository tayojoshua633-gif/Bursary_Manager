// lib/screens/staff/staff_view/staff_table_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import '../../../utils/staff_listing_pdf_generator.dart';

class StaffTableScreen extends StatefulWidget {
  const StaffTableScreen({super.key});

  @override
  State<StaffTableScreen> createState() => _StaffTableScreenState();
}

class _StaffTableScreenState extends State<StaffTableScreen> {
  final _dbHelper = DatabaseHelper();
  final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 0);
  List<Staff> _allStaff = [];
  List<Staff> _filteredStaff = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String _filterType = 'All';
  String _sortBy = 'name';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final staffData = await _dbHelper.getStaff();
      setState(() {
        _allStaff = staffData.map((e) => Staff.fromMap(e)).toList();
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyFilter() {
    setState(() {
      _filteredStaff = _allStaff.where((staff) {
        return _filterType == 'All' || staff.staffType == _filterType;
      }).toList();

      // Sort
      _filteredStaff.sort((a, b) {
        int result;
        switch (_sortBy) {
          case 'id':
            result = a.staffId.compareTo(b.staffId);
            break;
          case 'type':
            result = a.staffType.compareTo(b.staffType);
            break;
          case 'salary':
            result = a.salary.compareTo(b.salary);
            break;
          case 'name':
          default:
            result = a.fullName.compareTo(b.fullName);
        }
        return _sortAscending ? result : -result;
      });
    });
  }

  void _sort(String column) {
    setState(() {
      if (_sortBy == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = column;
        _sortAscending = true;
      }
      _applyFilter();
    });
  }

  Future<void> _exportToPDF() async {
    if (_filteredStaff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No staff to export')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final schoolProfile = await _dbHelper.getSchoolProfile();
      final teachingCount = _filteredStaff.where((s) => s.isTeachingStaff).length;
      final nonTeachingCount = _filteredStaff.where((s) => !s.isTeachingStaff).length;
      final totalSalary = _filteredStaff.fold<double>(0, (sum, s) => sum + s.salary);

      final filePath = await StaffListingPDFGenerator.generateStaffListingPDF(
        staff: _filteredStaff,
        schoolProfile: schoolProfile ?? {},
        filterType: _filterType,
        totalStaff: _filteredStaff.length,
        teachingCount: teachingCount,
        nonTeachingCount: nonTeachingCount,
        totalSalary: totalSalary,
      );

      if (mounted) {
        setState(() => _isExporting = false);
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Staff Listing - $_filterType',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Listing'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filter and Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blueGrey.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Text('Filter: '),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _filterType == 'All',
                        onSelected: (_) {
                          setState(() => _filterType = 'All');
                          _applyFilter();
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Teaching'),
                        selected: _filterType == 'Teaching Staff',
                        onSelected: (_) {
                          setState(() => _filterType = 'Teaching Staff');
                          _applyFilter();
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Non-Teaching'),
                        selected: _filterType == 'Non-Teaching Staff',
                        onSelected: (_) {
                          setState(() => _filterType = 'Non-Teaching Staff');
                          _applyFilter();
                        },
                      ),
                      const Spacer(),
                      Text(
                        '${_filteredStaff.length} staff',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportToPDF,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          foregroundColor: Colors.white,
                        ),
                        icon: _isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf, size: 18),
                        label: Text(_isExporting ? 'Exporting...' : 'Export PDF'),
                      ),
                    ],
                  ),
                ),
                // Table
                Expanded(
                  child: _filteredStaff.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No staff found',
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              sortColumnIndex: _getSortColumnIndex(),
                              sortAscending: _sortAscending,
                              headingRowColor: WidgetStateProperty.all(
                                Colors.blueGrey.withValues(alpha: 0.1),
                              ),
                              columns: [
                                DataColumn(
                                  label: const Text('S/N', style: TextStyle(fontWeight: FontWeight.bold)),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: const Text('Staff ID', style: TextStyle(fontWeight: FontWeight.bold)),
                                  onSort: (_, _) => _sort('id'),
                                ),
                                DataColumn(
                                  label: const Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold)),
                                  onSort: (_, _) => _sort('name'),
                                ),
                                DataColumn(
                                  label: const Text('Gender', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                DataColumn(
                                  label: const Text('Staff Type', style: TextStyle(fontWeight: FontWeight.bold)),
                                  onSort: (_, _) => _sort('type'),
                                ),
                                DataColumn(
                                  label: const Text('Phone', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                DataColumn(
                                  label: const Text('Salary', style: TextStyle(fontWeight: FontWeight.bold)),
                                  numeric: true,
                                  onSort: (_, _) => _sort('salary'),
                                ),
                              ],
                              rows: _filteredStaff.asMap().entries.map((entry) {
                                final index = entry.key;
                                final staff = entry.value;
                                return DataRow(
                                  cells: [
                                    DataCell(Text('${index + 1}')),
                                    DataCell(Text(staff.staffId)),
                                    DataCell(Text(staff.fullName)),
                                    DataCell(Text(staff.gender)),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: staff.isTeachingStaff
                                              ? Colors.green.withValues(alpha: 0.2)
                                              : Colors.orange.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          staff.staffType,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: staff.isTeachingStaff
                                                ? Colors.green[700]
                                                : Colors.orange[700],
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(staff.phone ?? '-')),
                                    DataCell(
                                      Text(
                                        staff.salary > 0
                                            ? _currencyFormat.format(staff.salary)
                                            : '-',
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ),
                // Summary Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.1),
                    border: Border(
                      top: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        'Total Staff',
                        _filteredStaff.length.toString(),
                        Icons.people,
                      ),
                      _buildSummaryItem(
                        'Teaching',
                        _filteredStaff
                            .where((s) => s.isTeachingStaff)
                            .length
                            .toString(),
                        Icons.school,
                      ),
                      _buildSummaryItem(
                        'Non-Teaching',
                        _filteredStaff
                            .where((s) => !s.isTeachingStaff)
                            .length
                            .toString(),
                        Icons.work,
                      ),
                      _buildSummaryItem(
                        'Total Salary',
                        _currencyFormat.format(
                          _filteredStaff.fold<double>(
                            0,
                            (sum, s) => sum + s.salary,
                          ),
                        ),
                        Icons.payments,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  int? _getSortColumnIndex() {
    switch (_sortBy) {
      case 'id':
        return 1;
      case 'name':
        return 2;
      case 'type':
        return 4;
      case 'salary':
        return 6;
      default:
        return null;
    }
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blueGrey, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
