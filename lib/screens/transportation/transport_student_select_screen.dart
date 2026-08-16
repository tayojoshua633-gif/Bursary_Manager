import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';
import 'route_allocate_screen.dart';

class TransportStudentSelectScreen extends StatefulWidget {
  const TransportStudentSelectScreen({super.key});

  @override
  State<TransportStudentSelectScreen> createState() => _TransportStudentSelectScreenState();
}

class _TransportStudentSelectScreenState extends State<TransportStudentSelectScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String _term = '';
  String _session = '';
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _allStudents = [];
  Map<int, Map<String, dynamic>> _allocationByStudentId = {};
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
        _currentUser = {'id': userId, 'userType': userType, 'username': username};
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

    _term = await _db.getActiveTerm();
    _session = (await _db.getActiveSession())?['sessionName'] ?? '';

    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT s.*, c.name as className, a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.isActive = 1
      ORDER BY s.surname ASC, s.firstName ASC
    ''');

    final allocations = await _db.getRouteAllocationsWithDetails(_term, _session);
    final allocationMap = <int, Map<String, dynamic>>{
      for (final a in allocations) a['studentId'] as int: a,
    };

    _allStudents = rows;
    _students = rows;
    _allocationByStudentId = allocationMap;
    _siblingPhones = computeSiblingPhones(rows);

    if (mounted) setState(() => _loading = false);
  }

  void _search(String keyword) {
    setState(() {
      if (keyword.trim().isEmpty) {
        _students = _allStudents;
      } else {
        final kw = keyword.trim().toLowerCase();
        _students = _allStudents.where((student) {
          final surname = (student['surname'] ?? '').toString().toLowerCase();
          final firstName = (student['firstName'] ?? '').toString().toLowerCase();
          final admissionNo = (student['admissionNo'] ?? '').toString().toLowerCase();
          return surname.contains(kw) || firstName.contains(kw) || admissionNo.contains(kw);
        }).toList();
      }
    });
  }

  void _openAllocate(Map<String, dynamic> student) async {
    final id = student['id'] as int;
    final name = "${student['surname']} ${student['firstName']}".trim();

    final result = await NavigationHelper.pushWithSidebar(
      context,
      page: RouteAllocateScreen(
        studentId: id,
        studentName: name,
        term: _term,
        session: _session,
      ),
      currentUser: _currentUser ?? {},
      pageId: 'transportation/allocate',
    );

    if (result == true) _loadStudents();
  }

  Widget _studentTile(Map<String, dynamic> s, DisplaySettings ds) {
    final name = "${s['surname']} ${s['firstName']}".trim();
    final adm = s['admissionNo'] ?? '';
    final cls = s['className'] ?? 'No Class';
    final arm = s['armName'] ?? 'No Arm';
    final allocation = _allocationByStudentId[s['id']];

    return Card(
      margin: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.75, vertical: ds.cardPadding * 0.25),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: allocation != null ? Colors.teal.shade100 : Colors.grey.shade200,
          child: Icon(
            Icons.directions_bus,
            color: allocation != null ? Colors.teal.shade700 : Colors.grey.shade500,
            size: ds.iconSize,
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(name,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: ds.bodyFontSize),
                  overflow: TextOverflow.ellipsis),
            ),
            SiblingMark(show: isSiblingPhone(s['parentPhone'] as String?, _siblingPhones)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Adm: $adm", style: TextStyle(fontSize: ds.subtitleFontSize)),
            Text("$cls - $arm", style: TextStyle(fontSize: ds.subtitleFontSize, color: Colors.grey.shade600)),
            if (allocation != null)
              Text(
                "Route: ${allocation['routeName']}",
                style: TextStyle(fontSize: ds.subtitleFontSize, color: Colors.teal.shade700, fontWeight: FontWeight.w500),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: Icon(Icons.arrow_forward_ios, size: ds.iconSize * 0.7),
        onTap: () => _openAllocate(s),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Allocate Students to Routes"),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
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
                          _search('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: ds.cardPadding, vertical: ds.cardPadding * 0.5),
            color: Colors.teal.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: ds.iconSize * 0.7, color: Colors.teal.shade700),
                SizedBox(width: ds.cardPadding * 0.5),
                Expanded(
                  child: Text(
                    "$_term, $_session — ${_allocationByStudentId.length} student(s) currently allocated",
                    style: TextStyle(fontSize: ds.subtitleFontSize, color: Colors.teal.shade900),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isEmpty ? "No active students found." : "No active students match your search.",
                          style: TextStyle(fontSize: ds.bodyFontSize, color: Colors.grey.shade600),
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
