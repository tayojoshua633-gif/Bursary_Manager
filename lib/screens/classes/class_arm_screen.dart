import 'package:flutter/material.dart';
import 'package:bursary_manager/data/database_helper_wrapper.dart';

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
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
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

  Future<void> _deleteArm(int id, String armName) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = await _db.database;

    final studentCountResult = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM students WHERE armId = ?',
      [id],
    );
    final studentCount = (studentCountResult.first['cnt'] as int?) ?? 0;

    final classFeesResult = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM class_fees WHERE armId = ?',
      [id],
    );
    final specialFeesResult = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM special_class_fees WHERE armId = ?',
      [id],
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
              Text("Cannot Delete Arm"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Arm "$armName" cannot be deleted because it still has data attached to it:',
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
                          '$studentCount student(s) are currently enrolled in this arm.',
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
                          'Fees have been assigned to this arm ($feeCount assignment(s)).',
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
                    ? 'Move or deactivate these students to another class/arm first, then try again.'
                    : 'Remove the fee assignments from this arm first, then try again.',
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
            Text("Delete Arm"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete Arm "$armName"?',
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

    await db.delete(
      'arms',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (!mounted) return;

    _loadArms();

    messenger.showSnackBar(
      SnackBar(content: Text('Arm "$armName" deleted')),
    );
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
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteArm(arm['id'], arm['name']?.toString() ?? ''),
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
