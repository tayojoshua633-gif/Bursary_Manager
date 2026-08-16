// lib/screens/staff/staff_setup/office_allocation_screen.dart
import 'package:flutter/material.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import '../../../models/staff_office.dart';

class OfficeAllocationScreen extends StatefulWidget {
  const OfficeAllocationScreen({super.key});

  @override
  State<OfficeAllocationScreen> createState() => _OfficeAllocationScreenState();
}

class _OfficeAllocationScreenState extends State<OfficeAllocationScreen> {
  final _dbHelper = DatabaseHelper();
  List<Staff> _allStaff = [];
  List<StaffOffice> _offices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final staffData = await _dbHelper.getStaff();
      final officesData = await _dbHelper.getStaffOffices();

      setState(() {
        _allStaff = staffData.map((e) => Staff.fromMap(e)).toList();
        _offices = officesData.map((e) => StaffOffice.fromMap(e)).toList();
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

  Future<void> _manageAllocation(Staff staff) async {
    final allocations = await _dbHelper.getStaffOfficeAllocations(staff.id!);
    final allocatedOfficeIds =
        allocations.map((a) => a['officeId'] as int).toSet();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OfficeAllocationBottomSheet(
        staff: staff,
        offices: _offices,
        allocatedOfficeIds: allocatedOfficeIds,
        dbHelper: _dbHelper,
        onSaved: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Office Allocation'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allStaff.isEmpty
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
              : _offices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.business_outlined,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No offices created',
                            style:
                                TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create offices first',
                            style:
                                TextStyle(fontSize: 14, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _allStaff.length,
                      itemBuilder: (ctx, i) {
                        final staff = _allStaff[i];
                        return FutureBuilder<List<Map<String, dynamic>>>(
                          future: _dbHelper.getStaffOfficeAllocations(staff.id!),
                          builder: (context, snapshot) {
                            final allocations = snapshot.data ?? [];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor:
                                              Colors.orange.withValues(alpha: 0.2),
                                          child: Text(
                                            staff.fullName[0].toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                staff.fullName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              Text(
                                                '${staff.staffId} - ${staff.staffType}',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              _manageAllocation(staff),
                                          icon: const Icon(Icons.edit, size: 16),
                                          label: const Text('Allocate'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (allocations.isNotEmpty) ...[
                                      const Divider(height: 24),
                                      const Text(
                                        'Allocated Offices:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: allocations.map((alloc) {
                                          return Chip(
                                            avatar: const Icon(Icons.business,
                                                size: 16),
                                            label: Text(
                                                alloc['officeName'] ?? 'Unknown'),
                                            backgroundColor:
                                                Colors.orange.withValues(alpha: 0.1),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}

class _OfficeAllocationBottomSheet extends StatefulWidget {
  final Staff staff;
  final List<StaffOffice> offices;
  final Set<int> allocatedOfficeIds;
  final DatabaseHelper dbHelper;
  final VoidCallback onSaved;

  const _OfficeAllocationBottomSheet({
    required this.staff,
    required this.offices,
    required this.allocatedOfficeIds,
    required this.dbHelper,
    required this.onSaved,
  });

  @override
  State<_OfficeAllocationBottomSheet> createState() =>
      _OfficeAllocationBottomSheetState();
}

class _OfficeAllocationBottomSheetState
    extends State<_OfficeAllocationBottomSheet> {
  late Set<int> _selectedOfficeIds;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedOfficeIds = Set.from(widget.allocatedOfficeIds);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      // Delete all existing allocations
      await widget.dbHelper.deleteAllStaffOfficeAllocations(widget.staff.id!);

      // Insert new allocations
      for (final officeId in _selectedOfficeIds) {
        await widget.dbHelper.insertStaffOfficeAllocation({
          'staffId': widget.staff.id,
          'officeId': officeId,
        });
      }

      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Office allocations saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.meeting_room, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Office Allocation',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        widget.staff.fullName,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Select offices to allocate (multiple selection allowed)',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.offices.length,
              itemBuilder: (ctx, i) {
                final office = widget.offices[i];
                final isSelected = _selectedOfficeIds.contains(office.id);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedOfficeIds.add(office.id!);
                      } else {
                        _selectedOfficeIds.remove(office.id);
                      }
                    });
                  },
                  title: Text(office.name),
                  subtitle: office.description != null &&
                          office.description!.isNotEmpty
                      ? Text(office.description!)
                      : null,
                  secondary: Icon(
                    Icons.business,
                    color: isSelected ? Colors.orange : Colors.grey,
                  ),
                  activeColor: Colors.orange,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save Allocations'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
