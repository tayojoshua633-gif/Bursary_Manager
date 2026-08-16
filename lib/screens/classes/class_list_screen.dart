import 'package:flutter/material.dart';
import 'package:bursary_manager/data/database_helper_wrapper.dart';
import 'package:bursary_manager/models/class_model.dart';
import 'class_form_screen.dart';
import 'class_arm_screen.dart'; // for managing arms

class ClassListScreen extends StatefulWidget {
  /// OPTIONAL callback for screens like ClearDataScreen
  final void Function(int classId)? onClassSelected;

  const ClassListScreen({super.key, this.onClassSelected});

  @override
  State<ClassListScreen> createState() => _ClassListScreenState();
}

class _ClassListScreenState extends State<ClassListScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  List<SchoolClass> _classes = [];
  Map<int, List<String>> _classArms = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _loading = true);
    final db = await _db.database;
    final classData = await db.query('classes');
    final armData = await db.query('arms', orderBy: 'name ASC');

    final armsMap = <int, List<String>>{};
    for (final arm in armData) {
      final classId = arm['classId'] as int;
      armsMap.putIfAbsent(classId, () => []).add(arm['name'] as String);
    }

    setState(() {
      _classes = classData.map((e) => SchoolClass.fromMap(e)).toList();
      _classArms = armsMap;
      _loading = false;
    });
  }

  void _openForm({SchoolClass? cls}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassFormScreen(schoolClass: cls),
      ),
    );

    if (result == true) {
      _loadClasses();
    }
  }

  void _openArms(SchoolClass cls) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassArmScreen(
          classId: cls.id!,
          className: cls.name,
        ),
      ),
    ).then((value) => _loadClasses());
  }

  Future<void> _deleteClass(SchoolClass cls) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = await _db.database;

    final armNames = _classArms[cls.id] ?? [];

    final studentCountResult = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM students WHERE classId = ?',
      [cls.id],
    );
    final studentCount = (studentCountResult.first['cnt'] as int?) ?? 0;

    final classFeesResult = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM class_fees WHERE classId = ?',
      [cls.id],
    );
    final specialFeesResult = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM special_class_fees WHERE classId = ?',
      [cls.id],
    );
    final feeCount = ((classFeesResult.first['cnt'] as int?) ?? 0) +
        ((specialFeesResult.first['cnt'] as int?) ?? 0);

    if (!mounted) return;

    if (studentCount > 0 || feeCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red),
              SizedBox(width: 8),
              Text("Cannot Delete Class"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${cls.name}" cannot be deleted because it still has data attached to it:',
              ),
              if (studentCount > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.people, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$studentCount student(s) are currently enrolled in this class/arm.',
                          style: const TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (feeCount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Fees have been assigned to this class/arm ($feeCount assignment(s)).',
                          style: const TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                studentCount > 0
                    ? 'Move or deactivate these students to another class first, then try again.'
                    : 'Remove the fee assignments from this class/arm first, then try again.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text("Delete Class"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              armNames.isEmpty
                  ? 'Are you sure you want to delete "${cls.name}"?'
                  : 'Are you sure you want to delete "${cls.name}" and its ${armNames.length} arm(s) (${armNames.join(', ')})?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
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
                  Icon(Icons.info_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone!',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await db.delete('arms', where: 'classId = ?', whereArgs: [cls.id]);
    await db.delete('classes', where: 'id = ?', whereArgs: [cls.id]);

    if (!mounted) return;

    await _loadClasses();

    messenger.showSnackBar(
      SnackBar(content: Text('Class "${cls.name}" deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Classes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? const Center(child: Text('No classes added'))
              : ListView.builder(
                  itemCount: _classes.length,
                  itemBuilder: (context, index) {
                    final c = _classes[index];

                    final arms = _classArms[c.id] ?? [];

                    return Card(
                      child: ListTile(
                        title: Text(c.name),
                        subtitle: arms.isEmpty
                            ? const Text('No arms', style: TextStyle(color: Colors.grey))
                            : Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: arms
                                    .map((a) => Chip(
                                          label: Text(a),
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        ))
                                    .toList(),
                              ),

                        // ================================
                        // NEW: callback support
                        // ================================
                        onTap: () {
                          if (widget.onClassSelected != null) {
                            widget.onClassSelected!(c.id!);
                            return;
                          }

                          // normal behavior (edit class)
                          _openForm(cls: c);
                        },

                        trailing: widget.onClassSelected != null
                            ? null // Hide edit buttons when used for selection
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: "Manage Arms",
                                    icon: const Icon(Icons.view_list),
                                    onPressed: () => _openArms(c),
                                  ),
                                  IconButton(
                                    tooltip: "Edit Class",
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _openForm(cls: c),
                                  ),
                                  IconButton(
                                    tooltip: "Delete Class",
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteClass(c),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                ),

      floatingActionButton: widget.onClassSelected != null
          ? null // hide FAB when used as a picker
          : FloatingActionButton(
              onPressed: () => _openForm(),
              child: const Icon(Icons.add),
            ),
    );
  }
}
