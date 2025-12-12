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
  List<Map<String, dynamic>> _allStudents = []; // Store all students for filtering

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);

    // Load active students WITH class and arm names using JOIN
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT 
        s.*,
        c.name as className,
        a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.isActive = 1
      ORDER BY s.surname ASC, s.firstName ASC
    ''');
    
    _allStudents = rows;
    _students = rows;

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _search(String keyword) async {
    setState(() => _loading = true);

    // Filter in-memory
    if (keyword.trim().isEmpty) {
      _students = _allStudents;
    } else {
      final kw = keyword.trim().toLowerCase();
      _students = _allStudents.where((student) {
        final surname = (student['surname'] ?? '').toString().toLowerCase();
        final firstName = (student['firstName'] ?? '').toString().toLowerCase();
        final admissionNo = (student['admissionNo'] ?? '').toString().toLowerCase();
        
        return surname.contains(kw) || 
               firstName.contains(kw) || 
               admissionNo.contains(kw);
      }).toList();
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
    final cls = s['className'] ?? 'No Class';
    final arm = s['armName'] ?? 'No Arm';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Icon(Icons.payment, color: Colors.blue.shade700),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Adm: $adm"),
            Text(
              "$cls - $arm",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        isThreeLine: true,
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
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // SEARCH INPUT
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: "Search active students...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadStudents();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => _search(value),
            ),
          ),

          // INFO BANNER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Only active students can receive payments (${_students.length})",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // STUDENT LIST
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchCtrl.text.isEmpty
                                  ? "No active students found."
                                  : "No active students match your search.",
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Add students to begin recording payments",
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadStudents,
                        child: ListView.builder(
                          itemCount: _students.length,
                          itemBuilder: (_, i) => _studentTile(_students[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}