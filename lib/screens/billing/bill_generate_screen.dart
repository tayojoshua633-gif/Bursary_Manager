// lib/screens/billing/bill_generate_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import 'bill_print_screen.dart';
import '../../utils/backup_reminder_helper.dart';
import '../../utils/cloud_sync_helper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../widgets/sibling_mark.dart';

class BillGenerateScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  final bool isSibling;

  const BillGenerateScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    this.isSibling = false,
  });

  @override
  State<BillGenerateScreen> createState() => _BillGenerateScreenState();
}

class _BillGenerateScreenState extends State<BillGenerateScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  bool _loading = true;
  String? _errorMessage;

  Map<String, dynamic>? _student;
  String _term = '';
  String _session = '';

  int? _billId;
  List<_FeeLine> _lines = [];
  bool _zeroBillMode = false;

  double _previousBalance = 0.0;
  double get _subtotal =>
      _lines.fold(0.0, (sum, e) => sum + (e.amount ?? 0));

  double get _grandTotal => _subtotal + _previousBalance;
  Map<String, dynamic>? _currentUser;

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

    if (mounted) {
      setState(() {
        _currentUser = {
          'id': userId,
          'userType': userType,
          'username': username,
        };
      });
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // Load student WITH class and arm names using JOIN
      final db = await _db.database;
      final studentRows = await db.rawQuery('''
        SELECT 
          s.*,
          c.name as className,
          a.name as armName
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        WHERE s.id = ?
      ''', [widget.studentId]);

      if (studentRows.isNotEmpty) {
        _student = studentRows.first;
      }

      _term = await _db.getActiveTerm();
      _session = (await _db.getActiveSession())?['sessionName'] ?? '';

      _previousBalance = await _db.computeOutstandingBeforeTerm(
        widget.studentId,
        term: _term,
        session: _session,
      );

      final oldBill = await _db.getBillForStudent(
        widget.studentId,
        _term,
        _session,
      );

      if (oldBill != null) {
        _billId = oldBill['id'] as int;

        // FIXED: Load bill breakdown - ALWAYS get fee name from fee_items table
        final breakdownRows = await db.rawQuery('''
          SELECT 
            bi.feeItemId,
            bi.amount,
            bi.label as savedLabel,
            fi.name as feeItemName
          FROM student_fee_breakdown bi
          LEFT JOIN fee_items fi ON bi.feeItemId = fi.id
          WHERE bi.billId = ?
          ORDER BY bi.id ASC
        ''', [_billId]);

        _lines = breakdownRows
            .map<_FeeLine>((b) {
              // PRIORITY: Use fee_items.name first, fallback to saved label, then "Fee"
              final feeName = b['feeItemName']?.toString() ??
                             b['savedLabel']?.toString() ??
                             "Fee";

              return _FeeLine(
                feeItemId: b['feeItemId'] as int,
                label: feeName,
                amount: (b['amount'] as num).toDouble(),
                isDefault: false, // Existing bill - not defaults
              );
            })
            .toList();
      } else {
        await _loadFreshFeeLines();
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = "Failed to load bill data: $e";
      });
    }
  }

  bool _usingClassDefaults = false;

  Future<void> _loadFreshFeeLines() async {
    _lines.clear();
    _usingClassDefaults = false;

    int? classId;
    final rawClass = _student?['classId'];

    if (rawClass is int) {
      classId = rawClass;
    } else if (rawClass != null) {
      classId = int.tryParse(rawClass.toString());
    }

    List<Map<String, dynamic>> classFees = [];

    if (classId != null) {
      classFees = await _db.getClassFees(
        classId,
        _term,
        _session,
      );
    }

    if (classFees.isNotEmpty) {
      _usingClassDefaults = true;
      _lines = classFees
          .map(
            (cf) => _FeeLine(
              feeItemId: cf['feeItemId'] is int
                  ? cf['feeItemId']
                  : int.tryParse(cf['feeItemId'].toString()) ?? 0,
              label: cf['feeItemName']?.toString() ?? "Fee",
              amount: (cf['amount'] as num).toDouble(),
              isDefault: true,
            ),
          )
          .where((line) => (line.amount ?? 0) > 0) // Only show fees with amount > 0
          .toList();
    } else {
      final items = await _db.getFeeItems(term: _term, session: _session);

      _lines = items
          .map(
            (it) => _FeeLine(
              feeItemId: it['id'] as int,
              label: it['name']?.toString() ?? "Fee",
              amount: (it['defaultAmount'] as num).toDouble(),
              isDefault: true,
            ),
          )
          .where((line) => (line.amount ?? 0) > 0) // Only show fees with amount > 0
          .toList();
    }
  }

  Future<bool> _confirmOverride() async {
    if (_billId == null) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text("Override Existing Bill?"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "A bill already exists for:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text("TERM: $_term"),
            Text("SESSION: $_session"),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Do you want to replace it?',
                      style: TextStyle(fontSize: 13),
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
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text("Override"),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _generateZeroBill() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.school, color: Colors.indigo),
            SizedBox(width: 8),
            Text("Generate Zero Bill?"),
          ],
        ),
        content: const Text(
          "This will set all fee amounts to ₦0 for this student (e.g. scholarship / fee waiver). "
          "Any amounts you've entered will be cleared. You can still review and save afterwards.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            child: const Text("Zero Out"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (_lines.isEmpty) {
      final items = await _db.getFeeItems(term: _term, session: _session);
      _lines = items
          .map(
            (it) => _FeeLine(
              feeItemId: it['id'] as int,
              label: it['name']?.toString() ?? "Fee",
              amount: 0,
              isDefault: false,
            ),
          )
          .toList();
    } else {
      for (final line in _lines) {
        line.amount = 0;
        line.isDefault = false;
      }
    }

    if (!mounted) return;
    setState(() {
      _usingClassDefaults = false;
      _zeroBillMode = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All fees set to ₦0. Review below, then save."),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  Future<void> _save() async {
    if (_lines.isEmpty && !_zeroBillMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No fee items found.")),
      );
      return;
    }

    final allow = await _confirmOverride();
    if (!allow) return;

    final bill = {
      'studentId': widget.studentId,
      'totalAmount': _grandTotal,
      'previousBalance': _previousBalance,
      'term': _term,
      'session': _session,
      'billDate': DateTime.now().toIso8601String(),
    };

    final breakdown = _lines
        .map(
          (e) => {
            'feeItemId': e.feeItemId,
            'amount': e.amount ?? 0,
            'label': e.label,  // Save the actual fee name
          },
        )
        .toList();

    try {
      final billId = await _db.insertStudentBill(bill, breakdown);

      // Track activity for backup reminder
      await BackupReminderHelper.incrementTransactionCount();
      // Fire-and-forget: silently sync to Google Drive if auto-backup is on
      CloudSyncHelper.triggerAutoBackup();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _billId == null
                ? "Bill created successfully!"
                : "Bill updated successfully!",
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate to print screen
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      NavigationHelper.pushReplacementWithSidebar(
        context,
        page: BillPrintScreen(
          billId: billId,
          studentId: widget.studentId,
          studentName: widget.studentName,
          term: _term,
          session: _session,
        ),
        currentUser: _currentUser ?? {},
        pageId: 'bills_payment/student_bills',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save bill: $e")),
      );
    }
  }

  void _editAmount(_FeeLine line) {
    final ctrl = TextEditingController(text: (line.amount ?? 0).toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.edit, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Edit Amount",
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              line.label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: "Amount",
                prefixText: "₦",
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              line.amount = double.tryParse(ctrl.text) ?? 0;
              line.isDefault = false; // Mark as custom amount
              if (mounted) setState(() {});
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _removeFeeItem(_FeeLine line) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete, color: Colors.red),
            SizedBox(width: 8),
            Text("Remove Fee Item?"),
          ],
        ),
        content: Text("Remove '${line.label}' from this bill?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _lines.remove(line);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }

  Future<void> _addFeeItem() async {
    // Get all available fee items
    final allFees = await _db.getFeeItems(term: _term, session: _session);

    if (!mounted) return;

    if (allFees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fee items available. Please create fee items first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_circle, color: Colors.green),
            SizedBox(width: 8),
            Text("Add Fee Item"),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allFees.length,
            itemBuilder: (context, i) {
              final fee = allFees[i];
              final feeId = fee['id'] as int;
              final feeName = fee['name']?.toString() ?? 'Fee';
              final defaultAmount = (fee['defaultAmount'] as num).toDouble();

              // Check if already added
              final alreadyAdded = _lines.any((line) => line.feeItemId == feeId);

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: alreadyAdded ? Colors.grey : Colors.green.shade100,
                  child: Icon(
                    alreadyAdded ? Icons.check : Icons.attach_money,
                    color: alreadyAdded ? Colors.white : Colors.green.shade700,
                  ),
                ),
                title: Text(feeName),
                subtitle: Text('Default: ₦${NumberFormat("#,##0.00").format(defaultAmount)}'),
                enabled: !alreadyAdded,
                onTap: alreadyAdded ? null : () {
                  // Close the fee selection dialog first
                  Navigator.pop(context);

                  // Show amount entry dialog
                  final amountCtrl = TextEditingController(
                    text: defaultAmount > 0 ? defaultAmount.toString() : '',
                  );

                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Row(
                        children: [
                          const Icon(Icons.attach_money, color: Colors.green),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              "Enter Amount",
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            feeName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: "Amount",
                              prefixText: "₦",
                              border: OutlineInputBorder(),
                              hintText: "Enter amount",
                            ),
                            autofocus: true,
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                            if (amount > 0) {
                              setState(() {
                                _lines.add(_FeeLine(
                                  feeItemId: feeId,
                                  label: feeName,
                                  amount: amount,
                                  isDefault: false,
                                ));
                              });
                              Navigator.pop(context);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a valid amount greater than 0'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Add"),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Generate Bill — "),
            Flexible(child: Text(widget.studentName, overflow: TextOverflow.ellipsis)),
            SiblingMark(show: widget.isSibling),
          ],
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(ds.cardPadding * 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: ds.iconSize * 2.5,
                          color: Colors.red.shade300,
                        ),
                        SizedBox(height: ds.cardPadding),
                        Text(
                          "Error Loading Bill",
                          style: TextStyle(
                            fontSize: ds.titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        SizedBox(height: ds.cardPadding * 0.75),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: ds.bodyFontSize),
                        ),
                        SizedBox(height: ds.cardPadding * 1.5),
                        ElevatedButton.icon(
                          onPressed: _load,
                          icon: Icon(Icons.refresh, size: ds.iconSize),
                          label: Text("Retry", style: TextStyle(fontSize: ds.bodyFontSize)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: ds.cardPadding * 2,
                              vertical: ds.cardPadding * 0.75,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.all(ds.cardPadding * 0.75),
                  child: Column(
                    children: [
                      // Student Info Card
                      Card(
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.shade100,
                            child: Icon(Icons.person, color: Colors.indigo.shade700, size: ds.iconSize),
                          ),
                          title: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.studentName,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: ds.titleFontSize),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SiblingMark(show: widget.isSibling),
                            ],
                          ),
                          subtitle: Text(
                            "${_student?['className'] ?? 'No Class'} - ${_student?['armName'] ?? 'No Arm'}",
                            style: TextStyle(fontSize: ds.bodyFontSize),
                          ),
                        ),
                      ),
                      SizedBox(height: ds.cardPadding * 0.75),

                      // Term and Session
                      Row(
                        children: [
                          Expanded(child: _infoCard("Term", _term, Icons.event, ds)),
                          SizedBox(width: ds.cardPadding * 0.75),
                          Expanded(child: _infoCard("Session", _session, Icons.calendar_today, ds)),
                        ],
                      ),
                      SizedBox(height: ds.cardPadding * 0.75),

                      // Class Default Fees Indicator
                      if (_usingClassDefaults)
                        Card(
                          color: Colors.blue.shade50,
                          child: Padding(
                            padding: EdgeInsets.all(ds.cardPadding * 0.75),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue.shade700, size: ds.iconSize),
                                SizedBox(width: ds.cardPadding * 0.5),
                                Expanded(
                                  child: Text(
                                    "Using default fees assigned to this class. You can edit amounts or add/remove items.",
                                    style: TextStyle(
                                      fontSize: ds.subtitleFontSize,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (_usingClassDefaults) SizedBox(height: ds.cardPadding * 0.75),

                      // Fee Items Section Header
                      Row(
                        children: [
                          Icon(Icons.receipt_long, color: Colors.indigo.shade700, size: ds.iconSize),
                          SizedBox(width: ds.cardPadding * 0.5),
                          Text(
                            "Fee Items (${_lines.length})",
                            style: TextStyle(
                              fontSize: ds.bodyFontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: Icon(Icons.school, color: Colors.indigo.shade700, size: ds.iconSize * 0.85),
                            label: Text(
                              "Zero Bill",
                              style: TextStyle(color: Colors.indigo.shade700, fontSize: ds.subtitleFontSize),
                            ),
                            onPressed: _generateZeroBill,
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle, color: Colors.green, size: ds.iconSize),
                            onPressed: _addFeeItem,
                            tooltip: 'Add fee item',
                          ),
                        ],
                      ),
                      const Divider(),

                      // Fee Items List
                      Card(
                        elevation: 2,
                        child: _lines.isEmpty
                            ? Padding(
                                padding: EdgeInsets.all(ds.cardPadding * 2),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.inbox, size: ds.iconSize * 2.5, color: Colors.grey.shade400),
                                    SizedBox(height: ds.cardPadding),
                                    Text(
                                      "No fee items found",
                                      style: TextStyle(
                                        fontSize: ds.bodyFontSize,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.all(ds.cardPadding * 0.5),
                                itemCount: _lines.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final line = _lines[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.green.shade100,
                                      radius: ds.iconSize * 0.75,
                                      child: Text(
                                        '${i + 1}',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                          fontSize: ds.subtitleFontSize,
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            line.label,
                                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: ds.bodyFontSize),
                                          ),
                                        ),
                                        if (line.isDefault)
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.375, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'DEFAULT',
                                              style: TextStyle(
                                                fontSize: ds.subtitleFontSize * 0.75,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "₦${NumberFormat("#,##0.00").format(line.amount ?? 0)}",
                                          style: TextStyle(
                                            fontSize: ds.bodyFontSize,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(width: ds.cardPadding * 0.5),
                                        IconButton(
                                          icon: Icon(Icons.edit, color: Colors.blue, size: ds.iconSize),
                                          onPressed: () => _editAmount(line),
                                          tooltip: 'Edit amount',
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red, size: ds.iconSize),
                                          onPressed: () => _removeFeeItem(line),
                                          tooltip: 'Remove item',
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      SizedBox(height: ds.cardPadding * 0.75),

                      // Totals
                      _totalRow(
                        "Current Term Total",
                        _subtotal,
                        color: Colors.green,
                        icon: Icons.calculate,
                        ds: ds,
                      ),
                      if (_previousBalance != 0) ...[
                        SizedBox(height: ds.cardPadding * 0.5),
                        _totalRow(
                          _previousBalance > 0 ? "Previous Balance" : "Previous Credit",
                          _previousBalance.abs(),
                          color: _previousBalance > 0 ? Colors.red : Colors.green,
                          icon: _previousBalance > 0 ? Icons.warning : Icons.savings,
                          ds: ds,
                        ),
                      ],
                      SizedBox(height: ds.cardPadding * 0.5),
                      _totalRow(
                        "Grand Total (Prev + Current)",
                        _grandTotal,
                        color: Colors.blue,
                        icon: Icons.account_balance_wallet,
                        ds: ds,
                      ),
                      SizedBox(height: ds.cardPadding * 0.75),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: Icon(Icons.save, size: ds.iconSize),
                              label: Text(
                                _billId == null ? "Save Bill" : "Update Bill",
                                style: TextStyle(
                                  fontSize: ds.bodyFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.all(ds.cardPadding),
                              ),
                            ),
                          ),
                          SizedBox(width: ds.cardPadding * 0.75),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.close, size: ds.iconSize),
                              label: Text(
                                "Cancel",
                                style: TextStyle(fontSize: ds.bodyFontSize),
                              ),
                              onPressed: () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.all(ds.cardPadding),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _infoCard(String title, String value, IconData icon, DisplaySettings ds) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(ds.cardPadding * 0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: ds.iconSize * 0.7, color: Colors.indigo.shade700),
                SizedBox(width: ds.cardPadding * 0.375),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: ds.subtitleFontSize,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            SizedBox(height: ds.cardPadding * 0.25),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: ds.bodyFontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String title, double amount, {required Color color, required IconData icon, required DisplaySettings ds}) {
    return Card(
      elevation: 2,
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: EdgeInsets.all(ds.cardPadding * 0.75),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: ds.iconSize),
                SizedBox(width: ds.cardPadding * 0.5),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: ds.bodyFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text(
              "₦${NumberFormat("#,##0.00").format(amount)}",
              style: TextStyle(
                fontSize: ds.titleFontSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeeLine {
  final int feeItemId;
  final String label;
  double? amount;
  bool isDefault;

  _FeeLine({
    required this.feeItemId,
    required this.label,
    required this.amount,
    this.isDefault = true,
  });
}