import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';

class SetBillPriorityScreen extends StatefulWidget {
  const SetBillPriorityScreen({super.key});

  @override
  State<SetBillPriorityScreen> createState() => _SetBillPriorityScreenState();
}

class _SetBillPriorityScreenState extends State<SetBillPriorityScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: 'N');

  String? _term;
  String? _session;

  // Scope is dynamic: 'class' when no arm selected, 'class_arm' when arm selected
  String get _scope => _selectedArmId != null ? 'class_arm' : 'class';

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  List<Map<String, dynamic>> _feeItems = [];

  int? _selectedClassId;
  int? _selectedArmId;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    _term = await _db.getActiveTerm();
    final activeSession = await _db.getActiveSession();
    _session = activeSession?['sessionName'] ?? '';

    _classes = await _db.getClasses();

    if (mounted) setState(() {});
  }

  Future<void> _loadFeeItems() async {
    setState(() => _loading = true);

    if (_term == null || _session == null) {
      setState(() {
        _feeItems = [];
        _loading = false;
      });
      return;
    }

    if (_selectedClassId == null) {
      setState(() {
        _feeItems = [];
        _loading = false;
      });
      return;
    }

    List<Map<String, dynamic>> items = [];

    // Load all fee items first to look up names
    final allFeeItems =
        await _db.getFeeItems(term: _term, session: _session);
    final feeItemMap = <int, String>{};
    for (final fi in allFeeItems) {
      feeItemMap[fi['id'] as int] = fi['name'] as String? ?? '';
    }

    final classFees = await _db.getClassFees(
      _selectedClassId!,
      _term!,
      _session!,
      armId: _selectedArmId,
    );

    items = classFees.map((cf) {
      final feeItemId = cf['feeItemId'] as int;
      return {
        'feeItemId': feeItemId,
        'name': feeItemMap[feeItemId] ?? 'Unknown Fee',
        'amount': (cf['amount'] ?? 0).toDouble(),
      };
    }).toList();

    // Check if any student-specific extras exist for this class/arm.
    // If so, add ONE virtual placeholder (feeItemId = -2) so the admin
    // can position all extras as a group in the priority order.
    final extras = await _db.getExtraFeeItemsForClassArm(
      classId: _selectedClassId!,
      armId: _selectedArmId,
      term: _term!,
      session: _session!,
    );
    if (extras.isNotEmpty) {
      items.add({
        'feeItemId': -2,
        'name': 'Student-Specific Extras',
        'amount': 0.0, // varies per student
      });
    }

    // Add Previous Balance as a virtual priority item (feeItemId = -1)
    items.add({
      'feeItemId': -1,
      'name': 'Previous Balance',
      'amount': 0.0, // Actual amount varies per student
    });

    // Merge with existing priorities to preserve saved order
    final existingPriorities = await _db.getFeePriorities(
      scope: _scope,
      classId: _selectedClassId,
      armId: _selectedArmId,
      term: _term!,
      session: _session!,
    );

    if (existingPriorities.isNotEmpty) {
      // Build a map of feeItemId -> priority from saved data
      final priorityMap = <int, int>{};
      for (final p in existingPriorities) {
        priorityMap[p['feeItemId'] as int] = p['priority'] as int;
      }

      // Sort items: those with existing priorities first (by priority), then the rest
      items.sort((a, b) {
        final pa = priorityMap[a['feeItemId'] as int];
        final pb = priorityMap[b['feeItemId'] as int];

        if (pa != null && pb != null) return pa.compareTo(pb);
        if (pa != null) return -1;
        if (pb != null) return 1;
        return 0;
      });
    }

    if (mounted) {
      setState(() {
        _feeItems = items;
        _loading = false;
      });
    }
  }

  Future<void> _loadArms() async {
    if (_selectedClassId == null) {
      setState(() => _arms = []);
      return;
    }
    _arms = await _db.getArmsByClass(_selectedClassId!);
    if (mounted) {
      setState(() {});
      // If class has no arms, load class-level priorities immediately
      if (_arms.isEmpty) _loadFeeItems();
    }
  }

  void _onClassChanged(int? classId) {
    setState(() {
      _selectedClassId = classId;
      _selectedArmId = null;
      _arms = [];
      _feeItems = [];
    });

    if (classId != null) {
      _loadArms();
    }
  }

  void _onArmChanged(int? armId) {
    setState(() {
      _selectedArmId = armId;
    });
    _loadFeeItems();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _feeItems.removeAt(oldIndex);
      _feeItems.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    if (_term == null || _session == null) return;

    final priorities = <Map<String, dynamic>>[];
    for (int i = 0; i < _feeItems.length; i++) {
      priorities.add({
        'feeItemId': _feeItems[i]['feeItemId'],
        'priority': i + 1,
      });
    }

    await _db.saveFeePriorities(
      scope: _scope,
      classId: _selectedClassId,
      armId: _selectedArmId,
      term: _term!,
      session: _session!,
      priorities: priorities,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Priorities saved successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Bill Priority'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Info card
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Set the order in which payments are applied to fee '
                      'items. Priority 1 gets paid first.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Class dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedClassId,
              items: _classes.map((c) {
                return DropdownMenuItem<int>(
                  value: c['id'] as int,
                  child: Text(c['name'] as String? ?? ''),
                );
              }).toList(),
              onChanged: _onClassChanged,
            ),
          ),

          // Arm dropdown
          if (_arms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Arm',
                  border: OutlineInputBorder(),
                ),
                initialValue: _selectedArmId,
                items: _arms.map((a) {
                  return DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(a['name'] as String? ?? ''),
                  );
                }).toList(),
                onChanged: _onArmChanged,
              ),
            ),

          const SizedBox(height: 8),

          // Fee items list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _feeItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.list_alt,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _selectedClassId == null
                                  ? 'Select a class to view fee items'
                                  : _arms.isNotEmpty && _selectedArmId == null
                                      ? 'Select an arm to view fee items'
                                      : 'No fee items found for this class',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _feeItems.length,
                        onReorder: _onReorder,
                        itemBuilder: (context, index) {
                          final item = _feeItems[index];
                          final feeItemId = item['feeItemId'] as int;
                          final name = item['name'] as String;
                          final amount = (item['amount'] as num).toDouble();

                          final bool isPreviousBalance = feeItemId == -1;
                          final bool isStudentExtras = feeItemId == -2;

                          return ListTile(
                            key: ValueKey(feeItemId),
                            leading: CircleAvatar(
                              backgroundColor: isPreviousBalance
                                  ? Colors.deepOrange
                                  : isStudentExtras
                                      ? Colors.purple
                                      : Colors.blue,
                              foregroundColor: Colors.white,
                              child: Text('${index + 1}'),
                            ),
                            title: Text(name),
                            subtitle: Text(
                              isPreviousBalance || isStudentExtras
                                  ? 'Varies per student'
                                  : _currencyFormat.format(amount),
                            ),
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                          );
                        },
                      ),
          ),

          // Save button at bottom
          if (_feeItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text(
                    'Save Priorities',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
