import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bursary_manager/data/database_helper_wrapper.dart';
import '../../db/database_helper.dart';
import '../../models/student.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';
import '../../widgets/student_quick_actions_panel.dart';
import '../../widgets/term_session_filter.dart';
import 'student_details_screen.dart';

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
  Map<String, dynamic> _currentUser = {};

  // Term filter — null means "All". Defaults to the active term/session.
  List<String> _sessions = [];
  String? _filterSession;
  String? _filterTerm;
  bool _termFilterInitialised = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _load();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';

    if (!mounted) return;
    setState(() {
      _currentUser = {
        'id': userId,
        'userType': userType,
        'username': username,
      };
    });
  }

  void _openStudentDetails(Map<String, dynamic> studentData) {
    final student = Student.fromMap(studentData);
    NavigationHelper.pushWithSidebar(
      context,
      page: StudentDetailsScreen(student: student),
      currentUser: _currentUser,
      pageId: 'student_management/students',
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    if (!_termFilterInitialised) {
      _filterTerm = await db.getActiveTerm();
      _filterSession = (await db.getActiveSession())?['sessionName'] as String?;
      _sessions = TermSessionFilter.sessionNames(await db.getAllSessions(), _filterSession);
      _termFilterInitialised = true;
    }
    _allStudents = await db.getInactiveStudents();
    _siblingPhones = computeSiblingPhones(await db.getActiveStudents());
    _applyFilter();
    setState(() => loading = false);
  }

  void _applyFilter() {
    final keyword = _searchCtrl.text.trim().toLowerCase();

    setState(() {
      final inTerm = _allStudents.where((s) =>
          (_filterSession == null || s['leftSession'] == _filterSession) &&
          (_filterTerm == null || s['leftTerm'] == _filterTerm));

      if (keyword.isEmpty) {
        students = inTerm.toList();
        return;
      }

      students = inTerm.where((s) {
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

  String _periodLabel() {
    if (_filterSession == null && _filterTerm == null) return "all terms";
    return [_filterTerm ?? "all terms", _filterSession ?? "all sessions"].join(" ");
  }

  String _leftLabel(Map<String, dynamic> s) {
    final term = (s['leftTerm'] ?? '').toString();
    final session = (s['leftSession'] ?? '').toString();
    final period = term.isEmpty && session.isEmpty ? 'Term not recorded' : '$term $session'.trim();
    final date = DateTime.tryParse((s['leftDate'] ?? '').toString());
    if (date == null) return period;
    final d = "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
    return '$period ($d)';
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
      endDrawer: StudentQuickAccess.buildEndDrawer(
        context,
        current: StudentQuickAction.inactive,
        onReturn: _load,
      ),
      body: StudentQuickAccess.wrapBody(
        context,
        current: StudentQuickAction.inactive,
        onReturn: _load,
        body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: TermSessionFilter(
                    sessions: _sessions,
                    session: _filterSession,
                    term: _filterTerm,
                    allowAll: true,
                    onSessionChanged: (v) {
                      _filterSession = v;
                      _applyFilter();
                    },
                    onTermChanged: (v) {
                      _filterTerm = v;
                      _applyFilter();
                    },
                  ),
                ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_off, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Made inactive in ${_periodLabel()}",
                          style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        "${students.length}",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
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
                                ? "No students made inactive in ${_periodLabel()}"
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
                                onTap: () => _openStudentDetails(s),
                                title: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                                    SiblingMark(
                                      show: isSiblingPhone(s['parentPhone'] as String?, _siblingPhones),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  "${s['className']} - ${s['armName']}\n"
                                  "Left: ${_leftLabel(s)}"
                                  "${(s['leftReason'] ?? '').toString().isNotEmpty ? ' • ${s['leftReason']}' : ''}",
                                ),
                                isThreeLine: true,
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
      ),
    );
  }
}
