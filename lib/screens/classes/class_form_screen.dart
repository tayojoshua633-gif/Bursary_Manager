import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';
import 'package:bursary_manager/models/class_model.dart';

class ClassFormScreen extends StatefulWidget {
  final SchoolClass? schoolClass;

  const ClassFormScreen({super.key, this.schoolClass});

  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final DatabaseHelper _db = DatabaseHelper();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.schoolClass != null) {
      _nameCtrl.text = widget.schoolClass!.name;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final cls = SchoolClass(
      id: widget.schoolClass?.id,
      name: _nameCtrl.text.trim(),
    );

    final db = await _db.database;

    if (cls.id == null) {
      await db.insert('classes', cls.toMap());
    } else {
      await db.update(
        'classes',
        cls.toMap(),
        where: 'id = ?',
        whereArgs: [cls.id],
      );
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.schoolClass != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Class' : 'Add Class')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Class Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Class name required' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
