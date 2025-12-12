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
    final cls = s['className'] ?? 'No Class';
    final arm = s['armName'] ?? 'No Arm';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: Icon(Icons.receipt_long, color: Colors.green.shade700),
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
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _openBilling(s),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Student for Billing"),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // SEARCH BAR
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
            color: Colors.green.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Only active students can be billed (${_students.length})",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade900,
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
                              "Add students to begin billing",
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