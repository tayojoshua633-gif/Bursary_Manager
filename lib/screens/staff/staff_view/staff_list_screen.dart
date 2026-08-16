// lib/screens/staff/staff_view/staff_list_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import 'staff_details_screen.dart';
import 'staff_table_screen.dart';

class StaffListScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const StaffListScreen({super.key, required this.currentUser});

  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen> {
  final _dbHelper = DatabaseHelper();
  final _searchController = TextEditingController();
  List<Staff> _allStaff = [];
  List<Staff> _filteredStaff = [];
  bool _isLoading = true;
  String _filterType = 'All';

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStaff = _allStaff.where((staff) {
        final matchesSearch = staff.fullName.toLowerCase().contains(query) ||
            staff.staffId.toLowerCase().contains(query);
        final matchesType = _filterType == 'All' || staff.staffType == _filterType;
        return matchesSearch && matchesType;
      }).toList();
    });
  }

  Future<void> _deleteStaff(Staff staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Staff'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete ${staff.fullName}?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. The staff profile will be removed, but their '
                      'payment records (loans, incentives, deductions, payroll history) will remain '
                      'in the system.',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dbHelper.deleteStaff(staff.id!);
        _loadStaff();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${staff.fullName} deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting staff: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff List'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Table View',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StaffTableScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.withValues(alpha: 0.1),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search staff...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (_) => _applyFilter(),
                ),
                const SizedBox(height: 12),
                Row(
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
                  ],
                ),
              ],
            ),
          ),
          // Staff Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${_filteredStaff.length} staff found',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          // Staff List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredStaff.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No staff found',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredStaff.length,
                        itemBuilder: (ctx, i) {
                          final staff = _filteredStaff[i];
                          return _StaffCard(
                            staff: staff,
                            onTap: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StaffDetailsScreen(
                                    staffId: staff.id!,
                                    currentUser: widget.currentUser,
                                  ),
                                ),
                              );
                              if (result == true) _loadStaff();
                            },
                            onDelete: () => _deleteStaff(staff),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final Staff staff;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _StaffCard({required this.staff, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Photo or Avatar
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: staff.photoPath != null && File(staff.photoPath!).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(staff.photoPath!),
                          fit: BoxFit.cover,
                        ),
                      )
                    : Center(
                        child: Text(
                          staff.fullName[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      staff.staffId,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
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
                          fontSize: 11,
                          color: staff.isTeachingStaff
                              ? Colors.green[700]
                              : Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Actions
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                    onPressed: onDelete,
                    tooltip: 'Delete Staff',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
