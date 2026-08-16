import 'package:flutter/material.dart';
import 'package:bursary_manager/data/database_helper_wrapper.dart';
import '../../db/database_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';

class InactiveStudentsScreen extends StatefulWidget {
  const InactiveStudentsScreen({super.key});

  @override
  State<InactiveStudentsScreen> createState() =>
      _InactiveStudentsScreenState();
}

class _InactiveStudentsScreenState extends State<InactiveStudentsScreen> {
  final db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> students = [];
  bool loading = true;
  Set<String> _siblingPhones = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    _allStudents = await db.getInactiveStudents();
    _siblingPhones = computeSiblingPhones(await db.getActiveStudents());
    _applyFilter();
    setState(() => loading = false);
  }

  void _applyFilter() {
    final keyword = _searchCtrl.text.trim().toLowerCase();

    setState(() {
      if (keyword.isEmpty) {
        students = _allStudents;
        return;
      }

      students = _allStudents.where((s) {
        final surname = (s['surname']?.toString() ?? '').toLowerCase();
        final firstName = (s['firstName']?.toString() ?? '').toLowerCase();
        final otherName = (s['otherName']?.toString() ?? '').toLowerCase();
        final admissionNo = (s['admissionNo']?.toString() ?? '').toLowerCase();
        final className = (s['className']?.toString() ?? '').toLowerCase();
        final armName = (s['armName']?.toString() ?? '').toLowerCase();

        return surname.contains(keyword) ||
               firstName.contains(keyword) ||
               otherName.contains(keyword) ||
               admissionNo.contains(keyword) ||
               className.contains(keyword) ||
               armName.contains(keyword);
      }).toList();
    });
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
    // Block deletion if student is registered for any external examination
    final examRegs = await DatabaseHelper().getStudentExamRegistrations(id);
    if (examRegs.isNotEmpty) {
      final examList = examRegs
          .map((e) => '  •  ${e['name']} (${e['code']})')
          .join('\n');
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red),
              SizedBox(width: 8),
              Text('Cannot Delete Student'),
            ],
          ),
          content: Text(
            '$name is registered for the following external examination(s):\n\n'
            '$examList\n\n'
            'Remove the student from the examination registration first before deleting.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      hintText: "Search inactive students...",
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                _applyFilter();
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => _applyFilter(),
                  ),
                ),
                Expanded(
                  child: students.isEmpty
                      ? Center(
                          child: Text(
                            _searchCtrl.text.isEmpty
                                ? "No inactive students"
                                : "No inactive students match your search.",
                          ),
                        )
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
                                title: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                                    SiblingMark(
                                      show: isSiblingPhone(s['parentPhone'] as String?, _siblingPhones),
                                    ),
                                  ],
                                ),
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
                ),
              ],
            ),
    );
  }
}
