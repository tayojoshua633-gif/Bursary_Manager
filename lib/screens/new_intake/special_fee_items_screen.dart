import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import 'special_fee_assignment_screen.dart';

class SpecialFeeItemsScreen extends StatefulWidget {
  const SpecialFeeItemsScreen({super.key});

  @override
  State<SpecialFeeItemsScreen> createState() => _SpecialFeeItemsScreenState();
}

class _SpecialFeeItemsScreenState extends State<SpecialFeeItemsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _nameCtrl = TextEditingController();

  List<Map<String, dynamic>> _categories = []; // Categories (parents with children)
  List<Map<String, dynamic>> _standaloneItems = []; // Standalone items (no parent, no children)
  final Map<int, List<Map<String, dynamic>>> _childItemsMap = {}; // Children by parent ID
  final Set<int> _expandedParents = {}; // Track expanded categories

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
    final activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";

    _term = activeTerm;
    _session = activeSession;

    // Load categories (items with isCategory = 1)
    _categories = await _db.getSpecialFeeItemCategories(
      term: activeTerm,
      session: activeSession,
    );

    // Load standalone items (items with isCategory = 0)
    _standaloneItems = await _db.getSpecialFeeItemStandalone(
      term: activeTerm,
      session: activeSession,
    );

    // Load children for each category
    _childItemsMap.clear();
    for (var category in _categories) {
      final categoryId = category['id'] as int;
      final children = await _db.getSpecialFeeItemChildren(
        categoryId,
        term: activeTerm,
        session: activeSession,
      );
      _childItemsMap[categoryId] = children;
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  int get _totalItems {
    int total = _categories.length + _standaloneItems.length;
    for (var children in _childItemsMap.values) {
      total += children.length;
    }
    return total;
  }

  // ----------------------------------------------------------
  // ADD STANDALONE ITEM (NO PARENT)
  // ----------------------------------------------------------
  Future<void> _addStandaloneItem() async {
    _nameCtrl.clear();

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.receipt, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text("New Standalone Item"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: "Item Name",
                border: OutlineInputBorder(),
                hintText: "e.g., Registration Fee, ID Card",
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Standalone items are not grouped under any category',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
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
            onPressed: () async {
              final name = _nameCtrl.text.trim();
              if (name.isEmpty) return;

              await _db.insertSpecialFeeItem({
                'name': name,
                'defaultAmount': 0.0,
                'description': '',
                'term': _term,
                'session': _session,
                'createdAt': DateTime.now().toIso8601String(),
                'parentId': null,
                'isCategory': 0, // Mark as standalone item
              });

              if (mounted) Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text("Create Item"),
          ),
        ],
      ),
    );

    if (result == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Item "${_nameCtrl.text.trim()}" created'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ----------------------------------------------------------
  // ADD CATEGORY (PARENT ITEM)
  // ----------------------------------------------------------
  Future<void> _addCategory() async {
    _nameCtrl.clear();

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.folder, color: Colors.deepOrange.shade700),
            const SizedBox(width: 8),
            const Text("New Category"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: "Category Name",
                border: OutlineInputBorder(),
                hintText: "e.g., Uniform, Text Books",
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
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
                  Expanded(
                    child: Text(
                      'Categories group related fee items together',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
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
            onPressed: () async {
              final name = _nameCtrl.text.trim();
              if (name.isEmpty) return;

              await _db.insertSpecialFeeItem({
                'name': name,
                'defaultAmount': 0.0,
                'description': '',
                'term': _term,
                'session': _session,
                'createdAt': DateTime.now().toIso8601String(),
                'parentId': null,
                'isCategory': 1, // Mark as category
              });

              if (mounted) Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text("Create Category"),
          ),
        ],
      ),
    );

    if (result == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Category "${_nameCtrl.text.trim()}" created'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ----------------------------------------------------------
  // ADD CHILD ITEM TO CATEGORY
  // ----------------------------------------------------------
  Future<void> _addChildItem(int parentId, String parentName) async {
    _nameCtrl.clear();

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_circle, color: Colors.deepOrange.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text("Add Item to $parentName")),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: "Item Name",
                border: const OutlineInputBorder(),
                hintText: "e.g., Vest, Socks, English Book",
                prefixIcon: Icon(Icons.subdirectory_arrow_right, color: Colors.grey.shade400),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_open, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Adding to: $parentName',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.bold),
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
            onPressed: () async {
              final name = _nameCtrl.text.trim();
              if (name.isEmpty) return;

              await _db.insertSpecialFeeItem({
                'name': name,
                'defaultAmount': 0.0,
                'description': '',
                'term': _term,
                'session': _session,
                'createdAt': DateTime.now().toIso8601String(),
                'parentId': parentId,
                'isCategory': 0, // Child items are never categories
              });

              if (mounted) Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text("Add Item"),
          ),
        ],
      ),
    );

    if (result == true) {
      // Auto-expand this category
      _expandedParents.add(parentId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${_nameCtrl.text.trim()}" added to $parentName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ----------------------------------------------------------
  // EDIT ITEM
  // ----------------------------------------------------------
  Future<void> _editItem(Map<String, dynamic> item, {bool isParent = false}) async {
    _nameCtrl.text = item['name'] ?? "";

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isParent ? "Edit Category" : "Edit Item"),
        content: TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: isParent ? "Category Name" : "Item Name",
            border: const OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
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

              await _db.updateSpecialFeeItem(
                item['id'],
                {
                  'name': newName,
                  'defaultAmount': item['defaultAmount'],
                  'description': item['description'],
                  'term': item['term'],
                  'session': item['session'],
                  'createdAt': item['createdAt'],
                  'parentId': item['parentId'],
                  'isCategory': item['isCategory'] ?? 0,
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
      await _load();
    }
  }

  /// Returns the human-readable labels (with counts) of every kind of
  /// record that depends on this special fee item, so deletion can be
  /// blocked and explained instead of silently orphaning data.
  Future<Map<String, int>> _getSpecialFeeItemUsage(int id, {bool isParent = false}) async {
    final db = await _db.database;
    final Map<String, int> usage = {};

    List<int> ids = [id];
    if (isParent) {
      final children = await db.query('special_fee_items', where: 'parentId = ?', whereArgs: [id]);
      if (children.isNotEmpty) {
        usage['Items inside this category'] = children.length;
        ids.addAll(children.map((c) => c['id'] as int));
      }
    }

    final placeholders = List.filled(ids.length, '?').join(', ');
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM special_class_fees WHERE specialFeeItemId IN ($placeholders)',
      ids,
    );
    final assignedCount = (result.first['c'] as int?) ?? 0;
    if (assignedCount > 0) {
      usage['Assigned to classes'] = assignedCount;
    }

    return usage;
  }

  // ----------------------------------------------------------
  // DELETE ITEM
  // ----------------------------------------------------------
  Future<void> _deleteItem(int id, String itemName, {bool isParent = false}) async {
    final messenger = ScaffoldMessenger.of(context);

    final usage = await _getSpecialFeeItemUsage(id, isParent: isParent);
    if (usage.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.block, color: Colors.red),
              const SizedBox(width: 8),
              Text(isParent ? 'Cannot Delete Category' : 'Cannot Delete Item'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"$itemName" cannot be deleted because it contains the following:',
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
              Text(
                isParent
                    ? 'Deleting this category would orphan the item(s) inside '
                        'it and/or disconnect their class fee assignments. '
                        'Remove or move the items out of this category first.'
                    : 'Deleting this item that is still assigned to classes '
                        'would disconnect those fee assignments, corrupting '
                        'your records. Remove the class assignment(s) first.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
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
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 8),
            Text(isParent ? "Delete Category" : "Delete Item"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isParent
                  ? "Are you sure you want to delete this category?"
                  : "Are you sure you want to delete this item?",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text("Item: $itemName"),
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

    await _db.deleteSpecialFeeItem(id);
    await _load();

    messenger.showSnackBar(
      SnackBar(content: Text('$itemName deleted')),
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

    // Step 2: Load special fee items (categories + children + standalone)
    final previousCategories = await _db.getSpecialFeeItemCategories(
      term: selectedTerm,
      session: selectedSession,
    );
    final previousStandalone = await _db.getSpecialFeeItemStandalone(
      term: selectedTerm,
      session: selectedSession,
    );
    final Map<int, List<Map<String, dynamic>>> previousChildren = {};
    for (final cat in previousCategories) {
      final catId = cat['id'] as int;
      previousChildren[catId] = await _db.getSpecialFeeItemChildren(
        catId,
        term: selectedTerm,
        session: selectedSession,
      );
    }

    // Step 3: Load ALL special class fee assignments from that period
    // Build fee item name map from loaded items
    final Map<int, String> feeItemNameMap = {};
    for (final cat in previousCategories) {
      feeItemNameMap[cat['id'] as int] = cat['name'] as String? ?? '';
      for (final child in previousChildren[cat['id'] as int] ?? []) {
        feeItemNameMap[child['id'] as int] = child['name'] as String? ?? '';
      }
    }
    for (final item in previousStandalone) {
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
      // No-arm fees (armId IS NULL or 0)
      final noArmFees = await _db.getSpecialClassFees(classId, selectedTerm, selectedSession);
      for (final fee in noArmFees) {
        final feeItemId = fee['specialFeeItemId'] as int;
        previousAssignments.add({
          'classId': classId,
          'specialFeeItemId': feeItemId,
          'amount': fee['amount'],
          'armId': 0,
          'className': className,
          'feeItemName': feeItemNameMap[feeItemId] ?? '',
          'armName': null,
        });
      }
      // Per-arm fees
      for (final arm in classToArms[classId] ?? []) {
        final armId = arm['id'] as int;
        final armFees = await _db.getSpecialClassFees(classId, selectedTerm, selectedSession, armId: armId);
        for (final fee in armFees) {
          final feeItemId = fee['specialFeeItemId'] as int;
          previousAssignments.add({
            'classId': classId,
            'specialFeeItemId': feeItemId,
            'amount': fee['amount'],
            'armId': armId,
            'className': className,
            'feeItemName': feeItemNameMap[feeItemId] ?? '',
            'armName': armNameMap[armId] ?? '',
          });
        }
      }
    }

    if (previousCategories.isEmpty &&
        previousStandalone.isEmpty &&
        previousAssignments.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nothing found in $selectedTerm, $selectedSession'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Step 4: Push preview screen; wait for confirmation
    if (!mounted) return;
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _ImportPreviewScreen(
          fromTerm: selectedTerm,
          fromSession: selectedSession,
          toTerm: _term ?? '',
          toSession: _session ?? '',
          categories: previousCategories,
          childItemsMap: previousChildren,
          standaloneItems: previousStandalone,
          classAssignments: previousAssignments,
        ),
      ),
    );
    if (confirmed != true) return;

    // Step 5: Import special fee items, building old-id → new-id map
    final existingCategories = await _db.getSpecialFeeItemCategories(
        term: _term, session: _session);
    final existingStandalone = await _db.getSpecialFeeItemStandalone(
        term: _term, session: _session);
    final Map<int, int> oldToNewId = {};

    for (final cat in previousCategories) {
      final oldCatId = cat['id'] as int;
      final existing = existingCategories.cast<Map<String, dynamic>?>()
          .firstWhere((e) => e!['name'] == cat['name'], orElse: () => null);

      final int newCatId;
      if (existing == null) {
        newCatId = await _db.insertSpecialFeeItem({
          'name': cat['name'],
          'defaultAmount': cat['defaultAmount'],
          'description': cat['description'],
          'term': _term,
          'session': _session,
          'parentId': null,
          'isCategory': 1,
          'createdAt': DateTime.now().toIso8601String(),
        });
      } else {
        newCatId = existing['id'] as int;
      }
      oldToNewId[oldCatId] = newCatId;

      final children = previousChildren[oldCatId] ?? [];
      final existingChildren = await _db.getSpecialFeeItemChildren(
          newCatId, term: _term, session: _session);

      for (final child in children) {
        final oldChildId = child['id'] as int;
        final existingChild = existingChildren
            .cast<Map<String, dynamic>?>()
            .firstWhere((e) => e!['name'] == child['name'],
                orElse: () => null);

        final int newChildId;
        if (existingChild == null) {
          newChildId = await _db.insertSpecialFeeItem({
            'name': child['name'],
            'defaultAmount': child['defaultAmount'],
            'description': child['description'],
            'term': _term,
            'session': _session,
            'parentId': newCatId,
            'isCategory': 0,
            'createdAt': DateTime.now().toIso8601String(),
          });
        } else {
          newChildId = existingChild['id'] as int;
        }
        oldToNewId[oldChildId] = newChildId;
      }
    }

    for (final item in previousStandalone) {
      final oldId = item['id'] as int;
      final existing = existingStandalone.cast<Map<String, dynamic>?>()
          .firstWhere((e) => e!['name'] == item['name'], orElse: () => null);

      final int newId;
      if (existing == null) {
        newId = await _db.insertSpecialFeeItem({
          'name': item['name'],
          'defaultAmount': item['defaultAmount'],
          'description': item['description'],
          'term': _term,
          'session': _session,
          'parentId': null,
          'isCategory': 0,
          'createdAt': DateTime.now().toIso8601String(),
        });
      } else {
        newId = existing['id'] as int;
      }
      oldToNewId[oldId] = newId;
    }

    // Step 6: Import special class fee assignments grouped by class+arm
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
      final armId =
          (rawArmId == null || rawArmId == 0) ? null : rawArmId as int;

      final newRows = <Map<String, dynamic>>[];
      for (final a in rows) {
        final oldFeeItemId = a['specialFeeItemId'] as int;
        final newFeeItemId = oldToNewId[oldFeeItemId];
        if (newFeeItemId == null) continue;
        newRows.add({
          'classId': classId,
          'specialFeeItemId': newFeeItemId,
          'amount': a['amount'],
          'term': _term,
          'session': _session,
        });
      }

      if (newRows.isNotEmpty) {
        await _db.replaceSpecialClassFeesFor(
          classId, _term!, _session!, newRows,
          armId: armId,
        );
      }
    }

    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Import complete: ${oldToNewId.length} special fee item(s) and '
          '${grouped.length} class assignment(s) imported',
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
        title: const Text("Special Bills Items"),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Add Standalone Item Button
          FloatingActionButton.extended(
            heroTag: 'addItem',
            backgroundColor: Colors.orange,
            icon: const Icon(Icons.receipt),
            label: const Text("Add Item"),
            onPressed: _addStandaloneItem,
          ),
          const SizedBox(height: 12),
          // Add Category Button
          FloatingActionButton.extended(
            heroTag: 'addCategory',
            backgroundColor: Colors.deepOrange,
            icon: const Icon(Icons.create_new_folder),
            label: const Text("Add Category"),
            onPressed: _addCategory,
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                children: [
                  // Info Card
                  Card(
                    color: Colors.deepOrange.shade50,
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person_add_alt_1, color: Colors.deepOrange.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'New Intake Bills - Special Fees',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Organize special fees into categories (e.g., Uniform, Text Books)',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.event, size: 18, color: Colors.deepOrange.shade700),
                              const SizedBox(width: 8),
                              Text('$_term | $_session', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                        'Import Special Fee Items & Fee Assignments from Previous Session/Term',
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

                  // Assign Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _totalItems == 0
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const SpecialFeeAssignmentScreen()),
                              );
                            },
                      icon: const Icon(Icons.assignment, size: 28),
                      label: const Text(
                        'Assign Special Fees to Class',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Header
                  Row(
                    children: [
                      Icon(Icons.folder_special, color: Colors.deepOrange.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Categories & Items ($_totalItems)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  const Divider(),

                  // Empty State
                  if (_categories.isEmpty && _standaloneItems.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.folder_off, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'No special fee items yet',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Use the menu below to add:\n• Categories (group related items)\n• Standalone Items (individual fees)',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Standalone Items Section
                  if (_standaloneItems.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.receipt_long, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Standalone Items (${_standaloneItems.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._standaloneItems.map((item) {
                      final itemId = item['id'] as int;
                      final itemName = item['name'] ?? '';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade100,
                            child: Icon(Icons.receipt, color: Colors.orange.shade700),
                          ),
                          title: Text(itemName, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: const Text('Standalone item', style: TextStyle(fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _editItem(item),
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                tooltip: 'Edit item',
                              ),
                              IconButton(
                                onPressed: () => _deleteItem(itemId, itemName),
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Delete item',
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],

                  // Categories Section Header
                  if (_categories.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.folder_special, color: Colors.deepOrange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Categories (${_categories.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Categories with Children
                  ..._categories.map((parent) {
                    final parentId = parent['id'] as int;
                    final parentName = parent['name'] ?? '';
                    final children = _childItemsMap[parentId] ?? [];
                    final isExpanded = _expandedParents.contains(parentId);

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          // Parent/Category Header
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedParents.remove(parentId);
                                } else {
                                  _expandedParents.add(parentId);
                                }
                              });
                            },
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade100,
                                borderRadius: BorderRadius.vertical(
                                  top: const Radius.circular(12),
                                  bottom: isExpanded ? Radius.zero : const Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isExpanded ? Icons.folder_open : Icons.folder,
                                    color: Colors.deepOrange.shade700,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          parentName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          '${children.length} item${children.length != 1 ? 's' : ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _addChildItem(parentId, parentName),
                                    icon: Icon(Icons.add_circle, color: Colors.green.shade600),
                                    tooltip: 'Add item to category',
                                  ),
                                  IconButton(
                                    onPressed: () => _editItem(parent, isParent: true),
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'Edit category',
                                  ),
                                  IconButton(
                                    onPressed: () => _deleteItem(parentId, parentName, isParent: true),
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: 'Delete category',
                                  ),
                                  Icon(
                                    isExpanded ? Icons.expand_less : Icons.expand_more,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Children
                          if (isExpanded) ...[
                            if (children.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    Icon(Icons.inbox, size: 40, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No items in this category',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: () => _addChildItem(parentId, parentName),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add first item'),
                                    ),
                                  ],
                                ),
                              ),
                            ...children.map((child) {
                              final childName = child['name'] ?? '';
                              return Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: Colors.grey.shade200),
                                  ),
                                ),
                                child: ListTile(
                                  leading: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(width: 16),
                                      Icon(Icons.subdirectory_arrow_right, color: Colors.grey.shade400, size: 20),
                                      const SizedBox(width: 8),
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Colors.orange.shade100,
                                        child: Icon(Icons.receipt, size: 16, color: Colors.orange.shade700),
                                      ),
                                    ],
                                  ),
                                  title: Text(childName),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: () => _editItem(child),
                                        icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                        tooltip: 'Edit item',
                                      ),
                                      IconButton(
                                        onPressed: () => _deleteItem(child['id'], childName),
                                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                        tooltip: 'Delete item',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 80), // Space for FAB
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
                    'Special fee items will be copied to the current period',
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
  final List<Map<String, dynamic>> categories;
  final Map<int, List<Map<String, dynamic>>> childItemsMap;
  final List<Map<String, dynamic>> standaloneItems;
  final List<Map<String, dynamic>> classAssignments;

  const _ImportPreviewScreen({
    required this.fromTerm,
    required this.fromSession,
    required this.toTerm,
    required this.toSession,
    required this.categories,
    required this.childItemsMap,
    required this.standaloneItems,
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

  int get _totalItems {
    int count = categories.length + standaloneItems.length;
    for (final children in childItemsMap.values) {
      count += children.length;
    }
    return count;
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
        backgroundColor: Colors.deepOrange,
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
            color: Colors.deepOrange.shade50,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz, color: Colors.deepOrange.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'Import Summary',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.arrow_circle_right,
                          size: 16, color: Colors.grey.shade600),
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
                      Icon(Icons.arrow_circle_right,
                          size: 16, color: Colors.deepOrange.shade600),
                      const SizedBox(width: 6),
                      Text(
                        'To:      $toTerm  |  $toSession',
                        style: TextStyle(
                          color: Colors.deepOrange.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$_totalItems special fee item(s)  •  ${grouped.length} class assignment(s)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Special Fee Items section
          if (categories.isNotEmpty || standaloneItems.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.folder_special, color: Colors.deepOrange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Special Fee Items ($_totalItems)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),

            // Standalone items
            if (standaloneItems.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Standalone Items (${standaloneItems.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
              ...standaloneItems.map((item) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    elevation: 1,
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.shade100,
                        radius: 18,
                        child: Icon(Icons.receipt,
                            color: Colors.orange.shade700, size: 18),
                      ),
                      title: Text(item['name'] as String? ?? '',
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Text(
                        _fmt(item['defaultAmount']),
                        style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  )),
              const SizedBox(height: 12),
            ],

            // Categories with children
            if (categories.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Categories (${categories.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepOrange.shade700,
                  ),
                ),
              ),
              ...categories.map((cat) {
                final catId = cat['id'] as int;
                final children = childItemsMap[catId] ?? [];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.shade50,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.folder,
                                size: 20,
                                color: Colors.deepOrange.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cat['name'] as String? ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange.shade900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Text(
                              '${children.length} item${children.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.deepOrange.shade600),
                            ),
                          ],
                        ),
                      ),
                      // Children
                      ...children.map((child) => Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            child: Row(
                              children: [
                                Icon(Icons.subdirectory_arrow_right,
                                    size: 16,
                                    color: Colors.deepOrange.shade300),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                      child['name'] as String? ?? '',
                                      style:
                                          const TextStyle(fontSize: 13)),
                                ),
                                Text(
                                  _fmt(child['defaultAmount']),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 6),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 20),
          ],

          // Fee Assignments per Class/Arm section
          if (grouped.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.school, color: Colors.deepOrange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Fee Assignments (${grouped.length} class/arm)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            ...grouped.entries.map((entry) {
              final label = entry.key;
              final rows = entry.value;
              final total = rows.fold<double>(
                0,
                (sum, a) =>
                    sum + ((a['amount'] as num?)?.toDouble() ?? 0),
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
                        color: Colors.deepOrange.shade50,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.class_,
                              size: 18,
                              color: Colors.deepOrange.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange.shade900,
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
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        child: Row(
                          children: [
                            Icon(Icons.chevron_right,
                                size: 16,
                                color: Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(feeName,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                            Text(
                              _fmt(a['amount']),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
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
