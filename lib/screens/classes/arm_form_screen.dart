import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';
import 'package:bursary_manager/models/arm.dart';

class ArmFormScreen extends StatefulWidget {
  final int classId;
  final Arm? arm;

  const ArmFormScreen({super.key, required this.classId, this.arm});

  @override
  State<ArmFormScreen> createState() => _ArmFormScreenState();
}

class _ArmFormScreenState extends State<ArmFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _saving = false;
  final DatabaseHelper _db = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    if (widget.arm != null) {
      _nameCtrl.text = widget.arm!.name;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final arm = Arm(
      id: widget.arm?.id,
      classId: widget.classId,
      name: _nameCtrl.text.trim(),
    );

    final db = await _db.database;

    if (arm.id == null) {
      await db.insert('arms', arm.toMap());
    } else {
      await db.update(
        'arms',
        arm.toMap(),
        where: 'id = ?',
        whereArgs: [arm.id],
      );
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.arm != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Arm' : 'Add Arm')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Arm Name (e.g., A, B, C)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
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
