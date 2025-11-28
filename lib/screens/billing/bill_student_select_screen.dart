import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import 'bill_generate_screen.dart';

class BillStudentSelectScreen extends StatefulWidget {
  const BillStudentSelectScreen({super.key});

  @override
  State<BillStudentSelectScreen> createState() =>
      _BillStudentSelectScreenState();
}

class _BillStudentSelectScreenState extends State<BillStudentSelectScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);

    final rows = await _db.getAllStudents();
    _students = rows;

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _search() async {
    final kw = _searchCtrl.text.trim();
    setState(() => _loading = true);

    if (kw.isEmpty) {
      _students = await _db.getAllStudents();
    } else {
      _students = await _db.searchStudents(kw);
    }

    if (mounted) setState(() => _loading = false);
  }

  void _openBilling(Map<String, dynamic> student) async {
    final id = student['id'];
    final name = "${student['surname']} ${student['firstName']}";

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BillGenerateScreen(
          studentId: id,
          studentName: name,
        ),
      ),
    );

    // If bill was saved, refresh list to reflect any updates
    if (result == true) _loadStudents();
  }

  Widget _studentTile(Map<String, dynamic> s) {
    final name = "${s['surname']} ${s['firstName']}".trim();
    final adm = s['admissionNo'] ?? '';
    final cls = s['className'] ?? '';
    final arm = s['armName'] ?? '';

    return Card(
      child: ListTile(
        title: Text(name),
        subtitle: Text("Adm: $adm   |   $cls $arm"),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _openBilling(s),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select Student for Billing")),
      body: Column(
        children: [
          // SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: "Search by name or admission no.",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                    ? const Center(child: Text("No students found."))
                    : ListView.builder(
                        itemCount: _students.length,
                        itemBuilder: (_, i) => _studentTile(_students[i]),
                      ),
          ),
        ],
      ),
    );
  }
}
