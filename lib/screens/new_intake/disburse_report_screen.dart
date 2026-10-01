// lib/screens/new_intake/disburse_report_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../widgets/quick_access_sidebar.dart';

class DisburseReportScreen extends StatefulWidget {
  const DisburseReportScreen({super.key});

  @override
  State<DisburseReportScreen> createState() => _DisburseReportScreenState();
}

class _DisburseReportScreenState extends State<DisburseReportScreen> {
  static const List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];

  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  List<Map<String, dynamic>> _students = []; // grouped report rows

  String? _activeTerm;
  String? _activeSession;
  int? _selectedClassId; // null = all classes
  int? _selectedArmId; // null = all arms

  String _search = '';

  bool _loading = true;
  bool _loadingArms = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _activeTerm = await _db.getActiveTerm();
    _activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";
    _sessions = await _db.getAllSessions();
    _classes = await _db.getClasses();

    await _loadReport();

    if (mounted) setState(() => _loading = false);
  }

  void _onTermChanged(String? term) {
    if (term == null) return;
    setState(() => _activeTerm = term);
    _refresh();
  }

  void _onSessionChanged(String? session) {
    if (session == null) return;
    setState(() => _activeSession = session);
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _loadReport();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onClassChanged(int? classId) async {
    setState(() {
      _selectedClassId = classId;
      _selectedArmId = null;
      _arms = [];
    });

    if (classId == null) {
      await _loadReport();
      return;
    }

    setState(() => _loadingArms = true);
    final database = await _db.database;
    final armsData = await database.query(
      'arms',
      where: 'classId = ?',
      whereArgs: [classId],
      orderBy: 'name',
    );

    setState(() {
      _arms = armsData;
      _loadingArms = false;
    });

    await _loadReport();
  }

  Future<void> _onArmChanged(int? armId) async {
    setState(() => _selectedArmId = armId);
    await _loadReport();
  }

  Future<void> _loadReport() async {
    final database = await _db.database;

    final where = StringBuffer(
      "sid.status = 'given' AND sid.term = ? AND sid.session = ?",
    );
    final args = <dynamic>[_activeTerm ?? '', _activeSession ?? ''];

    if (_selectedClassId != null) {
      where.write(' AND s.classId = ?');
      args.add(_selectedClassId);
    }
    if (_selectedArmId != null) {
      where.write(' AND s.armId = ?');
      args.add(_selectedArmId);
    }

    final rows = await database.rawQuery('''
      SELECT sid.markedAt, sid.markedBy,
             s.id AS studentId, s.surname, s.firstName, s.otherName, s.admissionNo,
             c.name AS className, a.name AS armName,
             sfi.name AS itemName, parent.name AS categoryName
      FROM special_item_disbursements sid
      JOIN students s ON s.id = sid.studentId
      LEFT JOIN classes c ON c.id = s.classId
      LEFT JOIN arms a ON a.id = s.armId
      JOIN special_fee_items sfi ON sfi.id = sid.specialFeeItemId
      LEFT JOIN special_fee_items parent ON parent.id = sfi.parentId
      WHERE $where
      ORDER BY s.surname, s.firstName, sfi.name
    ''', args);

    final grouped = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      final studentId = r['studentId'] as int;
      grouped.putIfAbsent(
        studentId,
        () => {
          'studentId': studentId,
          'name': '${r['surname']} ${r['firstName']} ${r['otherName'] ?? ''}'
              .trim(),
          'admissionNo': r['admissionNo'],
          'className': r['className'],
          'armName': r['armName'],
          'items': <Map<String, dynamic>>[],
        },
      );
      (grouped[studentId]!['items'] as List<Map<String, dynamic>>).add({
        'itemName': r['itemName'],
        'categoryName': r['categoryName'],
        'markedAt': r['markedAt'],
      });
    }

    if (!mounted) return;
    setState(() => _students = grouped.values.toList());
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_search.trim().isEmpty) return _students;
    final q = _search.trim().toLowerCase();
    return _students.where((s) {
      final name = (s['name'] as String).toLowerCase();
      final admNo = (s['admissionNo']?.toString() ?? '').toLowerCase();
      return name.contains(q) || admNo.contains(q);
    }).toList();
  }

  bool get _hasFilter => _selectedClassId != null || _search.trim().isNotEmpty;

  String _formatDate(dynamic markedAt) {
    if (markedAt == null) return '';
    try {
      return DateFormat(
        'd MMM yyyy',
      ).format(DateTime.parse(markedAt as String));
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => QuickAccessScaffold(
        group: QuickAccessGroup.itemDisbursement,
        currentId: 'disburse_report',
        child: _buildScreenContent(context),
      );

  Widget _buildScreenContent(BuildContext context) {
    final filtered = _filteredStudents;
    final totalItemsGiven = _students.fold<int>(
      0,
      (sum, s) => sum + (s['items'] as List).length,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Disburse Report'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Filters
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              border: Border(bottom: BorderSide(color: Colors.teal.shade100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _activeSession,
                        decoration: InputDecoration(
                          labelText: 'Session',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(
                            Icons.calendar_today,
                            size: 18,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: _sessions
                            .map((s) => s['sessionName'] as String)
                            .toSet()
                            .map(
                              (name) => DropdownMenuItem(
                                value: name,
                                child: Text(name),
                              ),
                            )
                            .toList(),
                        onChanged: _onSessionChanged,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _activeTerm,
                        decoration: InputDecoration(
                          labelText: 'Term',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.event, size: 18),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: _terms
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                        onChanged: _onTermChanged,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _selectedClassId,
                        decoration: InputDecoration(
                          labelText: 'Class',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.school, size: 18),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('All Classes'),
                          ),
                          ..._classes.map(
                            (c) => DropdownMenuItem<int?>(
                              value: c['id'] as int,
                              child: Text(c['name'] as String),
                            ),
                          ),
                        ],
                        onChanged: _onClassChanged,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _loadingArms
                          ? const Center(child: CircularProgressIndicator())
                          : DropdownButtonFormField<int?>(
                              initialValue: _selectedArmId,
                              decoration: InputDecoration(
                                labelText: 'Arm',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.class_, size: 18),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('All Arms'),
                                ),
                                ..._arms.map(
                                  (a) => DropdownMenuItem<int?>(
                                    value: a['id'] as int,
                                    child: Text(a['name'] as String),
                                  ),
                                ),
                              ],
                              onChanged: _selectedClassId == null
                                  ? null
                                  : _onArmChanged,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Search student',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ],
            ),
          ),

          // Summary
          if (!_loading && _hasFilter)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.green.shade50,
              child: Text(
                '${_students.length} student(s) • $totalItemsGiven item(s) given',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ),

          // Results
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_hasFilter
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.filter_alt_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Select a class or search for a student to view the report',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No students have been given items yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final s = filtered[index];
                      final items = s['items'] as List<Map<String, dynamic>>;
                      final classArm = [s['className'], s['armName']]
                          .where((v) => v != null && (v as String).isNotEmpty)
                          .join(' - ');

                      return Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      s['name'] as String,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    s['admissionNo']?.toString() ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              if (classArm.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  classArm,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: items.map((it) {
                                  final label =
                                      (it['categoryName'] != null &&
                                          (it['categoryName'] as String)
                                              .isNotEmpty)
                                      ? '${it['categoryName']} • ${it['itemName']}'
                                      : it['itemName'] as String;
                                  final date = _formatDate(it['markedAt']);
                                  return Chip(
                                    avatar: const Icon(
                                      Icons.check_circle,
                                      size: 16,
                                      color: Colors.green,
                                    ),
                                    label: Text(
                                      date.isNotEmpty
                                          ? '$label ($date)'
                                          : label,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    backgroundColor: Colors.green.shade50,
                                  );
                                }).toList(),
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
