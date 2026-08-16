// lib/screens/staff/staff_view/staff_deactivate_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';

class StaffDeactivateScreen extends StatefulWidget {
  const StaffDeactivateScreen({super.key});

  @override
  State<StaffDeactivateScreen> createState() => _StaffDeactivateScreenState();
}

class _StaffDeactivateScreenState extends State<StaffDeactivateScreen>
    with SingleTickerProviderStateMixin {
  final _dbHelper = DatabaseHelper();
  late final TabController _tabController;

  List<Staff> _activeStaff = [];
  List<Staff> _inactiveStaff = [];
  bool _isLoading = true;

  final _searchActive = TextEditingController();
  final _searchInactive = TextEditingController();

  List<Staff> _filteredActive = [];
  List<Staff> _filteredInactive = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStaff();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchActive.dispose();
    _searchInactive.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final activeMaps = await _dbHelper.getStaff(includeInactive: false);
      final inactiveMaps = await _dbHelper.getInactiveStaff();
      setState(() {
        _activeStaff = activeMaps.map((m) => Staff.fromMap(m)).toList();
        _inactiveStaff = inactiveMaps.map((m) => Staff.fromMap(m)).toList();
        _filteredActive = List.from(_activeStaff);
        _filteredInactive = List.from(_inactiveStaff);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading staff: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filterActive(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredActive = _activeStaff.where((s) {
        return s.fullName.toLowerCase().contains(q) ||
            s.staffId.toLowerCase().contains(q) ||
            s.staffType.toLowerCase().contains(q);
      }).toList();
    });
  }

  void _filterInactive(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredInactive = _inactiveStaff.where((s) {
        return s.fullName.toLowerCase().contains(q) ||
            s.staffId.toLowerCase().contains(q) ||
            s.staffType.toLowerCase().contains(q);
      }).toList();
    });
  }

  Future<void> _deactivateStaff(Staff staff) async {
    DateTime deactivationDate = DateTime.now();
    DateTime firstAllowedDate = DateTime(2000);
    if (staff.dateOfEmployment != null) {
      try {
        firstAllowedDate = DateTime.parse(staff.dateOfEmployment!);
      } catch (_) {}
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Deactivate Staff'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to deactivate ${staff.fullName}?',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: deactivationDate,
                      firstDate: firstAllowedDate,
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => deactivationDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Deactivation Date',
                      prefixIcon: Icon(Icons.event_busy),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(DateFormat('dd MMM yyyy').format(deactivationDate)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Back-date this if the staff actually left earlier — payroll and '
                  'payment records for months after this date will no longer show them.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue),
                          SizedBox(width: 6),
                          Text(
                            'Records are preserved',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text(
                        'All historical records (salary, loans, incentives, deductions, payroll) '
                        'remain intact and accessible. The staff will be hidden from active '
                        'lists but can be reactivated at any time.',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_off, size: 18),
              label: const Text('Deactivate'),
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _dbHelper.deactivateStaff(
        staff.id!,
        deactivationDate: deactivationDate.toIso8601String(),
      );
      await _loadStaff();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${staff.fullName} has been deactivated. All records preserved.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
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
            Text('Permanently delete ${staff.fullName}\'s staff record?'),
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
                      'This cannot be undone. The staff profile will be removed, but their '
                      'payment records (salary, loans, incentives, deductions, payroll history) '
                      'will remain in the system.',
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
        await _loadStaff();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${staff.fullName} deleted. Payment records were preserved.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting staff: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _reactivateStaff(Staff staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivate Staff'),
        content: Text(
          'Reactivate ${staff.fullName} and add them back to the active staff list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.person_add, size: 18),
            label: const Text('Reactivate'),
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _dbHelper.reactivateStaff(staff.id!);
      await _loadStaff();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${staff.fullName} has been reactivated.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deactivate / Reactivate Staff'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.red.shade100,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Active (${_activeStaff.length})'),
            Tab(text: 'Inactive (${_inactiveStaff.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActiveTab(),
                _buildInactiveTab(),
              ],
            ),
    );
  }

  Widget _buildActiveTab() {
    return Column(
      children: [
        // Info banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.orange.shade50,
          child: Row(
            children: [
              Icon(Icons.warning_amber, size: 18, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Deactivating a staff hides them from active lists. '
                  'All salary, loan, incentive and payroll records are preserved.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
            ],
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchActive,
            decoration: const InputDecoration(
              hintText: 'Search by name, ID or type...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _filterActive,
          ),
        ),
        // List
        Expanded(
          child: _filteredActive.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        'No active staff found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filteredActive.length,
                  itemBuilder: (ctx, i) => _buildActiveCard(_filteredActive[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildInactiveTab() {
    return Column(
      children: [
        // Info banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.green.shade50,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'All past records (salary, loans, incentives, deductions) '
                  'are still available. Reactivate to restore full access.',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                ),
              ),
            ],
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchInactive,
            decoration: const InputDecoration(
              hintText: 'Search by name, ID or type...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _filterInactive,
          ),
        ),
        // List
        Expanded(
          child: _filteredInactive.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        'No inactive staff',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filteredInactive.length,
                  itemBuilder: (ctx, i) => _buildInactiveCard(_filteredInactive[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildActiveCard(Staff staff) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Photo or avatar
            _buildAvatar(staff, Colors.blue),
            const SizedBox(width: 12),
            // Staff info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    staff.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${staff.staffId}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: staff.isTeachingStaff
                          ? Colors.blue.shade50
                          : Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      staff.staffType,
                      style: TextStyle(
                        fontSize: 11,
                        color: staff.isTeachingStaff ? Colors.blue : Colors.purple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Deactivate button
            ElevatedButton.icon(
              icon: const Icon(Icons.person_off, size: 16),
              label: const Text('Deactivate'),
              onPressed: () => _deactivateStaff(staff),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInactiveCard(Staff staff) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Photo or avatar (greyed out)
            Stack(
              children: [
                _buildAvatar(staff, Colors.grey),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Staff info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    staff.fullName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${staff.staffId}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'INACTIVE',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        staff.staffType,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  if (staff.deactivationDate != null || staff.updatedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Deactivated: ${_formatDate(staff.deactivationDate ?? staff.updatedAt!)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ],
              ),
            ),
            // Reactivate / Delete buttons
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add, size: 16),
                  label: const Text('Reactivate'),
                  onPressed: () => _reactivateStaff(staff),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                  onPressed: () => _deleteStaff(staff),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(Staff staff, Color color) {
    if (staff.photoPath != null && File(staff.photoPath!).existsSync()) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: FileImage(File(staff.photoPath!)),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        staff.surname.isNotEmpty ? staff.surname[0].toUpperCase() : '?',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 18,
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }
}
