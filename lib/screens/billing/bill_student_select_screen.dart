import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';
import 'bill_generate_screen.dart';

class BillStudentSelectScreen extends StatefulWidget {
  const BillStudentSelectScreen({super.key});

  @override
  State<BillStudentSelectScreen> createState() =>
      _BillStudentSelectScreenState();
}

class _BillStudentSelectScreenState extends State<BillStudentSelectScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _allStudents = []; // Store all students for filtering
  Map<String, dynamic>? _currentUser;
  Set<String> _siblingPhones = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadStudents();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';

    if (mounted) {
      setState(() {
        _currentUser = {
          'id': userId,
          'userType': userType,
          'username': username,
        };
      });
    }
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
    _siblingPhones = computeSiblingPhones(rows);

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

    final result = await NavigationHelper.pushWithSidebar(
      context,
      page: BillGenerateScreen(
        studentId: id,
        studentName: name,
        isSibling: isSiblingPhone(student['parentPhone'] as String?, _siblingPhones),
      ),
      currentUser: _currentUser ?? {},
      pageId: 'bills_payment/student_bills',
    );

    // If bill was saved, refresh list to reflect any updates
    if (result == true) _loadStudents();
  }

  Widget _studentTile(Map<String, dynamic> s, DisplaySettings ds) {
    final name = "${s['surname']} ${s['firstName']}".trim();
    final adm = s['admissionNo'] ?? '';
    final cls = s['className'] ?? 'No Class';
    final arm = s['armName'] ?? 'No Arm';

    return Card(
      margin: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.75, vertical: ds.cardPadding * 0.25),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: Icon(Icons.receipt_long, color: Colors.green.shade700, size: ds.iconSize),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: ds.bodyFontSize),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SiblingMark(show: isSiblingPhone(s['parentPhone'] as String?, _siblingPhones)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Adm: $adm", style: TextStyle(fontSize: ds.subtitleFontSize)),
            Text(
              "$cls - $arm",
              style: TextStyle(fontSize: ds.subtitleFontSize, color: Colors.grey.shade600),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Icon(Icons.arrow_forward_ios, size: ds.iconSize * 0.7),
        onTap: () => _openBilling(s),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
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
            padding: EdgeInsets.all(ds.cardPadding * 0.75),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(fontSize: ds.bodyFontSize),
              decoration: InputDecoration(
                labelText: "Search active students...",
                prefixIcon: Icon(Icons.search, size: ds.iconSize),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: ds.iconSize),
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
            padding: EdgeInsets.symmetric(horizontal: ds.cardPadding, vertical: ds.cardPadding * 0.5),
            color: Colors.green.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: ds.iconSize * 0.7, color: Colors.green.shade700),
                SizedBox(width: ds.cardPadding * 0.5),
                Expanded(
                  child: Text(
                    "Only active students can be billed (${_students.length})",
                    style: TextStyle(
                      fontSize: ds.subtitleFontSize,
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
                                size: ds.iconSize * 2.5, color: Colors.grey.shade400),
                            SizedBox(height: ds.cardPadding),
                            Text(
                              _searchCtrl.text.isEmpty
                                  ? "No active students found."
                                  : "No active students match your search.",
                              style: TextStyle(
                                  fontSize: ds.bodyFontSize, color: Colors.grey.shade600),
                            ),
                            SizedBox(height: ds.cardPadding * 0.5),
                            Text(
                              "Add students to begin billing",
                              style: TextStyle(
                                  fontSize: ds.subtitleFontSize, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadStudents,
                        child: ListView.builder(
                          itemCount: _students.length,
                          itemBuilder: (_, i) => _studentTile(_students[i], ds),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}