// lib/screens/new_intake/disburse_items_screen.dart
import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/write_guard.dart';
import '../../widgets/quick_access_sidebar.dart';

class DisburseItemsScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const DisburseItemsScreen({super.key, required this.currentUser});

  @override
  State<DisburseItemsScreen> createState() => _DisburseItemsScreenState();
}

class _DisburseItemsScreenState extends State<DisburseItemsScreen> {
  static const List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];

  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _arms = [];
  List<Map<String, dynamic>> _specialItems = []; // {id, name, amount, categoryName}
  List<Map<String, dynamic>> _students = []; // {id, surname, firstName, otherName, admissionNo}
  Map<int, String> _statusByStudentId = {};

  String? _activeTerm;
  String? _activeSession;
  int? _selectedClassId;
  int? _selectedArmId;
  String? _selectedClassName;
  String? _selectedArmName;
  int? _selectedItemId;

  String _search = '';

  bool _loading = true;
  bool _loadingArms = false;
  bool _loadingStudents = false;
  final Set<int> _savingStudentIds = {};

  @override
  void initState() {
    super.initState();
    WriteGuard.enforce(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _activeTerm = await _db.getActiveTerm();
    _activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";
    _sessions = await _db.getAllSessions();
    _classes = await _db.getClasses();

    if (mounted) setState(() => _loading = false);
  }

  void _onTermChanged(String? term) {
    if (term == null) return;
    setState(() => _activeTerm = term);
    if (_selectedClassId != null) _loadItemsForSelection();
  }

  void _onSessionChanged(String? session) {
    if (session == null) return;
    setState(() => _activeSession = session);
    if (_selectedClassId != null) _loadItemsForSelection();
  }

  Future<void> _onClassChanged(int? classId) async {
    if (classId == null) return;

    final selectedClass = _classes.firstWhere(
      (c) => c['id'] == classId,
      orElse: () => {'name': 'Unknown'},
    );

    setState(() {
      _selectedClassId = classId;
      _selectedClassName = selectedClass['name'] as String?;
      _selectedArmId = null;
      _selectedArmName = null;
      _arms = [];
      _specialItems = [];
      _students = [];
      _statusByStudentId = {};
      _selectedItemId = null;
      _loadingArms = true;
    });

    try {
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

      if (_arms.isEmpty || _arms.length == 1) {
        if (_arms.length == 1) {
          _selectedArmId = _arms.first['id'] as int;
          _selectedArmName = _arms.first['name'] as String?;
        }
        await _loadItemsForSelection();
      }
    } catch (e) {
      debugPrint('Error loading arms: $e');
      setState(() {
        _arms = [];
        _loadingArms = false;
      });
    }
  }

  Future<void> _onArmChanged(int? armId) async {
    if (armId == null) return;

    final selectedArm = _arms.firstWhere(
      (a) => a['id'] == armId,
      orElse: () => {'name': 'Unknown'},
    );

    setState(() {
      _selectedArmId = armId;
      _selectedArmName = selectedArm['name'] as String?;
    });
    await _loadItemsForSelection();
  }

  Future<void> _loadItemsForSelection() async {
    if (_selectedClassId == null) return;

    setState(() {
      _loading = true;
      _specialItems = [];
      _selectedItemId = null;
      _students = [];
      _statusByStudentId = {};
    });

    final database = await _db.database;
    final where = StringBuffer('sc.classId = ? AND sc.term = ? AND sc.session = ?');
    final args = <dynamic>[_selectedClassId, _activeTerm ?? '', _activeSession ?? ''];
    if (_selectedArmId != null) {
      where.write(' AND sc.armId = ?');
      args.add(_selectedArmId);
    } else {
      where.write(' AND (sc.armId IS NULL OR sc.armId = 0)');
    }

    final rows = await database.rawQuery('''
      SELECT sc.specialFeeItemId AS id, sfi.name AS name, sc.amount AS amount,
             parent.name AS categoryName
      FROM special_class_fees sc
      JOIN special_fee_items sfi ON sfi.id = sc.specialFeeItemId
      JOIN disbursement_settings ds ON ds.specialFeeItemId = sc.specialFeeItemId AND ds.classId = sc.classId
      LEFT JOIN special_fee_items parent ON parent.id = sfi.parentId
      WHERE $where
      ORDER BY COALESCE(parent.name, ''), sfi.name
    ''', args);

    final items = rows.map((r) => Map<String, dynamic>.from(r)).toList();

    setState(() {
      _specialItems = items;
      _selectedItemId = items.isNotEmpty ? items.first['id'] as int : null;
      _loading = false;
    });

    if (_selectedItemId != null) {
      await _loadStudentsAndStatus();
    }
  }

  Future<void> _selectItem(int itemId) async {
    if (_selectedItemId == itemId) return;
    setState(() {
      _selectedItemId = itemId;
      _search = '';
    });
    await _loadStudentsAndStatus();
  }

  Future<void> _loadStudentsAndStatus() async {
    if (_selectedClassId == null || _selectedItemId == null) return;

    setState(() => _loadingStudents = true);

    final database = await _db.database;
    final where = StringBuffer('isActive = 1 AND classId = ?');
    final args = <dynamic>[_selectedClassId];
    if (_selectedArmId != null) {
      where.write(' AND armId = ?');
      args.add(_selectedArmId);
    }

    final studentRows = await database.query(
      'students',
      columns: ['id', 'surname', 'firstName', 'otherName', 'admissionNo'],
      where: where.toString(),
      whereArgs: args,
      orderBy: 'surname, firstName',
    );

    final statusRows = await database.query(
      'special_item_disbursements',
      columns: ['studentId', 'status'],
      where: 'specialFeeItemId = ? AND term = ? AND session = ?',
      whereArgs: [_selectedItemId, _activeTerm ?? '', _activeSession ?? ''],
    );

    final statusMap = <int, String>{};
    for (final r in statusRows) {
      statusMap[r['studentId'] as int] = r['status'] as String;
    }

    if (!mounted) return;
    setState(() {
      _students = studentRows.map((r) => Map<String, dynamic>.from(r)).toList();
      _statusByStudentId = statusMap;
      _loadingStudents = false;
    });
  }

  bool _isGiven(int studentId) => _statusByStudentId[studentId] == 'given';

  Future<void> _setStatus(int studentId, String status) async {
    final database = await _db.database;
    final now = DateTime.now().toIso8601String();

    final existing = await database.query(
      'special_item_disbursements',
      where: 'studentId = ? AND specialFeeItemId = ? AND term = ? AND session = ?',
      whereArgs: [studentId, _selectedItemId, _activeTerm ?? '', _activeSession ?? ''],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await database.update(
        'special_item_disbursements',
        {
          'status': status,
          'markedBy': widget.currentUser['username'],
          'markedAt': now,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await database.insert('special_item_disbursements', {
        'studentId': studentId,
        'specialFeeItemId': _selectedItemId,
        'term': _activeTerm ?? '',
        'session': _activeSession ?? '',
        'status': status,
        'markedBy': widget.currentUser['username'],
        'markedAt': now,
      });
    }
  }

  Future<void> _confirmAndToggle(int studentId, String studentName) async {
    if (_selectedItemId == null) return;
    final willBeGiven = !_isGiven(studentId);
    final label = willBeGiven ? 'Given' : 'Not Given';
    final item = _specialItems.firstWhere(
      (i) => i['id'] == _selectedItemId,
      orElse: () => {},
    );
    final itemName = item['name'] as String? ?? 'this item';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark as $label?'),
        content: Text('Mark $studentName as "$label" for $itemName?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: willBeGiven ? Colors.green : Colors.grey.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _toggleStatus(studentId);
  }

  Future<void> _toggleStatus(int studentId) async {
    if (_selectedItemId == null) return;
    final previous = _statusByStudentId[studentId];
    final newStatus = _isGiven(studentId) ? 'not_given' : 'given';

    setState(() {
      _savingStudentIds.add(studentId);
      _statusByStudentId[studentId] = newStatus;
    });

    try {
      await _setStatus(studentId, newStatus);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (previous == null) {
          _statusByStudentId.remove(studentId);
        } else {
          _statusByStudentId[studentId] = previous;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _savingStudentIds.remove(studentId));
    }
  }

  Future<void> _markAll(String status) async {
    if (_students.isEmpty) return;
    final label = status == 'given' ? 'Given' : 'Not Given';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark All as $label?'),
        content: Text(
          'This will mark all ${_students.length} student(s) in ${_classLabel()} as "$label" '
          'for the selected item.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loadingStudents = true);
    for (final s in _students) {
      await _setStatus(s['id'] as int, status);
    }
    await _loadStudentsAndStatus();
  }

  String _classLabel() =>
      '${_selectedClassName ?? ''}${_selectedArmName != null ? ' - $_selectedArmName' : ''}';

  String _studentName(Map<String, dynamic> s) =>
      '${s['surname']} ${s['firstName']} ${s['otherName'] ?? ''}'.trim();

  List<Map<String, dynamic>> get _filteredStudents {
    if (_search.trim().isEmpty) return _students;
    final q = _search.trim().toLowerCase();
    return _students.where((s) {
      final name = _studentName(s).toLowerCase();
      final admNo = (s['admissionNo']?.toString() ?? '').toLowerCase();
      return name.contains(q) || admNo.contains(q);
    }).toList();
  }

  String _itemDisplayName(Map<String, dynamic> item) {
    final categoryName = item['categoryName'] as String?;
    final name = item['name'] as String? ?? 'Unknown';
    return categoryName != null && categoryName.isNotEmpty ? '$categoryName • $name' : name;
  }

  @override
  Widget build(BuildContext context) => QuickAccessScaffold(
        group: QuickAccessGroup.itemDisbursement,
        currentId: 'disburse_items',
        child: _buildScreenContent(context),
      );

  Widget _buildScreenContent(BuildContext context) {
    final filtered = _filteredStudents;
    final givenCount = _students.where((s) => _isGiven(s['id'] as int)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Disburse Items'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: _loading && _classes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Selection area
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border(bottom: BorderSide(color: Colors.orange.shade200)),
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
                                prefixIcon: const Icon(Icons.calendar_today, size: 18),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: _sessions
                                  .map((s) => s['sessionName'] as String)
                                  .toSet()
                                  .map((name) => DropdownMenuItem(value: name, child: Text(name)))
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
                                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                  .toList(),
                              onChanged: _onTermChanged,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<int>(
                        initialValue: _selectedClassId,
                        decoration: InputDecoration(
                          labelText: 'Select Class',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.school),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: _classes
                            .map((c) => DropdownMenuItem<int>(
                                  value: c['id'] as int,
                                  child: Text(c['name'] as String),
                                ))
                            .toList(),
                        onChanged: _onClassChanged,
                      ),

                      if (_selectedClassId != null && _arms.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _loadingArms
                            ? const Center(child: CircularProgressIndicator())
                            : DropdownButtonFormField<int>(
                                initialValue: _selectedArmId,
                                decoration: InputDecoration(
                                  labelText: 'Select Arm',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.class_),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                items: _arms
                                    .map((a) => DropdownMenuItem<int>(
                                          value: a['id'] as int,
                                          child: Text(a['name'] as String),
                                        ))
                                    .toList(),
                                onChanged: _onArmChanged,
                              ),
                      ],
                    ],
                  ),
                ),

                // Item chooser
                if (_specialItems.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _specialItems.map((item) {
                        final id = item['id'] as int;
                        final selected = _selectedItemId == id;
                        return ChoiceChip(
                          label: Text(_itemDisplayName(item)),
                          selected: selected,
                          selectedColor: Colors.deepOrange.shade100,
                          onSelected: (_) => _selectItem(id),
                        );
                      }).toList(),
                    ),
                  ),

                // Summary + actions
                if (_selectedItemId != null && !_loadingStudents && _students.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: Colors.green.shade50,
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, color: Colors.green.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$givenCount of ${_students.length} given',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _markAll('given'),
                          child: const Text('Mark All Given'),
                        ),
                        TextButton(
                          onPressed: () => _markAll('not_given'),
                          child: const Text('Mark All Not Given'),
                        ),
                      ],
                    ),
                  ),

                // Search
                if (_selectedItemId != null && _students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Search student',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),

                // Content
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _selectedClassId == null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.school, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Select a class to track item disbursement',
                                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            )
                          : _specialItems.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No items are set up for disbursement in this class',
                                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Assign the item to this class in New Intake Bills, then enable it '
                                          'in Disburse Settings',
                                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : _loadingStudents
                                  ? const Center(child: CircularProgressIndicator())
                                  : _students.isEmpty
                                      ? Center(
                                          child: Text(
                                            'No active students in ${_classLabel()}',
                                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                          ),
                                        )
                                      : ListView.separated(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          itemCount: filtered.length,
                                          separatorBuilder: (_, _) => const Divider(height: 1),
                                          itemBuilder: (context, index) {
                                            final s = filtered[index];
                                            final studentId = s['id'] as int;
                                            final given = _isGiven(studentId);
                                            final saving = _savingStudentIds.contains(studentId);
                                            final studentName = _studentName(s);

                                            return ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor: given
                                                    ? Colors.green.shade100
                                                    : Colors.grey.shade200,
                                                child: Icon(
                                                  given ? Icons.check : Icons.inventory_2_outlined,
                                                  color: given ? Colors.green.shade700 : Colors.grey.shade500,
                                                  size: 18,
                                                ),
                                              ),
                                              title: Text(studentName),
                                              subtitle: Text(s['admissionNo']?.toString() ?? ''),
                                              trailing: saving
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  : SizedBox(
                                                      width: 108,
                                                      child: OutlinedButton(
                                                        onPressed: () => _confirmAndToggle(studentId, studentName),
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor:
                                                              given ? Colors.green.shade700 : Colors.grey.shade700,
                                                          backgroundColor:
                                                              given ? Colors.green.shade50 : Colors.white,
                                                          side: BorderSide(
                                                            color: given ? Colors.green : Colors.grey.shade400,
                                                          ),
                                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                                        ),
                                                        child: Text(
                                                          given ? 'Given' : 'Not Given',
                                                          style: const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                              onTap: saving ? null : () => _confirmAndToggle(studentId, studentName),
                                            );
                                          },
                                        ),
                ),
              ],
            ),
    );
  }
}
