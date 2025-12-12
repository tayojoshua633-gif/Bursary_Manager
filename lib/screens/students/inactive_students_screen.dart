import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';

class InactiveStudentsScreen extends StatefulWidget {
  const InactiveStudentsScreen({super.key});

  @override
  State<InactiveStudentsScreen> createState() =>
      _InactiveStudentsScreenState();
}

class _InactiveStudentsScreenState extends State<InactiveStudentsScreen> {
  final db = DatabaseHelper();
  List<Map<String, dynamic>> students = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    students = await db.getInactiveStudents();
    setState(() => loading = false);
  }

  Future<void> _restore(int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Restore Student"),
        content: Text("Restore $name back to active students?"),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            child: const Text("Restore"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (ok == true) {
      await db.restoreStudent(id);
      _load();
    }
  }

  Future<void> _delete(int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Permanently"),
        content: Text(
            "This will permanently remove $name and all data.\nAre you VERY sure?"),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (ok == true) {
      await db.deleteStudent(id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Inactive Students"),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : students.isEmpty
              ? const Center(child: Text("No inactive students"))
              : ListView.builder(
                  itemCount: students.length,
                  itemBuilder: (_, i) {
                    final s = students[i];
                    final name =
                        "${s['surname']} ${s['firstName']} (${s['admissionNo']})";

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: ListTile(
                        title: Text(name),
                        subtitle:
                            Text("${s['className']} - ${s['armName']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: "Restore",
                              icon: const Icon(Icons.restore),
                              onPressed: () => _restore(s['id'], name),
                            ),
                            IconButton(
                              tooltip: "Delete Permanently",
                              icon: const Icon(Icons.delete_forever,
                                  color: Colors.red),
                              onPressed: () => _delete(s['id'], name),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
