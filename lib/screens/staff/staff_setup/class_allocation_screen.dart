// lib/screens/staff/staff_setup/class_allocation_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';

class ClassAllocationScreen extends StatefulWidget {
  const ClassAllocationScreen({super.key});

  @override
  State<ClassAllocationScreen> createState() => _ClassAllocationScreenState();
}

class _ClassAllocationScreenState extends State<ClassAllocationScreen> {
  final _dbHelper = DatabaseHelper();
  List<Staff> _teachingStaff = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final staffData = await _dbHelper.getTeachingStaff();
      final classesData = await _dbHelper.getClasses();
      final armsData = await _dbHelper.getArms();

      setState(() {
        _teachingStaff = staffData.map((e) => Staff.fromMap(e)).toList();
        _classes = classesData;
        _arms = armsData;
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

  List<Map<String, dynamic>> _getArmsForClass(int classId) {
    return _arms.where((a) => a['classId'] == classId).toList();
  }

  bool _isSecondaryClass(String className) {
    final lower = className.toLowerCase();
    return lower.contains('jss') ||
        lower.contains('sss') ||
        lower.contains('js ') ||
        lower.contains('ss ') ||
        lower.contains('junior') ||
        lower.contains('senior');
  }

  Future<void> _manageAllocation(Staff staff) async {
    // Load current allocations for this staff
    final allocations = await _dbHelper.getStaffClassAllocations(staff.id!);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AllocationBottomSheet(
        staff: staff,
        classes: _classes,
        arms: _arms,
        currentAllocations: allocations,
        dbHelper: _dbHelper,
        isSecondaryClass: _isSecondaryClass,
        onSaved: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Allocation'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _teachingStaff.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No teaching staff found',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Register teaching staff first',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _teachingStaff.length,
                  itemBuilder: (ctx, i) {
                    final staff = _teachingStaff[i];
                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: _dbHelper.getStaffClassAllocations(staff.id!),
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
                                          Colors.deepPurple.withValues(alpha: 0.2),
                                      child: Text(
                                        staff.fullName[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.deepPurple,
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
                                            staff.staffId,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () => _manageAllocation(staff),
                                      icon: const Icon(Icons.edit, size: 16),
                                      label: const Text('Allocate'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.deepPurple,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                if (allocations.isNotEmpty) ...[
                                  const Divider(height: 24),
                                  const Text(
                                    'Allocated Classes:',
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
                                      final className = alloc['className'] ?? '';
                                      final armName = alloc['armName'] ?? '';
                                      final subjects = alloc['subjectsTaught'];
                                      List<String> subjectList = [];
                                      if (subjects != null &&
                                          subjects.toString().isNotEmpty) {
                                        try {
                                          subjectList = (jsonDecode(subjects) as List)
                                              .map((e) => e.toString())
                                              .toList();
                                        } catch (_) {}
                                      }
                                      return Chip(
                                        label: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('$className - $armName'),
                                            if (subjectList.isNotEmpty)
                                              Text(
                                                subjectList.join(', '),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                          ],
                                        ),
                                        backgroundColor:
                                            Colors.deepPurple.withValues(alpha: 0.1),
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

class _AllocationBottomSheet extends StatefulWidget {
  final Staff staff;
  final List<Map<String, dynamic>> classes;
  final List<Map<String, dynamic>> arms;
  final List<Map<String, dynamic>> currentAllocations;
  final DatabaseHelper dbHelper;
  final bool Function(String) isSecondaryClass;
  final VoidCallback onSaved;

  const _AllocationBottomSheet({
    required this.staff,
    required this.classes,
    required this.arms,
    required this.currentAllocations,
    required this.dbHelper,
    required this.isSecondaryClass,
    required this.onSaved,
  });

  @override
  State<_AllocationBottomSheet> createState() => _AllocationBottomSheetState();
}

class _AllocationBottomSheetState extends State<_AllocationBottomSheet> {
  final List<_ClassArmAllocation> _allocations = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Load existing allocations
    for (final alloc in widget.currentAllocations) {
      List<String> subjects = [];
      if (alloc['subjectsTaught'] != null &&
          alloc['subjectsTaught'].toString().isNotEmpty) {
        try {
          subjects = (jsonDecode(alloc['subjectsTaught']) as List)
              .map((e) => e.toString())
              .toList();
        } catch (_) {}
      }
      _allocations.add(_ClassArmAllocation(
        classId: alloc['classId'],
        armId: alloc['armId'],
        subjects: subjects,
      ));
    }
  }

  List<Map<String, dynamic>> _getArmsForClass(int classId) {
    return widget.arms.where((a) => a['classId'] == classId).toList();
  }

  void _addAllocation() {
    if (widget.classes.isEmpty) return;
    final firstClass = widget.classes.first;
    final armsForClass = _getArmsForClass(firstClass['id']);
    if (armsForClass.isEmpty) return;

    setState(() {
      _allocations.add(_ClassArmAllocation(
        classId: firstClass['id'],
        armId: armsForClass.first['id'],
        subjects: [],
      ));
    });
  }

  void _removeAllocation(int index) {
    setState(() {
      _allocations.removeAt(index);
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      // Delete all existing allocations
      await widget.dbHelper.deleteAllStaffClassAllocations(widget.staff.id!);

      // Insert new allocations
      for (final alloc in _allocations) {
        await widget.dbHelper.insertStaffClassAllocation({
          'staffId': widget.staff.id,
          'classId': alloc.classId,
          'armId': alloc.armId,
          'subjectsTaught':
              alloc.subjects.isNotEmpty ? jsonEncode(alloc.subjects) : null,
        });
      }

      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Class allocations saved'),
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
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.class_, color: Colors.deepPurple),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Class Allocation',
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
          Expanded(
            child: _allocations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.class_outlined,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('No classes allocated'),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _addAllocation,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Class'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _allocations.length,
                    itemBuilder: (ctx, i) {
                      final alloc = _allocations[i];
                      final selectedClass = widget.classes.firstWhere(
                        (c) => c['id'] == alloc.classId,
                        orElse: () => widget.classes.first,
                      );
                      final armsForClass = _getArmsForClass(alloc.classId);
                      final isSecondary =
                          widget.isSecondaryClass(selectedClass['name'] ?? '');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      initialValue: alloc.classId,
                                      decoration: const InputDecoration(
                                        labelText: 'Class',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: widget.classes
                                          .map((c) => DropdownMenuItem<int>(
                                                value: c['id'],
                                                child: Text(c['name']),
                                              ))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v == null) return;
                                        final newArms = _getArmsForClass(v);
                                        setState(() {
                                          alloc.classId = v;
                                          alloc.armId = newArms.isNotEmpty
                                              ? newArms.first['id']
                                              : 0;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      initialValue: armsForClass
                                              .any((a) => a['id'] == alloc.armId)
                                          ? alloc.armId
                                          : (armsForClass.isNotEmpty
                                              ? armsForClass.first['id']
                                              : null),
                                      decoration: const InputDecoration(
                                        labelText: 'Arm',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: armsForClass
                                          .map((a) => DropdownMenuItem<int>(
                                                value: a['id'],
                                                child: Text(a['name']),
                                              ))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() {
                                          alloc.armId = v;
                                        });
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _removeAllocation(i),
                                    icon:
                                        const Icon(Icons.delete, color: Colors.red),
                                  ),
                                ],
                              ),
                              if (isSecondary) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  initialValue: alloc.subjects.join(', '),
                                  decoration: const InputDecoration(
                                    labelText: 'Subjects Taught (comma separated)',
                                    border: OutlineInputBorder(),
                                    hintText: 'e.g., Mathematics, Physics',
                                  ),
                                  onChanged: (v) {
                                    alloc.subjects = v
                                        .split(',')
                                        .map((s) => s.trim())
                                        .where((s) => s.isNotEmpty)
                                        .toList();
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addAllocation,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Class'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassArmAllocation {
  int classId;
  int armId;
  List<String> subjects;

  _ClassArmAllocation({
    required this.classId,
    required this.armId,
    required this.subjects,
  });
}
