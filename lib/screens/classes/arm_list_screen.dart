import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';
import 'package:bursary_manager/models/arm.dart';
import 'arm_form_screen.dart';

class ArmListScreen extends StatefulWidget {
  final int classId; // only arms under this class

  const ArmListScreen({super.key, required this.classId});

  @override
  State<ArmListScreen> createState() => _ArmListScreenState();
}

class _ArmListScreenState extends State<ArmListScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Arm> _arms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadArms();
  }

  Future<void> _loadArms() async {
    setState(() => _loading = true);

    final db = await _db.database;
    final data = await db.query(
      'arms',
      where: 'classId = ?',
      whereArgs: [widget.classId],
    );

    setState(() {
      _arms = data.map((e) => Arm.fromMap(e)).toList();
      _loading = false;
    });
  }

  void _openForm({Arm? arm}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArmFormScreen(
          classId: widget.classId,
          arm: arm,
        ),
      ),
    );

    if (result == true) _loadArms();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arms')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _arms.isEmpty
              ? const Center(child: Text('No arms added'))
              : ListView.builder(
                  itemCount: _arms.length,
                  itemBuilder: (context, index) {
                    final arm = _arms[index];
                    return Card(
                      child: ListTile(
                        title: Text(arm.name),
                        onTap: () => _openForm(arm: arm),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
