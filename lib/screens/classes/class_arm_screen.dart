import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';

class ClassArmScreen extends StatefulWidget {
  final int classId;
  final String className;

  const ClassArmScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ClassArmScreen> createState() => _ClassArmScreenState();
}

class _ClassArmScreenState extends State<ClassArmScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Map<String, dynamic>> _arms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadArms();
  }

  Future<void> _loadArms() async {
    final db = await _db.database;
    final data = await db.query(
      'arms',
      where: 'classId = ?',
      whereArgs: [widget.classId],
      orderBy: 'name ASC',
    );

    setState(() {
      _arms = data;
      _loading = false;
    });
  }

  Future<void> _addArm() async {
    TextEditingController controller = TextEditingController();

    final result = await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Add Arm"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: "Arm Name (e.g., A, B, C)",
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text("Save"),
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
            ),
          ],
        );
      },
    );

    if (result != null) {
      final db = await _db.database;

      await db.insert('arms', {
        'classId': widget.classId,
        'name': result,
      });

      _loadArms();
    }
  }

  Future<void> _deleteArm(int id) async {
    final db = await _db.database;

    await db.delete(
      'arms',
      where: 'id = ?',
      whereArgs: [id],
    );

    _loadArms();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Arms for ${widget.className}"),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _arms.isEmpty
              ? const Center(child: Text("No arms added"))
              : ListView.builder(
                  itemCount: _arms.length,
                  itemBuilder: (context, index) {
                    final arm = _arms[index];
                    return Card(
                      child: ListTile(
                        title: Text("Arm ${arm['name']}"),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteArm(arm['id']),
                        ),
                      ),
                    );
                  },
                ),

      floatingActionButton: FloatingActionButton(
        onPressed: _addArm,
        child: const Icon(Icons.add),
      ),
    );
  }
}
