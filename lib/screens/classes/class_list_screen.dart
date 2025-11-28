import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';
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
  final DatabaseHelper _db = DatabaseHelper();
  List<SchoolClass> _classes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _loading = true);
    final data = await _db.database.then((db) => db.query('classes'));

    setState(() {
      _classes = data.map((e) => SchoolClass.fromMap(e)).toList();
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

                    return Card(
                      child: ListTile(
                        title: Text(c.name),

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
