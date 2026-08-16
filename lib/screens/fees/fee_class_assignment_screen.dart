import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';

class FeeClassAssignmentScreen extends StatefulWidget {
  const FeeClassAssignmentScreen({super.key});

  @override
  State<FeeClassAssignmentScreen> createState() =>
      _FeeClassAssignmentScreenState();
}

class _FeeClassAssignmentScreenState extends State<FeeClassAssignmentScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  List<Map<String, dynamic>> _feeItems = [];

  String? _activeTerm;
  String? _activeSession;
  int? _selectedClassId;
  int? _selectedArmId;

  final Map<int, TextEditingController> _amountCtrl = {};
  bool _loading = true;
  bool _loadingArms = false;
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // -----------------------------------------------------------
  // LOAD ACTIVE TERM/SESSION + CLASSES + FEE ITEMS
  // -----------------------------------------------------------
  Future<void> _load() async {
    setState(() => _loading = true);

    _activeTerm = await _db.getActiveTerm();
    _activeSession =
        (await _db.getActiveSession())?['sessionName'] ?? "";

    _classes = await _db.getClasses();
    _feeItems = await _db.getFeeItems(
      term: _activeTerm,
      session: _activeSession,
    );

    _amountCtrl.clear();

    for (var item in _feeItems) {
      final id = item['id'] as int;
      final defaultAmount = (item['defaultAmount'] ?? 0);

      // Only set text if amount > 0, otherwise leave empty to avoid user mistakes
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
      _selectedArmId = null; // Reset arm selection
      _arms = [];
      _loadingArms = true;
    });

    // Load arms for this class
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

      // If there's only one arm or no arms, auto-load fees for the class
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

    final rows = await _db.getClassFees(
      _selectedClassId!,
      _activeTerm ?? "",
      _activeSession ?? "",
      armId: _selectedArmId,
    );

    debugPrint('📋 Loading fees for class $_selectedClassId: ${rows.length} existing fee assignments found');

    for (var item in _feeItems) {
      final id = item['id'] as int;

      // Find matching fee assignment - ensure proper type comparison
      Map<String, dynamic>? match;
      for (var row in rows) {
        final rowFeeItemId = row['feeItemId'];
        if (rowFeeItemId is int && rowFeeItemId == id) {
          match = row;
          break;
        } else if (rowFeeItemId != null && rowFeeItemId.toString() == id.toString()) {
          match = row;
          break;
        }
      }

      // Get amount from existing assignment or use default
      double amount = 0.0;
      if (match != null && match.isNotEmpty) {
        final matchAmount = match['amount'];
        if (matchAmount is num) {
          amount = matchAmount.toDouble();
        } else if (matchAmount != null) {
          amount = double.tryParse(matchAmount.toString()) ?? 0.0;
        }
        debugPrint('   Fee item $id: Found existing amount = $amount');
      } else {
        final defaultAmount = item['defaultAmount'];
        if (defaultAmount is num) {
          amount = defaultAmount.toDouble();
        } else if (defaultAmount != null) {
          amount = double.tryParse(defaultAmount.toString()) ?? 0.0;
        }
        debugPrint('   Fee item $id: Using default amount = $amount');
      }

      // Set text field - show existing amounts (including 0 for transparency)
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

    for (var item in _feeItems) {
      final id = item['id'] as int;
      final ctrl = _amountCtrl[id];
      if (ctrl == null) continue;

      final amount = double.tryParse(ctrl.text.trim()) ?? 0;
      t += amount;
    }

    setState(() => _total = t);
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

    // If class has arms, require arm selection
    if (_arms.isNotEmpty && _selectedArmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an arm")),
      );
      return;
    }

    final sessionVal = _activeSession ?? "";

    List<Map<String, dynamic>> rows = [];

    for (var item in _feeItems) {
      final id = item['id'] as int;
      final ctrl = _amountCtrl[id];

      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        final amount = double.tryParse(ctrl.text.trim()) ?? 0;

        rows.add({
          'classId': _selectedClassId,
          'feeItemId': id,
          'amount': amount,
          'term': _activeTerm,
          'session': sessionVal,
        });
      }
    }

    // CHECK FOR NEW FEE ITEMS, CHANGED FEES, AND CUSTOM ADJUSTMENTS
    debugPrint('💾 Saving class fees - checking for changes...');

    // Get existing class fees to detect new and changed items
    final existingClassFees = await _db.getClassFees(
      _selectedClassId!,
      _activeTerm!,
      sessionVal,
      armId: _selectedArmId,
    );

    // Build map of existing fees: feeItemId -> amount
    final existingFeesMap = <int, double>{};
    for (var fee in existingClassFees) {
      final feeItemId = fee['feeItemId'] as int;
      final amount = (fee['amount'] as num).toDouble();
      existingFeesMap[feeItemId] = amount;
    }

    // Identify NEW fees (not in existing class fees)
    final newFeeItems = rows.where((r) =>
      !existingFeesMap.containsKey(r['feeItemId'])
    ).toList();

    // Identify CHANGED fees (existing but with different amount)
    final changedFeeItems = <Map<String, dynamic>>[];
    for (var row in rows) {
      final feeItemId = row['feeItemId'] as int;
      final newAmount = (row['amount'] as num).toDouble();

      if (existingFeesMap.containsKey(feeItemId)) {
        final oldAmount = existingFeesMap[feeItemId]!;
        if ((newAmount - oldAmount).abs() > 0.01) {
          changedFeeItems.add({
            ...row,
            'oldAmount': oldAmount,
            'newAmount': newAmount,
          });
        }
      }
    }

    debugPrint('   Existing fee items: ${existingFeesMap.length}');
    debugPrint('   New fee items: ${newFeeItems.length}');
    debugPrint('   Changed fee items: ${changedFeeItems.length}');

    final customAdjustments = await _checkForCustomAdjustments(
      _selectedClassId!,
      _activeTerm!,
      sessionVal,
      rows,
      armId: _selectedArmId,
    );

    String saveAction = 'full'; // 'full', 'addNewOnly', 'updateChangedOnly', or 'cancel'

    if (customAdjustments > 0) {
      debugPrint('⚠️  $customAdjustments students have custom adjustments');

      // Build fee names for dialog
      final newFeeNames = newFeeItems.map((f) {
        final feeItem = _feeItems.firstWhere(
          (item) => item['id'] == f['feeItemId'],
          orElse: () => {'name': 'Unknown'},
        );
        return feeItem['name'] as String? ?? 'Unknown';
      }).toList();

      final changedFeeDetails = changedFeeItems.map((f) {
        final feeItem = _feeItems.firstWhere(
          (item) => item['id'] == f['feeItemId'],
          orElse: () => {'name': 'Unknown'},
        );
        final name = feeItem['name'] as String? ?? 'Unknown';
        final oldAmt = (f['oldAmount'] as num).toStringAsFixed(0);
        final newAmt = (f['newAmount'] as num).toStringAsFixed(0);
        return '$name: ₦$oldAmt → ₦$newAmt';
      }).toList();

      // Show dialog with options
      saveAction = await _showSaveOptionsDialog(
        customAdjustments,
        newFeeItems.length,
        newFeeNames,
        changedFeeItems.length,
        changedFeeDetails,
      );

      if (saveAction == 'cancel') {
        debugPrint('❌ User cancelled');
        return;
      }
    }

    // Handle "Add New Only" action
    if (saveAction == 'addNewOnly' && newFeeItems.isNotEmpty) {
      debugPrint('✓ Adding new fees only (preserving custom adjustments)');

      // Add new items to class_fees table
      for (var newFee in newFeeItems) {
        await _db.insertClassFee(newFee);
      }

      // Add new fees to existing student bills
      final addedCount = await _addNewFeesToStudentBills(
        _selectedClassId!,
        _activeTerm!,
        sessionVal,
        newFeeItems,
        armId: _selectedArmId,
      );

      if (!mounted) return;

      final className = _classes.firstWhere(
        (c) => c['id'] == _selectedClassId,
        orElse: () => {'name': 'Unknown'},
      )['name'];

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${newFeeItems.length} new fee(s) to $className\n'
            'Updated $addedCount student bill(s)',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      Navigator.pop(context, true);
      return;
    }

    // Handle "Update Changed Only" action
    if (saveAction == 'updateChangedOnly' && (changedFeeItems.isNotEmpty || newFeeItems.isNotEmpty)) {
      debugPrint('✓ Updating changed fees only (preserving other custom adjustments)');

      // Update class_fees table with new amounts
      await _db.replaceClassFeesFor(
        _selectedClassId!,
        _activeTerm!,
        sessionVal,
        rows,
        armId: _selectedArmId,
      );

      // Update only the changed and new fees in student bills
      final updatedCount = await _updateChangedFeesInStudentBills(
        _selectedClassId!,
        _activeTerm!,
        sessionVal,
        changedFeeItems,
        newFeeItems,
        armId: _selectedArmId,
      );

      if (!mounted) return;

      final className = _classes.firstWhere(
        (c) => c['id'] == _selectedClassId,
        orElse: () => {'name': 'Unknown'},
      )['name'];

      final changesSummary = <String>[];
      if (changedFeeItems.isNotEmpty) {
        changesSummary.add('${changedFeeItems.length} fee(s) updated');
      }
      if (newFeeItems.isNotEmpty) {
        changesSummary.add('${newFeeItems.length} new fee(s) added');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${changesSummary.join(", ")} for $className\n'
            'Updated $updatedCount student bill(s)',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      Navigator.pop(context, true);
      return;
    }

    // Full replacement
    debugPrint('✓ Proceeding with full fee replacement');
    await _db.replaceClassFeesFor(
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

    final armName = _selectedArmId != null
        ? _arms.firstWhere(
            (a) => a['id'] == _selectedArmId,
            orElse: () => {'name': ''},
          )['name']
        : null;

    final displayName = armName != null ? '$className $armName' : className;

    // AUTO-GENERATE BILLS FOR ALL STUDENTS IN THIS CLASS/ARM
    try {
      final studentsCount = await _autoGenerateBillsForClass(
        _selectedClassId!,
        _activeTerm!,
        sessionVal,
        rows,
        armId: _selectedArmId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fees saved for $displayName\n'
            'Bills auto-generated for $studentsCount student(s)',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fees saved for $displayName\n'
            'Warning: Bill generation failed: $e',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }

    Navigator.pop(context, true);
  }

  // -----------------------------------------------------------
  // CHECK FOR CUSTOM ADJUSTMENTS
  // -----------------------------------------------------------
  Future<int> _checkForCustomAdjustments(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> newFeeRows, {
    int? armId,
  }) async {
    final db = await _db.database;

    // Get all students in this class/arm with existing bills
    String query = '''
      SELECT
        s.id as studentId,
        b.id as billId
      FROM students s
      INNER JOIN student_bills b ON s.id = b.studentId
      WHERE s.classId = ?
        AND s.isActive = 1
        AND b.term = ?
        AND b.session = ?
    ''';

    List<dynamic> queryArgs = [classId, term, session];

    if (armId != null) {
      query += ' AND s.armId = ?';
      queryArgs.add(armId);
    }

    final results = await db.rawQuery(query, queryArgs);

    debugPrint('🔍 Custom Adjustment Check:');
    debugPrint('   Found ${results.length} students with existing bills');
    debugPrint('   ClassId: $classId, Term: $term, Session: $session');

    int customCount = 0;

    for (var row in results) {
      final billId = row['billId'] as int;
      final studentId = row['studentId'] as int;

      // Get the actual fee breakdown for this student's bill
      final breakdown = await db.query(
        'student_fee_breakdown',
        where: 'billId = ?',
        whereArgs: [billId],
      );

      debugPrint('   Student $studentId: ${breakdown.length} fee items in breakdown');

      // Check if this bill has custom adjustments by comparing with new class fees
      if (_hasCustomAdjustments(breakdown, newFeeRows)) {
        customCount++;
        debugPrint('   ✓ Student $studentId has custom adjustments');
      }
    }

    debugPrint('   Total students with custom adjustments: $customCount');
    return customCount;
  }

  // -----------------------------------------------------------
  // CHECK IF A BILL HAS CUSTOM ADJUSTMENTS
  // -----------------------------------------------------------
  bool _hasCustomAdjustments(
    List<Map<String, dynamic>> currentBreakdown,
    List<Map<String, dynamic>> newClassFees,
  ) {
    // Check if number of fee items is different
    if (currentBreakdown.length != newClassFees.length) {
      debugPrint('      → Different number of items: ${currentBreakdown.length} vs ${newClassFees.length}');
      return true; // Student has additional or fewer fee items
    }

    // Create a map of feeItemId -> amount for easy comparison
    final currentFeesMap = <int, double>{};
    for (var item in currentBreakdown) {
      final feeItemId = item['feeItemId'] as int;
      final amount = (item['amount'] as num).toDouble();
      currentFeesMap[feeItemId] = amount;
    }

    // Check if all class fees match the student's bill
    for (var classFee in newClassFees) {
      final feeItemId = classFee['feeItemId'] as int;
      final expectedAmount = (classFee['amount'] as num).toDouble();

      // Check if this fee exists in the student's bill
      if (!currentFeesMap.containsKey(feeItemId)) {
        debugPrint('      → Missing fee item: $feeItemId');
        return true; // Student's bill is missing this fee item
      }

      final currentAmount = currentFeesMap[feeItemId]!;

      // Check if amount differs (allow small difference for floating point precision)
      if ((currentAmount - expectedAmount).abs() > 0.01) {
        debugPrint('      → Amount differs for fee $feeItemId: ₦$currentAmount vs ₦$expectedAmount');
        return true; // Amount has been customized
      }
    }

    // Check if student has any fee items not in the class fees
    final classFeeIds = newClassFees.map((f) => f['feeItemId'] as int).toSet();
    for (var feeItemId in currentFeesMap.keys) {
      if (!classFeeIds.contains(feeItemId)) {
        debugPrint('      → Extra fee item: $feeItemId');
        return true; // Student has additional fee items (special charges, etc.)
      }
    }

    return false; // No custom adjustments detected
  }

  // -----------------------------------------------------------
  // SHOW SAVE OPTIONS DIALOG
  // -----------------------------------------------------------
  Future<String> _showSaveOptionsDialog(
    int affectedCount,
    int newFeeCount,
    List<String> newFeeNames,
    int changedFeeCount,
    List<String> changedFeeDetails,
  ) async {
    final hasNewFees = newFeeCount > 0;
    final hasChangedFees = changedFeeCount > 0;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 32),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Custom Adjustments Detected',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Affected students info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$affectedCount student(s) have custom bill adjustments',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Changed fees info (if any)
              if (hasChangedFees) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit, color: Colors.purple.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Fee amount(s) changed:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...changedFeeDetails.map((detail) => Padding(
                        padding: const EdgeInsets.only(left: 28, bottom: 4),
                        child: Text(
                          '• $detail',
                          style: TextStyle(color: Colors.purple.shade800, fontSize: 13),
                        ),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // New fees info (if any)
              if (hasNewFees) ...[
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
                          Icon(Icons.add_circle, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'New fee(s) being added:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...newFeeNames.map((name) => Padding(
                        padding: const EdgeInsets.only(left: 28, bottom: 4),
                        child: Text(
                          '• $name',
                          style: TextStyle(color: Colors.blue.shade800),
                        ),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              const Text(
                'How would you like to proceed?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Option 1: Update Changed & Add New Only (if there are changes)
              if (hasChangedFees || hasNewFees)
                _buildOptionCard(
                  icon: Icons.edit_note,
                  color: Colors.green,
                  title: hasChangedFees && hasNewFees
                      ? 'Update Changed & Add New Only'
                      : hasChangedFees
                          ? 'Update Changed Fees Only'
                          : 'Add New Fees Only',
                  description: hasChangedFees && hasNewFees
                      ? 'Update the changed fees and add new ones.\nOther custom adjustments will be preserved.'
                      : hasChangedFees
                          ? 'Only update the fees that changed.\nOther custom adjustments will be preserved.'
                          : 'Only add the new fee item(s) to student bills.\nExisting custom amounts will be preserved.',
                  onTap: () => Navigator.pop(context, hasChangedFees ? 'updateChangedOnly' : 'addNewOnly'),
                ),

              if (hasChangedFees || hasNewFees) const SizedBox(height: 12),

              // Option 2: Override All
              _buildOptionCard(
                icon: Icons.sync,
                color: Colors.orange,
                title: 'Override All',
                description: 'Replace all fees with the new class fee structure.\nAll custom adjustments will be lost.',
                onTap: () => Navigator.pop(context, 'full'),
              ),

              const SizedBox(height: 12),

              // Option 3: Cancel
              _buildOptionCard(
                icon: Icons.cancel,
                color: Colors.grey,
                title: 'Cancel',
                description: 'Don\'t save any changes.',
                onTap: () => Navigator.pop(context, 'cancel'),
              ),
            ],
          ),
        ),
      ),
    );

    return result ?? 'cancel';
  }

  Widget _buildOptionCard({
    required IconData icon,
    required MaterialColor color,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, color: color.shade700, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: color.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: color.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.shade400),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // ADD NEW FEES TO EXISTING STUDENT BILLS
  // -----------------------------------------------------------
  Future<int> _addNewFeesToStudentBills(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> newFeeItems, {
    int? armId,
  }) async {
    final db = await _db.database;

    // Get all students in this class/arm with existing bills
    String query = '''
      SELECT
        s.id as studentId,
        b.id as billId,
        b.totalAmount as currentTotal
      FROM students s
      INNER JOIN student_bills b ON s.id = b.studentId
      WHERE s.classId = ?
        AND s.isActive = 1
        AND b.term = ?
        AND b.session = ?
    ''';

    List<dynamic> queryArgs = [classId, term, session];

    if (armId != null) {
      query += ' AND s.armId = ?';
      queryArgs.add(armId);
    }

    final results = await db.rawQuery(query, queryArgs);

    debugPrint('📝 Adding new fees to ${results.length} student bills');

    int updatedCount = 0;

    for (var row in results) {
      final billId = row['billId'] as int;
      final currentTotal = (row['currentTotal'] as num).toDouble();

      double additionalAmount = 0.0;

      // Add each new fee item to the student's breakdown
      for (var newFee in newFeeItems) {
        final feeItemId = newFee['feeItemId'] as int;
        final amount = (newFee['amount'] as num).toDouble();

        // Check if this fee already exists in the breakdown
        final existing = await db.query(
          'student_fee_breakdown',
          where: 'billId = ? AND feeItemId = ?',
          whereArgs: [billId, feeItemId],
        );

        if (existing.isEmpty) {
          // Add the new fee to breakdown
          await db.insert('student_fee_breakdown', {
            'billId': billId,
            'feeItemId': feeItemId,
            'amount': amount,
          });
          additionalAmount += amount;
          debugPrint('   Added fee $feeItemId (₦$amount) to bill $billId');
        }
      }

      // Update the bill total if new fees were added
      if (additionalAmount > 0) {
        final newTotal = currentTotal + additionalAmount;
        await db.update(
          'student_bills',
          {'totalAmount': newTotal},
          where: 'id = ?',
          whereArgs: [billId],
        );
        updatedCount++;
        debugPrint('   Updated bill $billId total: ₦$currentTotal → ₦$newTotal');
      }
    }

    return updatedCount;
  }

  // -----------------------------------------------------------
  // UPDATE CHANGED FEES IN EXISTING STUDENT BILLS
  // -----------------------------------------------------------
  Future<int> _updateChangedFeesInStudentBills(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> changedFeeItems,
    List<Map<String, dynamic>> newFeeItems, {
    int? armId,
  }) async {
    final db = await _db.database;

    // Get all students in this class/arm with existing bills
    String query = '''
      SELECT
        s.id as studentId,
        b.id as billId,
        b.totalAmount as currentTotal
      FROM students s
      INNER JOIN student_bills b ON s.id = b.studentId
      WHERE s.classId = ?
        AND s.isActive = 1
        AND b.term = ?
        AND b.session = ?
    ''';

    List<dynamic> queryArgs = [classId, term, session];

    if (armId != null) {
      query += ' AND s.armId = ?';
      queryArgs.add(armId);
    }

    final results = await db.rawQuery(query, queryArgs);

    debugPrint('📝 Updating changed fees for ${results.length} student bills');

    int updatedCount = 0;

    for (var row in results) {
      final billId = row['billId'] as int;
      final currentTotal = (row['currentTotal'] as num).toDouble();

      double totalDifference = 0.0;

      // Update each changed fee item in the student's breakdown
      for (var changedFee in changedFeeItems) {
        final feeItemId = changedFee['feeItemId'] as int;
        final oldAmount = (changedFee['oldAmount'] as num).toDouble();
        final newAmount = (changedFee['newAmount'] as num).toDouble();

        // Check if this fee exists in the breakdown
        final existing = await db.query(
          'student_fee_breakdown',
          where: 'billId = ? AND feeItemId = ?',
          whereArgs: [billId, feeItemId],
        );

        if (existing.isNotEmpty) {
          final currentAmount = (existing.first['amount'] as num).toDouble();

          // Only update if the student had the OLD standard amount (not customized)
          // Allow small tolerance for floating point comparison
          if ((currentAmount - oldAmount).abs() < 0.01) {
            await db.update(
              'student_fee_breakdown',
              {'amount': newAmount},
              where: 'billId = ? AND feeItemId = ?',
              whereArgs: [billId, feeItemId],
            );
            totalDifference += (newAmount - oldAmount);
            debugPrint('   Updated fee $feeItemId: ₦$oldAmount → ₦$newAmount for bill $billId');
          } else {
            debugPrint('   Skipped fee $feeItemId for bill $billId (custom amount: ₦$currentAmount)');
          }
        }
      }

      // Add new fee items
      for (var newFee in newFeeItems) {
        final feeItemId = newFee['feeItemId'] as int;
        final amount = (newFee['amount'] as num).toDouble();

        // Check if this fee already exists in the breakdown
        final existing = await db.query(
          'student_fee_breakdown',
          where: 'billId = ? AND feeItemId = ?',
          whereArgs: [billId, feeItemId],
        );

        if (existing.isEmpty) {
          await db.insert('student_fee_breakdown', {
            'billId': billId,
            'feeItemId': feeItemId,
            'amount': amount,
          });
          totalDifference += amount;
          debugPrint('   Added new fee $feeItemId (₦$amount) to bill $billId');
        }
      }

      // Update the bill total if there were changes
      if (totalDifference.abs() > 0.01) {
        final newTotal = currentTotal + totalDifference;
        await db.update(
          'student_bills',
          {'totalAmount': newTotal},
          where: 'id = ?',
          whereArgs: [billId],
        );
        updatedCount++;
        debugPrint('   Updated bill $billId total: ₦$currentTotal → ₦$newTotal');
      }
    }

    return updatedCount;
  }

  // -----------------------------------------------------------
  // AUTO-GENERATE BILLS FOR ALL STUDENTS IN CLASS/ARM
  // -----------------------------------------------------------
  Future<int> _autoGenerateBillsForClass(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> feeRows, {
    int? armId,
  }) async {
    // Get all active students in this class (and arm if specified)
    final db = await _db.database;

    String whereClause = 'classId = ? AND isActive = 1';
    List<dynamic> whereArgs = [classId];

    if (armId != null) {
      whereClause += ' AND armId = ?';
      whereArgs.add(armId);
    }

    final students = await db.query(
      'students',
      where: whereClause,
      whereArgs: whereArgs,
    );

    if (students.isEmpty) return 0;

    int generatedCount = 0;

    for (final student in students) {
      final studentId = student['id'] as int;

      // Calculate previous balance
      final previousBalance = await _db.computeOutstandingBeforeTerm(
        studentId,
        term: term,
        session: session,
      );

      // Calculate total amount from fee rows
      final subtotal = feeRows.fold<double>(
        0.0,
        (sum, fee) => sum + ((fee['amount'] as num?)?.toDouble() ?? 0.0),
      );
      final grandTotal = subtotal + previousBalance;

      // Create bill data
      final bill = {
        'studentId': studentId,
        'totalAmount': grandTotal,
        'previousBalance': previousBalance,
        'term': term,
        'session': session,
        'billDate': DateTime.now().toIso8601String(),
      };

      // Create breakdown data
      final breakdown = feeRows.map((fee) {
        return {
          'feeItemId': fee['feeItemId'],
          'amount': fee['amount'],
          'label': '', // Will be populated from fee_items table
        };
      }).toList();

      // Insert or update bill
      try {
        await _db.insertStudentBill(bill, breakdown);
        generatedCount++;
      } catch (e) {
        debugPrint('Failed to generate bill for student $studentId: $e');
      }
    }

    return generatedCount;
  }

  @override
  void dispose() {
    for (var c in _amountCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // -----------------------------------------------------------
  // UI
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Assign Fees to Class"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ACTIVE TERM/SESSION DISPLAY - READ ONLY
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
                            Icon(Icons.event,
                                size: 18, color: Colors.indigo.shade700),
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
                                size: 18, color: Colors.indigo.shade700),
                            const SizedBox(width: 8),
                            const Text('Session: '),
                            Text(
                              _activeSession ?? 'Not set',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info,
                                  size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Fees will be assigned for this term/session',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

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
                            value: c['id'],
                            child: Text(c['name']),
                          ))
                      .toList(),
                  onChanged: _onClassChanged,
                ),

                const SizedBox(height: 16),

                // ARM SELECT (shown only if class has arms)
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
                            fillColor: Colors.blue.shade50,
                          ),
                          items: _arms
                              .map((a) => DropdownMenuItem<int>(
                                    value: a['id'],
                                    child: Text(a['name']),
                                  ))
                              .toList(),
                          onChanged: _onArmChanged,
                        ),

                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 24),

                // FEE ITEMS SECTION
                Row(
                  children: [
                    Icon(Icons.receipt_long, color: Colors.indigo.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "Fee Items (${_feeItems.length})",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(),

                // Empty state
                if (_feeItems.isEmpty)
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
                              'No fee items for this term/session',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create fee items first',
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

                // Fee items list
                ..._feeItems.map((item) {
                  final id = item['id'] as int;
                  final name = item['name'] ?? '';
                  final defaultAmount = (item['defaultAmount'] ?? 0).toStringAsFixed(2);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.indigo.shade100,
                            child: Icon(Icons.attach_money,
                                color: Colors.indigo.shade700, size: 20),
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
                                  'Default: ₦$defaultAmount',
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
                            width: 120,
                            child: TextField(
                              controller: _amountCtrl[id],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Amount",
                                border: OutlineInputBorder(),
                                prefixText: '₦',
                                isDense: true,
                              ),
                              onChanged: (_) => _recalculateTotal(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // TOTAL DISPLAY
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200, width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calculate, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            "Total Bill:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "₦${_total.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Colors.green.shade700,
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
                    onPressed: _feeItems.isEmpty ? null : _saveAssignments,
                    icon: const Icon(Icons.save),
                    label: const Text(
                      "SAVE ASSIGNMENTS",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Help text
                if (_selectedClassId == null)
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
                            'Select a class to assign fees',
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
}

