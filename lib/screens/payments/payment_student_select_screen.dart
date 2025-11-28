import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import 'payment_record_screen.dart';

class PaymentStudentSelectScreen extends StatefulWidget {
  /// OPTIONAL callback for clear-data screen
  final void Function(int studentId, String studentName)? onStudentSelected;

  const PaymentStudentSelectScreen({super.key, this.onStudentSelected});

  @override
  State<PaymentStudentSelectScreen> createState() =>
      _PaymentStudentSelectScreenState();
}

class _PaymentStudentSelectScreenState
    extends State<PaymentStudentSelectScreen> {
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

    _students = await _db.getAllStudents();

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

  // ============================================================
  // NORMAL APP FLOW: OPEN PAYMENT PAGE
  // CALLBACK MODE: RETURN SELECTED STUDENT TO CALLER
  // ============================================================
  void _selectStudent(Map<String, dynamic> student) {
    final int id = student['id'];
    final String name = "${student['surname']} ${student['firstName']}";

    if (widget.onStudentSelected != null) {
      // ---- callback mode ----
      widget.onStudentSelected!(id, name);
      return;
    }

    // ---- normal navigation ----
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentRecordScreen(
          studentId: id,
          studentName: name,
        ),
      ),
    );
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
        trailing: widget.onStudentSelected != null
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _selectStudent(s),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onStudentSelected != null
            ? "Select Student"
            : "Select Student for Payment"),
      ),
      body: Column(
        children: [
          // SEARCH INPUT
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
