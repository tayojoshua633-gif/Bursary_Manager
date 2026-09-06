import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';

class SpecialFeeAssignmentScreen extends StatefulWidget {
  const SpecialFeeAssignmentScreen({super.key});

  @override
  State<SpecialFeeAssignmentScreen> createState() =>
      _SpecialFeeAssignmentScreenState();
}

class _SpecialFeeAssignmentScreenState extends State<SpecialFeeAssignmentScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  List<Map<String, dynamic>> _regularFeeItems = []; // From class_fees
  List<Map<String, dynamic>> _specialFeeItems = []; // All special fees (flat list for saving)
  List<Map<String, dynamic>> _categories = []; // Categories (parents with children)
  List<Map<String, dynamic>> _standaloneItems = []; // Standalone items (no parent, no children)
  final Map<int, List<Map<String, dynamic>>> _childItemsMap = {}; // Children by parent ID
  Set<int> _expandedCategories = {}; // Track expanded categories
  Set<int> _excludedDefaultFeeIds = {}; // Track excluded default fees

  String? _activeTerm;
  String? _activeSession;
  int? _selectedClassId;
  int? _selectedArmId;
  Map<int, List<Map<String, dynamic>>> _armsByClass = {};

  // Multi class/arm assignment mode
  bool _applyToMultiple = false;
  final Set<String> _selectedTargets = {};

  final Map<int, TextEditingController> _amountCtrl = {};
  bool _loading = true;
  bool _loadingArms = false;
  double _regularTotal = 0;
  double _specialTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // -----------------------------------------------------------
  // LOAD ACTIVE TERM/SESSION + CLASSES + SPECIAL FEE ITEMS
  // -----------------------------------------------------------
  Future<void> _load() async {
    setState(() => _loading = true);

    _activeTerm = await _db.getActiveTerm();
    _activeSession =
        (await _db.getActiveSession())?['sessionName'] ?? "";

    _classes = await _db.getClasses();

    // Load arms for ALL classes at once (needed for multi class/arm selection)
    final database = await _db.database;
    final allArms = await database.query('arms', orderBy: 'classId, name');
    _armsByClass = {};
    for (var arm in allArms) {
      final classId = arm['classId'] as int;
      _armsByClass.putIfAbsent(classId, () => []).add(arm);
    }

    // Load all special fee items (flat list for saving)
    _specialFeeItems = await _db.getSpecialFeeItems(
      term: _activeTerm,
      session: _activeSession,
    );

    // Load categories (items with isCategory = 1)
    _categories = await _db.getSpecialFeeItemCategories(
      term: _activeTerm,
      session: _activeSession,
    );

    // Load standalone items (items with isCategory = 0)
    _standaloneItems = await _db.getSpecialFeeItemStandalone(
      term: _activeTerm,
      session: _activeSession,
    );

    // Load children for each category
    _childItemsMap.clear();
    for (var category in _categories) {
      final categoryId = category['id'] as int;
      final children = await _db.getSpecialFeeItemChildren(
        categoryId,
        term: _activeTerm,
        session: _activeSession,
      );
      _childItemsMap[categoryId] = children;
    }

    // Expand all categories by default
    _expandedCategories = _categories.map((p) => p['id'] as int).toSet();

    _amountCtrl.clear();

    // Create controllers for child items (items with parentId) AND standalone items
    for (var item in _specialFeeItems) {
      final id = item['id'] as int;
      final parentId = item['parentId'];
      final defaultAmount = (item['defaultAmount'] ?? 0);

      // Create controllers for child items (items with parentId)
      if (parentId != null) {
        _amountCtrl[id] = TextEditingController(
          text: defaultAmount > 0 ? defaultAmount.toString() : '',
        )..addListener(_recalculateTotal);
      }
    }

    // Create controllers for standalone items
    for (var item in _standaloneItems) {
      final id = item['id'] as int;
      final defaultAmount = (item['defaultAmount'] ?? 0);

      _amountCtrl[id] = TextEditingController(
        text: defaultAmount > 0 ? defaultAmount.toString() : '',
      )..addListener(_recalculateTotal);
    }

    _recalculateTotal();
    if (mounted) setState(() => _loading = false);
  }

  // -----------------------------------------------------------
  // WHEN A CLASS IS SELECTED
  // -----------------------------------------------------------
  Future<void> _onClassChanged(int? classId) async {
    if (classId == null) return;

    setState(() {
      _selectedClassId = classId;
      _selectedArmId = null;
      _arms = [];
      _regularFeeItems = [];
      _regularTotal = 0;
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
        }
        await _loadFeesForSelection();
      }
    } catch (e) {
      debugPrint('Error loading arms: $e');
      setState(() {
        _arms = [];
        _loadingArms = false;
      });
    }
  }

  // -----------------------------------------------------------
  // WHEN AN ARM IS SELECTED
  // -----------------------------------------------------------
  Future<void> _onArmChanged(int? armId) async {
    if (armId == null) return;

    setState(() => _selectedArmId = armId);
    await _loadFeesForSelection();
  }

  // -----------------------------------------------------------
  // LOAD FEES FOR SELECTED CLASS/ARM
  // -----------------------------------------------------------
  Future<void> _loadFeesForSelection() async {
    if (_selectedClassId == null) return;

    setState(() => _loading = true);

    // Load regular class fees
    final db = await _db.database;
    List<Map<String, dynamic>> regularFees;

    if (_selectedArmId != null) {
      // Filter by specific arm
      regularFees = await db.rawQuery('''
        SELECT cf.id, cf.feeItemId, cf.amount, fi.name as feeItemName
        FROM class_fees cf
        LEFT JOIN fee_items fi ON cf.feeItemId = fi.id
        WHERE cf.classId = ? AND cf.term = ? AND cf.session = ? AND cf.armId = ?
        ORDER BY fi.name ASC
      ''', [_selectedClassId, _activeTerm, _activeSession, _selectedArmId]);
    } else {
      // No arm selected, load all fees for the class
      regularFees = await db.rawQuery('''
        SELECT cf.id, cf.feeItemId, cf.amount, fi.name as feeItemName
        FROM class_fees cf
        LEFT JOIN fee_items fi ON cf.feeItemId = fi.id
        WHERE cf.classId = ? AND cf.term = ? AND cf.session = ?
        ORDER BY fi.name ASC
      ''', [_selectedClassId, _activeTerm, _activeSession]);
    }

    _regularFeeItems = regularFees;

    // Load excluded default fees for this class
    try {
      final excludedFees = await db.query(
        'excluded_default_fees',
        where: 'classId = ? AND term = ? AND session = ?',
        whereArgs: [_selectedClassId, _activeTerm, _activeSession],
      );
      _excludedDefaultFeeIds = excludedFees.map((e) => e['classFeeId'] as int).toSet();
    } catch (e) {
      // Table might not exist yet, ignore error
      _excludedDefaultFeeIds = {};
      debugPrint('Note: excluded_default_fees table not found: $e');
    }

    _recalculateRegularTotal();

    // Load existing special fee assignments
    final existingSpecialFees = await _db.getSpecialClassFees(
      _selectedClassId!,
      _activeTerm ?? "",
      _activeSession ?? "",
      armId: _selectedArmId,
    );

    // Pre-fill special fee amounts from existing assignments (for child items)
    for (var item in _specialFeeItems) {
      final id = item['id'] as int;
      final parentId = item['parentId'];

      // Only pre-fill child items (items with parentId)
      if (parentId == null) continue;

      Map<String, dynamic>? match;
      for (var row in existingSpecialFees) {
        final rowFeeItemId = row['specialFeeItemId'];
        if (rowFeeItemId is int && rowFeeItemId == id) {
          match = row;
          break;
        } else if (rowFeeItemId != null && rowFeeItemId.toString() == id.toString()) {
          match = row;
          break;
        }
      }

      double amount = 0.0;
      if (match != null) {
        final matchAmount = match['amount'];
        if (matchAmount is num) {
          amount = matchAmount.toDouble();
        }
      } else {
        final defaultAmount = item['defaultAmount'];
        if (defaultAmount is num) {
          amount = defaultAmount.toDouble();
        }
      }

      _amountCtrl[id]?.text = amount > 0 ? amount.toStringAsFixed(0) : '';
    }

    // Pre-fill special fee amounts for standalone items
    for (var item in _standaloneItems) {
      final id = item['id'] as int;

      Map<String, dynamic>? match;
      for (var row in existingSpecialFees) {
        final rowFeeItemId = row['specialFeeItemId'];
        if (rowFeeItemId is int && rowFeeItemId == id) {
          match = row;
          break;
        } else if (rowFeeItemId != null && rowFeeItemId.toString() == id.toString()) {
          match = row;
          break;
        }
      }

      double amount = 0.0;
      if (match != null) {
        final matchAmount = match['amount'];
        if (matchAmount is num) {
          amount = matchAmount.toDouble();
        }
      } else {
        final defaultAmount = item['defaultAmount'];
        if (defaultAmount is num) {
          amount = defaultAmount.toDouble();
        }
      }

      _amountCtrl[id]?.text = amount > 0 ? amount.toStringAsFixed(0) : '';
    }

    _recalculateTotal();
    if (mounted) setState(() => _loading = false);
  }

  // -----------------------------------------------------------
  // UPDATE TOTAL BILL
  // -----------------------------------------------------------
  void _recalculateTotal() {
    double t = 0;

    // Sum amounts from child items (items with parentId)
    for (var item in _specialFeeItems) {
      final id = item['id'] as int;
      final parentId = item['parentId'];

      // Only include child items (items with parentId)
      if (parentId == null) continue;

      final ctrl = _amountCtrl[id];
      if (ctrl == null) continue;

      final amount = double.tryParse(ctrl.text.trim()) ?? 0;
      t += amount;
    }

    // Also sum amounts from standalone items
    for (var item in _standaloneItems) {
      final id = item['id'] as int;
      final ctrl = _amountCtrl[id];
      if (ctrl == null) continue;

      final amount = double.tryParse(ctrl.text.trim()) ?? 0;
      t += amount;
    }

    setState(() => _specialTotal = t);
  }

  // -----------------------------------------------------------
  // CALCULATE CATEGORY SUBTOTAL
  // -----------------------------------------------------------
  double _getCategorySubtotal(int parentId) {
    final children = _childItemsMap[parentId] ?? [];
    double subtotal = 0;

    for (var child in children) {
      final id = child['id'] as int;
      final ctrl = _amountCtrl[id];
      if (ctrl != null) {
        subtotal += double.tryParse(ctrl.text.trim()) ?? 0;
      }
    }

    return subtotal;
  }

  // -----------------------------------------------------------
  // RECALCULATE REGULAR FEES TOTAL (excluding removed fees)
  // -----------------------------------------------------------
  void _recalculateRegularTotal() {
    double t = 0;
    for (var fee in _regularFeeItems) {
      final feeId = fee['id'] as int;
      if (!_excludedDefaultFeeIds.contains(feeId)) {
        t += (fee['amount'] as num?)?.toDouble() ?? 0;
      }
    }
    setState(() => _regularTotal = t);
  }

  // -----------------------------------------------------------
  // REMOVE DEFAULT FEE FROM NEW INTAKE BILL
  // -----------------------------------------------------------
  Future<void> _removeDefaultFee(int classFeeId, String feeName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Fee?'),
        content: Text(
          'Remove "$feeName" from new intake bills for this class?\n\n'
          'This fee will not be included when generating new intake bills.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Add to excluded set
    setState(() {
      _excludedDefaultFeeIds.add(classFeeId);
    });
    _recalculateRegularTotal();

    // Save to database
    try {
      final db = await _db.database;

      // Ensure table exists
      await db.execute('''
        CREATE TABLE IF NOT EXISTS excluded_default_fees (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          classId INTEGER NOT NULL,
          classFeeId INTEGER NOT NULL,
          term TEXT NOT NULL,
          session TEXT NOT NULL,
          UNIQUE(classId, classFeeId, term, session)
        )
      ''');

      await db.insert('excluded_default_fees', {
        'classId': _selectedClassId,
        'classFeeId': classFeeId,
        'term': _activeTerm,
        'session': _activeSession,
      });
    } catch (e) {
      debugPrint('Error saving excluded fee: $e');
    }
  }

  // -----------------------------------------------------------
  // RESTORE DEFAULT FEE TO NEW INTAKE BILL
  // -----------------------------------------------------------
  Future<void> _restoreDefaultFee(int classFeeId) async {
    setState(() {
      _excludedDefaultFeeIds.remove(classFeeId);
    });
    _recalculateRegularTotal();

    // Remove from database
    try {
      final db = await _db.database;
      await db.delete(
        'excluded_default_fees',
        where: 'classId = ? AND classFeeId = ? AND term = ? AND session = ?',
        whereArgs: [_selectedClassId, classFeeId, _activeTerm, _activeSession],
      );
    } catch (e) {
      debugPrint('Error restoring fee: $e');
    }
  }

  // -----------------------------------------------------------
  // SAVE TO DATABASE
  // -----------------------------------------------------------
  Future<void> _saveAssignments() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a class")),
      );
      return;
    }

    if (_arms.isNotEmpty && _selectedArmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an arm")),
      );
      return;
    }

    final sessionVal = _activeSession ?? "";

    List<Map<String, dynamic>> rows = [];

    // Save child items (items with parentId)
    for (var item in _specialFeeItems) {
      final id = item['id'] as int;
      final parentId = item['parentId'];

      // Skip parent categories - only save child items
      if (parentId == null) continue;

      final ctrl = _amountCtrl[id];

      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        final amount = double.tryParse(ctrl.text.trim()) ?? 0;

        rows.add({
          'classId': _selectedClassId,
          'specialFeeItemId': id,
          'amount': amount,
          'term': _activeTerm,
          'session': sessionVal,
        });
      }
    }

    // Also save standalone items
    for (var item in _standaloneItems) {
      final id = item['id'] as int;
      final ctrl = _amountCtrl[id];

      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        final amount = double.tryParse(ctrl.text.trim()) ?? 0;

        rows.add({
          'classId': _selectedClassId,
          'specialFeeItemId': id,
          'amount': amount,
          'term': _activeTerm,
          'session': sessionVal,
        });
      }
    }

    // Save the special class fees
    await _db.replaceSpecialClassFeesFor(
      _selectedClassId!,
      _activeTerm!,
      sessionVal,
      rows,
      armId: _selectedArmId,
    );

    if (!mounted) return;

    final className = _classes.firstWhere(
      (c) => c['id'] == _selectedClassId,
      orElse: () => {'name': 'Unknown'},
    )['name'];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Special fees saved for $className'),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context, true);
  }

  // -----------------------------------------------------------
  // SAVE TO DATABASE - MULTIPLE CLASS/ARM TARGETS AT ONCE
  // -----------------------------------------------------------
  Future<void> _saveMultiAssignments() async {
    if (_selectedTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select at least one class/arm"),
        ),
      );
      return;
    }

    final sessionVal = _activeSession ?? "";

    // Build the special fee template once - shared by every target
    final feeTemplate = <Map<String, dynamic>>[];

    for (var item in _specialFeeItems) {
      final id = item['id'] as int;
      final parentId = item['parentId'];
      if (parentId == null) continue; // skip category headers

      final ctrl = _amountCtrl[id];
      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        final amount = double.tryParse(ctrl.text.trim()) ?? 0;
        feeTemplate.add({'specialFeeItemId': id, 'amount': amount});
      }
    }

    for (var item in _standaloneItems) {
      final id = item['id'] as int;
      final ctrl = _amountCtrl[id];
      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        final amount = double.tryParse(ctrl.text.trim()) ?? 0;
        feeTemplate.add({'specialFeeItemId': id, 'amount': amount});
      }
    }

    if (feeTemplate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter at least one special fee amount"),
        ),
      );
      return;
    }

    final targets = _selectedTargets.map((key) {
      final parts = key.split(':');
      return {
        'classId': int.parse(parts[0]),
        'armId': parts.length > 1 ? int.parse(parts[1]) : null,
      };
    }).toList();

    setState(() => _loading = true);

    final updatedNames = <String>[];

    for (var t in targets) {
      final classId = t['classId'] as int;
      final armId = t['armId'];

      final rows = feeTemplate
          .map((f) => {
                'classId': classId,
                'specialFeeItemId': f['specialFeeItemId'],
                'amount': f['amount'],
                'term': _activeTerm,
                'session': sessionVal,
              })
          .toList();

      await _db.replaceSpecialClassFeesFor(
        classId,
        _activeTerm!,
        sessionVal,
        rows,
        armId: armId,
      );

      final className = _classes.firstWhere(
        (c) => c['id'] == classId,
        orElse: () => {'name': 'Unknown'},
      )['name'];

      final armName = armId != null
          ? (_armsByClass[classId]
              ?.firstWhere((a) => a['id'] == armId, orElse: () => {'name': ''})['name'])
          : null;

      updatedNames.add(
        (armName != null && armName != '') ? '$className $armName' : className,
      );
    }

    if (!mounted) return;
    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Special fees saved for ${updatedNames.length} class/arm(s): '
          '${updatedNames.join(", ")}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );

    Navigator.pop(context, true);
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,##0', 'en_US');
    return formatter.format(amount);
  }

  @override
  void dispose() {
    for (var ctrl in _amountCtrl.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // -----------------------------------------------------------
  // UI
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final grandTotal = _regularTotal + _specialTotal;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Assign Special Fees to Class"),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ACTIVE TERM/SESSION DISPLAY
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
                            Icon(Icons.person_add_alt_1,
                                color: Colors.deepOrange.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              'New Intake Bill Assignment',
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
                            Icon(Icons.event,
                                size: 18, color: Colors.deepOrange.shade700),
                            const SizedBox(width: 8),
                            const Text('Term: '),
                            Text(
                              _activeTerm ?? 'Not set',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 18, color: Colors.deepOrange.shade700),
                            const SizedBox(width: 8),
                            const Text('Session: '),
                            Text(
                              _activeSession ?? 'Not set',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // MULTI CLASS/ARM MODE TOGGLE
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.deepOrange.shade200),
                  ),
                  child: SwitchListTile(
                    value: _applyToMultiple,
                    activeThumbColor: Colors.deepOrange,
                    onChanged: (val) {
                      setState(() {
                        _applyToMultiple = val;
                        if (!val) _selectedTargets.clear();
                      });
                    },
                    title: const Text(
                      'Apply Same Special Fees to Multiple Classes/Arms',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Enter the special fee amounts once below, then pick every '
                      'class/arm that should get them - no need to repeat this for each one.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                if (!_applyToMultiple) ...[
                // CLASS SELECT
                const Text(
                  "Select Class",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                DropdownButtonFormField<int>(
                  initialValue: _selectedClassId,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.school),
                    hintText: 'Choose a class',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _classes
                      .map((c) => DropdownMenuItem<int>(
                            value: c['id'] as int,
                            child: Text(c['name'] as String),
                          ))
                      .toList(),
                  onChanged: _onClassChanged,
                ),

                const SizedBox(height: 16),

                // ARM SELECT
                if (_selectedClassId != null && _arms.isNotEmpty) ...[
                  const Text(
                    "Select Arm",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  _loadingArms
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : DropdownButtonFormField<int>(
                          initialValue: _selectedArmId,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.class_),
                            hintText: 'Choose an arm',
                            filled: true,
                            fillColor: Colors.orange.shade50,
                          ),
                          items: _arms
                              .map((a) => DropdownMenuItem<int>(
                                    value: a['id'] as int,
                                    child: Text(a['name'] as String),
                                  ))
                              .toList(),
                          onChanged: _onArmChanged,
                        ),

                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 24),

                // REGULAR FEES SECTION
                if (_selectedClassId != null) ...[
                  Row(
                    children: [
                      Icon(Icons.list_alt, color: Colors.grey.shade600, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Default Fees (${_regularFeeItems.length - _excludedDefaultFeeIds.length}/${_regularFeeItems.length})",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      if (_excludedDefaultFeeIds.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${_excludedDefaultFeeIds.length} excluded',
                            style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Click trash to exclude',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),

                  if (_regularFeeItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey.shade500),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No default fees assigned to this class yet.\nAssign fees in Fee Items → Assign Fees to Class.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  ..._regularFeeItems.map((fee) {
                    final feeId = fee['id'] as int;
                    final name = fee['feeItemName'] ?? 'Unknown';
                    final amount = (fee['amount'] as num?)?.toDouble() ?? 0;
                    final isExcluded = _excludedDefaultFeeIds.contains(feeId);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isExcluded ? Colors.red.shade50 : Colors.grey.shade100,
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isExcluded ? Colors.red.shade200 : Colors.grey.shade300,
                              radius: 18,
                              child: Icon(
                                isExcluded ? Icons.remove_circle : Icons.attach_money,
                                color: isExcluded ? Colors.red.shade700 : Colors.grey.shade600,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: isExcluded ? Colors.grey.shade500 : Colors.grey.shade700,
                                      decoration: isExcluded ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                  if (isExcluded)
                                    Text(
                                      'Excluded from new intake',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red.shade400,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '₦${_formatCurrency(amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isExcluded ? Colors.grey.shade400 : Colors.grey.shade600,
                                decoration: isExcluded ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Delete/Restore button
                            IconButton(
                              onPressed: () => isExcluded
                                  ? _restoreDefaultFee(feeId)
                                  : _removeDefaultFee(feeId, name),
                              icon: Icon(
                                isExcluded ? Icons.undo : Icons.delete_outline,
                                color: isExcluded ? Colors.green.shade600 : Colors.red.shade400,
                                size: 22,
                              ),
                              tooltip: isExcluded ? 'Restore fee' : 'Remove from new intake',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // Regular fees subtotal
                  if (_regularFeeItems.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Default Fees Subtotal:',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            '₦${_formatCurrency(_regularTotal)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),
                ],
                ] else
                  _buildMultiTargetSelector(),

                const SizedBox(height: 8),

                // SPECIAL FEES SECTION (EDITABLE) - Hierarchical View
                Row(
                  children: [
                    Icon(Icons.star, color: Colors.deepOrange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "Special Fees (${_categories.length + _standaloneItems.length} items)",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Editable',
                        style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade700),
                      ),
                    ),
                  ],
                ),
                const Divider(),

                if (_categories.isEmpty && _standaloneItems.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No special fee items for this term/session',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create special fee items first',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Standalone Items Section
                if (_standaloneItems.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long, size: 18, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Standalone Items (${_standaloneItems.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._standaloneItems.map((item) {
                    final id = item['id'] as int;
                    final name = item['name'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Icon(Icons.receipt, color: Colors.orange.shade700, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Default: ₦${_formatCurrency(item['defaultAmount'] ?? 0)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                controller: _amountCtrl[id],
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: "Amount",
                                  border: const OutlineInputBorder(),
                                  prefixText: '₦',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.orange.shade400, width: 2),
                                  ),
                                ),
                                onChanged: (_) => _recalculateTotal(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],

                // Categories Section Header
                if (_categories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.folder_special, size: 18, color: Colors.deepOrange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Categories (${_categories.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepOrange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Category cards with expandable children
                ..._categories.map((parent) {
                  final parentId = parent['id'] as int;
                  final parentName = parent['name'] ?? '';
                  final children = _childItemsMap[parentId] ?? [];
                  final isExpanded = _expandedCategories.contains(parentId);
                  final categorySubtotal = _getCategorySubtotal(parentId);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isExpanded
                            ? Colors.deepOrange.shade300
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Category header (clickable to expand/collapse)
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedCategories.remove(parentId);
                              } else {
                                _expandedCategories.add(parentId);
                              }
                            });
                          },
                          borderRadius: BorderRadius.vertical(
                            top: const Radius.circular(12),
                            bottom: isExpanded
                                ? Radius.zero
                                : const Radius.circular(12),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.shade50,
                              borderRadius: BorderRadius.vertical(
                                top: const Radius.circular(12),
                                bottom: isExpanded
                                    ? Radius.zero
                                    : const Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.deepOrange.shade200,
                                  radius: 18,
                                  child: Icon(
                                    Icons.folder,
                                    color: Colors.deepOrange.shade800,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        parentName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.deepOrange.shade900,
                                        ),
                                      ),
                                      Text(
                                        '${children.length} item${children.length == 1 ? '' : 's'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.deepOrange.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Category subtotal
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.deepOrange.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '₦${_formatCurrency(categorySubtotal)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.deepOrange.shade800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: Colors.deepOrange.shade700,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Children items (visible when expanded)
                        if (isExpanded && children.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              ),
                            ),
                            child: Column(
                              children: children.map((child) {
                                final childId = child['id'] as int;
                                final childName = child['name'] ?? '';

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: Colors.deepOrange.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                          Icons.subdirectory_arrow_right,
                                          size: 16,
                                          color: Colors.deepOrange.shade400,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              childName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Text(
                                              'Default: ₦${_formatCurrency(child['defaultAmount'] ?? 0)}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 110,
                                        child: TextField(
                                          controller: _amountCtrl[childId],
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: "Amount",
                                            border: const OutlineInputBorder(),
                                            prefixText: '₦',
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color: Colors.deepOrange.shade400,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                          onChanged: (_) => _recalculateTotal(),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                        // Empty children message
                        if (isExpanded && children.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'No items in this category',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // SPECIAL FEES SUBTOTAL
                if (_specialFeeItems.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.deepOrange.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.deepOrange.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              "Special Fees Subtotal:",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          "₦${_formatCurrency(_specialTotal)}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.deepOrange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // GRAND TOTAL DISPLAY
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300, width: 2),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calculate, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                "New Intake Total:",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            "₦${_formatCurrency(grandTotal)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '(Default: ₦${_formatCurrency(_regularTotal)} + Special: ₦${_formatCurrency(_specialTotal)})',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                // SAVE BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _specialFeeItems.isEmpty
                        ? null
                        : (_applyToMultiple
                            ? (_selectedTargets.isEmpty ? null : _saveMultiAssignments)
                            : (_selectedClassId == null ? null : _saveAssignments)),
                    icon: const Icon(Icons.save),
                    label: Text(
                      _applyToMultiple
                          ? "APPLY TO SELECTED CLASSES/ARMS"
                          : "SAVE SPECIAL FEE ASSIGNMENTS",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Help text
                if (_applyToMultiple && _selectedTargets.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Select at least one class/arm to apply these special fees to',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (!_applyToMultiple && _selectedClassId == null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Select a class to assign special fees for new intake students',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  // -----------------------------------------------------------
  // MULTI CLASS/ARM TARGET SELECTOR
  // -----------------------------------------------------------
  Widget _buildMultiTargetSelector() {
    int totalTargets = 0;
    for (var c in _classes) {
      final arms = _armsByClass[c['id']] ?? [];
      totalTargets += arms.isEmpty ? 1 : arms.length;
    }

    final allSelected = totalTargets > 0 && _selectedTargets.length == totalTargets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                "Select Classes/Arms",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: _classes.isEmpty
                  ? null
                  : () {
                      setState(() {
                        if (allSelected) {
                          _selectedTargets.clear();
                        } else {
                          _selectedTargets.clear();
                          for (var c in _classes) {
                            final classId = c['id'] as int;
                            final arms = _armsByClass[classId] ?? [];
                            if (arms.isEmpty) {
                              _selectedTargets.add('$classId');
                            } else {
                              for (var a in arms) {
                                _selectedTargets.add('$classId:${a['id']}');
                              }
                            }
                          }
                        }
                      });
                    },
              icon: Icon(allSelected ? Icons.deselect : Icons.select_all, size: 18),
              label: Text(allSelected ? 'Clear All' : 'Select All'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_selectedTargets.length} of $totalTargets selected',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _classes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No classes found'),
                )
              : Column(
                  children: _classes.map((c) => _buildClassTargetGroup(c)).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildClassTargetGroup(Map<String, dynamic> classData) {
    final classId = classData['id'] as int;
    final className = classData['name'] as String? ?? '';
    final arms = _armsByClass[classId] ?? [];

    if (arms.isEmpty) {
      final key = '$classId';
      return CheckboxListTile(
        dense: true,
        title: Text(className),
        value: _selectedTargets.contains(key),
        onChanged: (val) {
          setState(() {
            if (val == true) {
              _selectedTargets.add(key);
            } else {
              _selectedTargets.remove(key);
            }
          });
        },
      );
    }

    final armKeys = arms.map((a) => '$classId:${a['id']}').toList();
    final selectedCount = armKeys.where(_selectedTargets.contains).length;
    final allArmsSelected = selectedCount == armKeys.length;
    final someArmsSelected = selectedCount > 0 && !allArmsSelected;

    return ExpansionTile(
      title: Row(
        children: [
          Checkbox(
            value: allArmsSelected ? true : (someArmsSelected ? null : false),
            tristate: true,
            onChanged: (val) {
              setState(() {
                if (allArmsSelected) {
                  _selectedTargets.removeAll(armKeys);
                } else {
                  _selectedTargets.addAll(armKeys);
                }
              });
            },
          ),
          Expanded(child: Text(className)),
        ],
      ),
      children: arms.map((a) {
        final armId = a['id'] as int;
        final armName = a['name'] as String? ?? '';
        final key = '$classId:$armId';
        return Padding(
          padding: const EdgeInsets.only(left: 24),
          child: CheckboxListTile(
            dense: true,
            title: Text(armName),
            value: _selectedTargets.contains(key),
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedTargets.add(key);
                } else {
                  _selectedTargets.remove(key);
                }
              });
            },
          ),
        );
      }).toList(),
    );
  }
}

