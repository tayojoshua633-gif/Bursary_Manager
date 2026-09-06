import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import '../../navigation/sidebar_scaffold.dart';
import 'fee_class_assignment_screen.dart';

class FeeItemListScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const FeeItemListScreen({super.key, required this.currentUser});

  @override
  State<FeeItemListScreen> createState() => _FeeItemListScreenState();
}

class _FeeItemListScreenState extends State<FeeItemListScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _nameCtrl = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  String? _term;
  String? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final activeTerm = await _db.getActiveTerm();
    final activeSession =
        (await _db.getActiveSession())?['sessionName'] ?? "";

    _term = activeTerm;
    _session = activeSession;

    _items = await _db.getFeeItems(
      term: activeTerm,
      session: activeSession,
    );

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  // ----------------------------------------------------------
  // ADD NEW ITEM - FIXED: Include term and session
  // ----------------------------------------------------------
  Future<void> _addItem() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    // FIXED: Include term and session when creating fee item
    await _db.insertFeeItem({
      'name': name,
      'defaultAmount': 0.0,
      'description': '',
      'term': _term,        // ← Added
      'session': _session,  // ← Added
    });

    _nameCtrl.clear();

    if (!mounted) return;
    await _load();
  }

  // ----------------------------------------------------------
  // EDIT ITEM
  // ----------------------------------------------------------
  Future<void> _editItem(Map<String, dynamic> item) async {
    _nameCtrl.text = item['name'] ?? "";

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Fee Item"),
        content: TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: "Fee Item Name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = _nameCtrl.text.trim();
              if (newName.isEmpty) return;

              await _db.updateFeeItem(
                item['id'],
                {
                  'name': newName,
                  'defaultAmount': item['defaultAmount'],
                  'description': item['description'],
                  'term': item['term'],        // Preserve term
                  'session': item['session'],  // Preserve session
                },
              );

              if (mounted) Navigator.pop(context, true);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (updated == true) {
      if (!mounted) return;
      await _load();
    }
  }

  /// Groups of tables that reference a fee item, mapped to a
  /// human-readable label so usage can be reported to the user.
  static const Map<String, String> _feeItemUsageTables = {
    'Assigned to classes (fee structure)': 'class_fees',
    'Billed to students': 'student_fee_breakdown',
    'Fee priority settings': 'fee_priority',
  };

  Future<Map<String, int>> _getFeeItemUsage(int feeItemId) async {
    final db = await _db.database;
    final Map<String, int> usage = {};

    for (final entry in _feeItemUsageTables.entries) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${entry.value} WHERE feeItemId = ?',
        [feeItemId],
      );
      final count = (result.first['c'] as int?) ?? 0;
      if (count > 0) {
        usage[entry.key] = count;
      }
    }

    return usage;
  }

  // ----------------------------------------------------------
  // DELETE ITEM
  // ----------------------------------------------------------
  Future<void> _deleteItem(int id, String itemName) async {
    final messenger = ScaffoldMessenger.of(context);

    final usage = await _getFeeItemUsage(id);
    if (usage.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red),
              SizedBox(width: 8),
              Text('Cannot Delete Fee Item'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"$itemName" cannot be deleted because it contains the following records:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...usage.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.fiber_manual_record, size: 8),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${e.key} (${e.value})')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Deleting a fee item that is still assigned or billed would '
                'disconnect those class fee assignments and student bills '
                'from any fee item, corrupting your records. Remove the '
                'assignments/bills first, or leave this item in place.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text("Delete Fee Item"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Are you sure you want to delete this fee item?",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text("Item: $itemName"),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone!',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _db.deleteFeeItem(id);

    if (!mounted) return;
    
    await _load();

    messenger.showSnackBar(
      SnackBar(content: Text('Fee item "$itemName" deleted')),
    );
  }

  // ----------------------------------------------------------
  // IMPORT FROM PREVIOUS SESSION/TERM
  // ----------------------------------------------------------
  Future<void> _importFromPreviousPeriod() async {
    final sessions = await _db.getAllSessions();
    final terms = ['1st Term', '2nd Term', '3rd Term'];

    if (sessions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous sessions available')),
      );
      return;
    }

    // Step 1: Pick source period
    if (!mounted) return;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ImportPeriodDialog(
        sessions: sessions,
        terms: terms,
        currentTerm: _term,
        currentSession: _session,
      ),
    );
    if (result == null) return;

    final selectedTerm = result['term']!;
    final selectedSession = result['session']!;

    // Step 2: Load fee items from that period
    final previousItems = await _db.getFeeItems(
      term: selectedTerm,
      session: selectedSession,
    );

    // Step 3: Load ALL class fee assignments from that period
    final Map<int, String> feeItemNameMap = {};
    for (final item in previousItems) {
      feeItemNameMap[item['id'] as int] = item['name'] as String? ?? '';
    }
    final allClasses = await _db.getClasses();
    final allArms = await _db.getArms();
    final Map<int, String> classNameMap = {
      for (final c in allClasses) c['id'] as int: c['name'] as String? ?? ''
    };
    final Map<int, String> armNameMap = {
      for (final a in allArms) a['id'] as int: a['name'] as String? ?? ''
    };
    final Map<int, List<Map<String, dynamic>>> classToArms = {};
    for (final a in allArms) {
      final cid = a['classId'] as int;
      classToArms.putIfAbsent(cid, () => []);
      classToArms[cid]!.add(a);
    }
    final List<Map<String, dynamic>> previousAssignments = [];
    for (final cls in allClasses) {
      final classId = cls['id'] as int;
      final className = classNameMap[classId] ?? '';
      final noArmFees = await _db.getClassFees(classId, selectedTerm, selectedSession);
      for (final fee in noArmFees) {
        final feeItemId = fee['feeItemId'] as int;
        previousAssignments.add({
          'classId': classId,
          'feeItemId': feeItemId,
          'amount': fee['amount'],
          'armId': 0,
          'className': className,
          'feeItemName': feeItemNameMap[feeItemId] ?? '',
          'armName': null,
        });
      }
      for (final arm in classToArms[classId] ?? []) {
        final armId = arm['id'] as int;
        final armFees = await _db.getClassFees(classId, selectedTerm, selectedSession, armId: armId);
        for (final fee in armFees) {
          final feeItemId = fee['feeItemId'] as int;
          previousAssignments.add({
            'classId': classId,
            'feeItemId': feeItemId,
            'amount': fee['amount'],
            'armId': armId,
            'className': className,
            'feeItemName': feeItemNameMap[feeItemId] ?? '',
            'armName': armNameMap[armId] ?? '',
          });
        }
      }
    }

    if (previousItems.isEmpty && previousAssignments.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nothing found in $selectedTerm, $selectedSession'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Step 4: Push preview screen; wait for user confirmation
    if (!mounted) return;
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _ImportPreviewScreen(
          fromTerm: selectedTerm,
          fromSession: selectedSession,
          toTerm: _term ?? '',
          toSession: _session ?? '',
          feeItems: previousItems,
          classAssignments: previousAssignments,
        ),
      ),
    );
    if (confirmed != true) return;

    // Step 5: Import fee items, tracking old-id → new-id mapping
    final existingItems = await _db.getFeeItems(term: _term, session: _session);
    final Map<int, int> oldToNewId = {};

    for (final item in previousItems) {
      final oldId = item['id'] as int;
      final existing = existingItems.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e!['name'] == item['name'],
        orElse: () => null,
      );
      if (existing == null) {
        final newId = await _db.insertFeeItem({
          'name': item['name'],
          'defaultAmount': item['defaultAmount'],
          'description': item['description'],
          'term': _term,
          'session': _session,
        });
        oldToNewId[oldId] = newId;
      } else {
        oldToNewId[oldId] = existing['id'] as int;
      }
    }

    // Step 6: Import class fee assignments grouped by class+arm
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final a in previousAssignments) {
      final key = '${a['classId']}-${a['armId']}';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(Map<String, dynamic>.from(a));
    }

    for (final entry in grouped.entries) {
      final rows = entry.value;
      final classId = rows.first['classId'] as int;
      final rawArmId = rows.first['armId'];
      final armId = (rawArmId == null || rawArmId == 0) ? null : rawArmId as int;

      final newRows = <Map<String, dynamic>>[];
      for (final a in rows) {
        final oldFeeItemId = a['feeItemId'] as int;
        final newFeeItemId = oldToNewId[oldFeeItemId];
        if (newFeeItemId == null) continue;
        newRows.add({
          'classId': classId,
          'feeItemId': newFeeItemId,
          'amount': a['amount'],
          'term': _term,
          'session': _session,
        });
      }

      if (newRows.isNotEmpty) {
        await _db.replaceClassFeesFor(
          classId, _term!, _session!, newRows,
          armId: armId,
        );
      }
    }

    await _load();

    if (!mounted) return;
    final itemCount = oldToNewId.length;
    final assignmentCount = grouped.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Import complete: $itemCount fee item(s) and $assignmentCount class assignment(s) imported',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // UI
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fee Items"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add),
        onPressed: () {
          _nameCtrl.clear();
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("New Fee Item"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Fee Item Name",
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    onSubmitted: (_) async {
                      final navigator = Navigator.of(context);
                      if (_nameCtrl.text.trim().isNotEmpty) {
                        await _addItem();
                      }
                      if (mounted) navigator.pop();
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Text(
                              'Will be created for:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Term: $_term',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        Text(
                          'Session: $_session',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    
                    if (_nameCtrl.text.trim().isNotEmpty) {
                      await _addItem();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Fee item "${_nameCtrl.text.trim()}" added'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                    
                    if (mounted) navigator.pop();
                  },
                  child: const Text("Add"),
                ),
              ],
            ),
          );
        },
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Active Term/Session Info Card
                  Card(
                    color: Colors.indigo.shade50,
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Active Period',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.event, size: 18, color: Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              const Text('Term: '),
                              Text(
                                _term ?? 'Not set',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 18, color: Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              const Text('Session: '),
                              Text(
                                _session ?? 'Not set',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Import from Previous Session/Term Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _importFromPreviousPeriod,
                      icon: const Icon(Icons.file_download, size: 24),
                      label: const Text(
                        'Import Fee Items & Fee Assignments from Previous Session/Term',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Assign Fees to Class Button - Large and Prominent
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final screenSize = MediaQuery.of(context).size;
                        final showSidebar = screenSize.shortestSide >= 700;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => showSidebar
                                ? SidebarScaffold(
                                    currentUser: widget.currentUser,
                                    currentPageId: 'bills_payment/fee_items',
                                    child: const FeeClassAssignmentScreen(),
                                  )
                                : const FeeClassAssignmentScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.assignment, size: 28),
                      label: const Text(
                        'Assign Fees to Class',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Fee Items Header
                  Row(
                    children: [
                      Icon(Icons.receipt_long, color: Colors.indigo.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Fee Items (${_items.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),

                  const Divider(),

                  // Empty State
                  if (_items.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.inbox,
                                  size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'No fee items created yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap the + button to add fee items',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Fee Items List
                  ..._items.map((i) {
                    final name = i['name'] ?? '';
                    final amount = (i['defaultAmount'] ?? 0).toStringAsFixed(2);
                    final term = i['term'] ?? '';
                    final session = i['session'] ?? '';

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: Icon(Icons.attach_money,
                              color: Colors.indigo.shade700),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Default: ₦$amount',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$term | $session',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _editItem(i),
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              onPressed: () => _deleteItem(i['id'], name),
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

// ----------------------------------------------------------
// IMPORT PERIOD SELECTION DIALOG
// ----------------------------------------------------------
class _ImportPeriodDialog extends StatefulWidget {
  final List<Map<String, dynamic>> sessions;
  final List<String> terms;
  final String? currentTerm;
  final String? currentSession;

  const _ImportPeriodDialog({
    required this.sessions,
    required this.terms,
    this.currentTerm,
    this.currentSession,
  });

  @override
  State<_ImportPeriodDialog> createState() => _ImportPeriodDialogState();
}

class _ImportPeriodDialogState extends State<_ImportPeriodDialog> {
  String? _selectedSession;
  String? _selectedTerm;

  @override
  void initState() {
    super.initState();
    // Default to first available session and term, excluding current
    if (widget.sessions.isNotEmpty) {
      _selectedSession = widget.sessions.first['sessionName'];
    }
    if (widget.terms.isNotEmpty) {
      _selectedTerm = widget.terms.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.file_download, color: Colors.green),
          SizedBox(width: 8),
          Text('Import from Previous Period'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Period: ${widget.currentTerm} | ${widget.currentSession}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select period to import from:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedSession,
            decoration: const InputDecoration(
              labelText: 'Session',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.calendar_today),
            ),
            items: widget.sessions.map((session) {
              final sessionName = session['sessionName'] as String;
              return DropdownMenuItem(
                value: sessionName,
                child: Text(sessionName),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _selectedSession = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedTerm,
            decoration: const InputDecoration(
              labelText: 'Term',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.event),
            ),
            items: widget.terms.map((term) {
              return DropdownMenuItem(
                value: term,
                child: Text(term),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _selectedTerm = value);
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Fee items will be copied to the current period',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedSession != null && _selectedTerm != null) {
              Navigator.pop(context, {
                'session': _selectedSession!,
                'term': _selectedTerm!,
              });
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('Next'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------
// IMPORT PREVIEW SCREEN
// ----------------------------------------------------------
class _ImportPreviewScreen extends StatelessWidget {
  final String fromTerm;
  final String fromSession;
  final String toTerm;
  final String toSession;
  final List<Map<String, dynamic>> feeItems;
  final List<Map<String, dynamic>> classAssignments;

  const _ImportPreviewScreen({
    required this.fromTerm,
    required this.fromSession,
    required this.toTerm,
    required this.toSession,
    required this.feeItems,
    required this.classAssignments,
  });

  String _fmt(dynamic amount) {
    final val = (amount as num?)?.toDouble() ?? 0.0;
    final parts = val.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buffer.write(',');
      buffer.write(parts[i]);
    }
    return '₦$buffer';
  }

  @override
  Widget build(BuildContext context) {
    // Group class assignments by "ClassName" or "ClassName — ArmName"
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final a in classAssignments) {
      final className = a['className'] as String? ?? 'Unknown';
      final armName = a['armName'] as String?;
      final key = (armName != null && armName.isNotEmpty)
          ? '$className — $armName'
          : className;
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(a);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Preview'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.download_done),
                  label: const Text(
                    'Import All',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Period info card
          Card(
            color: Colors.indigo.shade50,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz, color: Colors.indigo.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'Import Summary',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.arrow_circle_right, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        'From: $fromTerm  |  $fromSession',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.arrow_circle_right, size: 16, color: Colors.indigo.shade600),
                      const SizedBox(width: 6),
                      Text(
                        'To:      $toTerm  |  $toSession',
                        style: TextStyle(
                          color: Colors.indigo.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${feeItems.length} fee item(s)  •  ${grouped.length} class assignment(s)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Fee Items section
          if (feeItems.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Text(
                  'Fee Items (${feeItems.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            ...feeItems.map((item) {
              final name = item['name'] as String? ?? '';
              final defaultAmount = item['defaultAmount'];
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                elevation: 1,
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade100,
                    radius: 18,
                    child: Icon(Icons.attach_money,
                        color: Colors.indigo.shade700, size: 18),
                  ),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: Text(
                    _fmt(defaultAmount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
          ],

          // Fee Assignments per Class/Arm section
          if (grouped.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.school, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Text(
                  'Fee Assignments (${grouped.length} class/arm)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            ...grouped.entries.map((entry) {
              final label = entry.key;
              final rows = entry.value;
              final total = rows.fold<double>(
                0,
                (sum, a) => sum + ((a['amount'] as num?)?.toDouble() ?? 0),
              );

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Class/arm header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.class_,
                              size: 18, color: Colors.indigo.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Total: ${_fmt(total)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Individual fee rows
                    ...rows.map((a) {
                      final feeName =
                          a['feeItemName'] as String? ?? 'Unknown';
                      final amount = a['amount'];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        child: Row(
                          children: [
                            Icon(Icons.chevron_right,
                                size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(feeName,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                            Text(
                              _fmt(amount),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                  ],
                ),
              );
            }),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}