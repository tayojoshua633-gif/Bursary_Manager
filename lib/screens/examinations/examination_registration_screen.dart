import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/external_examination.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';

class ExaminationRegistrationScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const ExaminationRegistrationScreen({super.key, required this.currentUser});

  @override
  State<ExaminationRegistrationScreen> createState() =>
      _ExaminationRegistrationScreenState();
}

class _ExaminationRegistrationScreenState
    extends State<ExaminationRegistrationScreen> {
  final _db = DatabaseHelper();

  List<ExternalExamination> _examinations = [];
  ExternalExamination? _selectedExam;

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  int? _selectedClassId;
  int? _selectedArmId;

  final _searchCtrl = TextEditingController();

  String _activeSession = '';

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filtered = [];
  Set<int> _registeredIds = {};
  bool _loadingStudents = false;
  bool _loadingExams = true;
  Set<String> _siblingPhones = {};

  @override
  void initState() {
    super.initState();
    _loadInit();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInit() async {
    final examRows = await _db.getExternalExaminations(activeOnly: true);
    final classRows = await _db.getClasses();
    final sessionData = await _db.getActiveSession();
    final session = sessionData?['sessionName'] as String? ?? '';
    if (!mounted) return;
    setState(() {
      _examinations = examRows.map(ExternalExamination.fromMap).toList();
      _classes = classRows;
      _activeSession = session;
      _loadingExams = false;
    });
  }

  Future<void> _loadStudents() async {
    if (_selectedExam == null) return;
    setState(() => _loadingStudents = true);

    final db = await _db.database;
    String where = 'isActive = 1';
    final args = <dynamic>[];
    if (_selectedClassId != null) {
      where += ' AND s.classId = ?';
      args.add(_selectedClassId);
    }
    if (_selectedArmId != null) {
      where += ' AND s.armId = ?';
      args.add(_selectedArmId);
    }

    final rows = await db.rawQuery('''
      SELECT s.id, s.surname, s.firstName, s.otherName, s.admissionNo,
             s.classId, s.armId, s.parentPhone,
             c.name AS className, a.name AS armName
      FROM students s
      JOIN classes c ON c.id = s.classId
      LEFT JOIN arms a ON a.id = s.armId
      WHERE s.$where
      ORDER BY c.name ASC, a.name ASC, s.surname ASC, s.firstName ASC
    ''', args);

    final regRows = await _db.getExaminationRegistrations(
        examinationId: _selectedExam!.id, session: _activeSession);
    final regStudentIds = regRows
        .where((r) => r['studentId'] != null)
        .map((r) => r['studentId'] as int)
        .toSet();

    final siblingPhones = computeSiblingPhones(await _db.getActiveStudents());

    if (!mounted) return;
    setState(() {
      _students = rows;
      _registeredIds = regStudentIds;
      _siblingPhones = siblingPhones;
      _loadingStudents = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _students.where((s) {
        if (q.isEmpty) return true;
        final name =
            '${s['surname']} ${s['firstName']} ${s['otherName'] ?? ''}'
                .toLowerCase();
        final admNo = (s['admissionNo'] as String? ?? '').toLowerCase();
        final cls = (s['className'] as String? ?? '').toLowerCase();
        final arm = (s['armName'] as String? ?? '').toLowerCase();
        return name.contains(q) ||
            admNo.contains(q) ||
            cls.contains(q) ||
            arm.contains(q);
      }).toList();
    });
  }

  Future<void> _onClassChanged(int? classId) async {
    setState(() {
      _selectedClassId = classId;
      _selectedArmId = null;
      _arms = [];
    });
    if (classId != null) {
      final armRows = await _db.getArmsByClass(classId);
      if (!mounted) return;
      setState(() => _arms = armRows);
    }
    _loadStudents();
  }

  Future<void> _toggleRegistration(Map<String, dynamic> student) async {
    if (_selectedExam == null) return;
    final studentId = student['id'] as int;
    final examId = _selectedExam!.id!;

    if (_registeredIds.contains(studentId)) {
      await _db.deleteExaminationRegistrationByKeys(studentId, examId, _activeSession);
      setState(() => _registeredIds.remove(studentId));
    } else {
      // Register
      final now = DateTime.now().toIso8601String();
      try {
        await _db.insertExaminationRegistration({
          'examinationId': examId,
          'studentId': studentId,
          'registrationDate': now.substring(0, 10),
          'createdAt': now,
          'session': _activeSession,
          'snapshotName': _studentName(student),
          'snapshotAdmNo': student['admissionNo'] ?? '',
          'snapshotGender': student['gender'] ?? '',
          'snapshotClass': student['className'] ?? '',
          'snapshotArm': student['armName'] ?? '',
        });
        setState(() => _registeredIds.add(studentId));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Student already registered for this exam.'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    }
  }

  Future<void> _registerAll() async {
    if (_selectedExam == null || _filtered.isEmpty) return;
    final unregistered =
        _filtered.where((s) => !_registeredIds.contains(s['id'] as int)).toList();
    if (unregistered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All shown students are already registered.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Register All'),
        content: Text(
            'Register ${unregistered.length} student(s) for ${_selectedExam!.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Register All')),
        ],
      ),
    );
    if (confirmed != true) return;

    final now = DateTime.now().toIso8601String();
    for (final s in unregistered) {
      try {
        await _db.insertExaminationRegistration({
          'examinationId': _selectedExam!.id!,
          'studentId': s['id'] as int,
          'registrationDate': now.substring(0, 10),
          'createdAt': now,
          'session': _activeSession,
          'snapshotName': _studentName(s),
          'snapshotAdmNo': s['admissionNo'] ?? '',
          'snapshotGender': s['gender'] ?? '',
          'snapshotClass': s['className'] ?? '',
          'snapshotArm': s['armName'] ?? '',
        });
        _registeredIds.add(s['id'] as int);
      } catch (_) {}
    }
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${unregistered.length} student(s) registered.'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _unregisterAll() async {
    if (_selectedExam == null || _filtered.isEmpty) return;
    final toUnregister =
        _filtered.where((s) => _registeredIds.contains(s['id'] as int)).toList();
    if (toUnregister.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No registered students in the current view.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unregister All'),
        content: Text(
            'Unregister ${toUnregister.length} student(s) from ${_selectedExam!.name}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unregister All',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final s in toUnregister) {
      await _db.deleteExaminationRegistrationByKeys(
          s['id'] as int, _selectedExam!.id!, _activeSession);
      _registeredIds.remove(s['id'] as int);
    }
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${toUnregister.length} student(s) unregistered.'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  String _studentName(Map<String, dynamic> s) {
    return '${s['surname']} ${s['firstName']}'
        '${(s['otherName'] as String?)?.isNotEmpty == true ? ' ${s['otherName']}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Registration'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (_selectedExam != null && _filtered.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) {
                if (v == 'register_all') _registerAll();
                if (v == 'unregister_all') _unregisterAll();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'register_all',
                  child: ListTile(
                    leading: Icon(Icons.done_all, color: Colors.teal),
                    title: Text('Register All'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'unregister_all',
                  child: ListTile(
                    leading: Icon(Icons.remove_done, color: Colors.red),
                    title: Text('Unregister All'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _loadingExams
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Exam selector
                Container(
                  color: Colors.teal.withValues(alpha: 0.06),
                  padding: EdgeInsets.all(ds.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<ExternalExamination>(
                        initialValue: _selectedExam,
                        decoration: const InputDecoration(
                          labelText: 'Select Examination *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        items: _examinations
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child:
                                      Text('${e.name} (${e.code})'),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() => _selectedExam = v);
                          _loadStudents();
                        },
                      ),
                      SizedBox(height: ds.cardPadding * 0.75),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              initialValue: _selectedClassId,
                              decoration: const InputDecoration(
                                labelText: 'Class',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('All Classes')),
                                ..._classes.map((c) => DropdownMenuItem(
                                      value: c['id'] as int,
                                      child: Text(c['name'] as String),
                                    )),
                              ],
                              onChanged: _onClassChanged,
                            ),
                          ),
                          SizedBox(width: ds.cardPadding * 0.5),
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              initialValue: _selectedArmId,
                              decoration: const InputDecoration(
                                labelText: 'Arm',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('All Arms')),
                                ..._arms.map((a) => DropdownMenuItem(
                                      value: a['id'] as int,
                                      child: Text(a['name'] as String),
                                    )),
                              ],
                              onChanged: (v) {
                                setState(() => _selectedArmId = v);
                                _loadStudents();
                              },
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: ds.cardPadding * 0.75),
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search by name, admission no, class…',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                  },
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),

                // Stats bar
                if (_selectedExam != null)
                  Container(
                    color: Colors.teal.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.people, size: 16, color: Colors.teal.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_filtered.length} shown  •  ${_registeredIds.length} registered',
                            style: TextStyle(
                                fontSize: ds.subtitleFontSize,
                                color: Colors.teal.shade700,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        if (_activeSession.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade700,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _activeSession,
                              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),

                // Student list
                Expanded(
                  child: _selectedExam == null
                      ? Center(
                          child: Text(
                            'Select an examination to begin',
                            style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: ds.titleFontSize * 0.85),
                          ),
                        )
                      : _loadingStudents
                          ? const Center(child: CircularProgressIndicator())
                          : _filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    'No students found',
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: ds.titleFontSize * 0.85),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _filtered.length,
                                  itemBuilder: (_, i) {
                                    final s = _filtered[i];
                                    final sid = s['id'] as int;
                                    final isReg = _registeredIds.contains(sid);
                                    final classArm =
                                        '${s['className'] ?? ''}${(s['armName'] as String?)?.isNotEmpty == true ? ' ${s['armName']}' : ''}';
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: isReg
                                            ? Colors.teal.withValues(alpha: 0.15)
                                            : Colors.grey.withValues(alpha: 0.15),
                                        child: Icon(
                                          isReg
                                              ? Icons.check_circle
                                              : Icons.person_outline,
                                          color: isReg
                                              ? Colors.teal
                                              : Colors.grey,
                                          size: 22,
                                        ),
                                      ),
                                      title: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _studentName(s),
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: ds.titleFontSize * 0.82),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          SiblingMark(
                                            show: isSiblingPhone(s['parentPhone'] as String?, _siblingPhones),
                                          ),
                                        ],
                                      ),
                                      subtitle: Text(
                                        '${s['admissionNo'] ?? ''}  •  $classArm',
                                        style: TextStyle(
                                            fontSize: ds.subtitleFontSize,
                                            color: Colors.grey[600]),
                                      ),
                                      trailing: Switch(
                                        value: isReg,
                                        activeThumbColor: Colors.teal,
                                        onChanged: (_) =>
                                            _toggleRegistration(s),
                                      ),
                                      onTap: () => _toggleRegistration(s),
                                    );
                                  },
                                ),
                ),
              ],
            ),
    );
  }
}
