// lib/screens/billing/bill_generate_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';
import 'bill_print_screen.dart';

class BillGenerateScreen extends StatefulWidget {
  final int studentId;
  final String studentName;

  const BillGenerateScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<BillGenerateScreen> createState() => _BillGenerateScreenState();
}

class _BillGenerateScreenState extends State<BillGenerateScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  bool _loading = true;
  String? _errorMessage;

  Map<String, dynamic>? _student;
  String _term = '';
  String _session = '';

  int? _billId;
  List<_FeeLine> _lines = [];

  double _previousBalance = 0.0;
  double get _subtotal =>
      _lines.fold(0.0, (sum, e) => sum + (e.amount ?? 0));

  double get _grandTotal => _subtotal + _previousBalance;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _loadFreshFeeLines() async {
    _lines.clear();

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
      _lines = classFees
          .map(
            (cf) => _FeeLine(
              feeItemId: cf['feeItemId'] is int
                  ? cf['feeItemId']
                  : int.tryParse(cf['feeItemId'].toString()) ?? 0,
              label: cf['feeItemName']?.toString() ?? "Fee",
              amount: (cf['amount'] as num).toDouble(),
            ),
          )
          .toList();
    } else {
      final items = await _db.getFeeItems(term: _term, session: _session);

      _lines = items
          .map(
            (it) => _FeeLine(
              feeItemId: it['id'] as int,
              label: it['name']?.toString() ?? "Fee",
              amount: (it['defaultAmount'] as num).toDouble(),
            ),
          )
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

  Future<void> _save() async {
    if (_lines.isEmpty) {
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
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BillPrintScreen(
            billId: billId,
            studentId: widget.studentId,
            studentName: widget.studentName,
            term: _term,
            session: _session,
          ),
        ),
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
              if (mounted) setState(() {});
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Generate Bill — ${widget.studentName}"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Error Loading Bill",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text("Retry"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Student Info Card
                      Card(
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.shade100,
                            child: Icon(Icons.person, color: Colors.indigo.shade700),
                          ),
                          title: Text(
                            widget.studentName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "${_student?['className'] ?? 'No Class'} - ${_student?['armName'] ?? 'No Arm'}",
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Term and Session
                      Row(
                        children: [
                          Expanded(child: _infoCard("Term", _term, Icons.event)),
                          const SizedBox(width: 12),
                          Expanded(child: _infoCard("Session", _session, Icons.calendar_today)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Previous Balance
                      if (_previousBalance > 0)
                        Card(
                          color: Colors.red.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      "Previous Balance",
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                Text(
                                  "₦${NumberFormat("#,##0.00").format(_previousBalance)}",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      
                      if (_previousBalance > 0) const SizedBox(height: 12),

                      // Fee Items Section Header
                      Row(
                        children: [
                          Icon(Icons.receipt_long, color: Colors.indigo.shade700),
                          const SizedBox(width: 8),
                          Text(
                            "Fee Items (${_lines.length})",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),

                      // Fee Items List
                      Expanded(
                        child: Card(
                          elevation: 2,
                          child: _lines.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      Text(
                                        "No fee items found",
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: _lines.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final line = _lines[i];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.green.shade100,
                                        radius: 18,
                                        child: Text(
                                          '${i + 1}',
                                          style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        line.label,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            "₦${NumberFormat("#,##0.00").format(line.amount ?? 0)}",
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.blue),
                                            onPressed: () => _editAmount(line),
                                            tooltip: 'Edit amount',
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Totals
                      _totalRow(
                        "Current Term Total",
                        _subtotal,
                        color: Colors.green,
                        icon: Icons.calculate,
                      ),
                      const SizedBox(height: 8),
                      _totalRow(
                        "Grand Total (Prev + Current)",
                        _grandTotal,
                        color: Colors.blue,
                        icon: Icons.account_balance_wallet,
                      ),
                      const SizedBox(height: 12),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.save),
                              label: Text(
                                _billId == null ? "Save Bill" : "Update Bill",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.close),
                              label: const Text(
                                "Cancel",
                                style: TextStyle(fontSize: 16),
                              ),
                              onPressed: () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
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

  Widget _infoCard(String title, String value, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.indigo.shade700),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String title, double amount, {required Color color, required IconData icon}) {
    return Card(
      elevation: 2,
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text(
              "₦${NumberFormat("#,##0.00").format(amount)}",
              style: TextStyle(
                fontSize: 18,
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

  _FeeLine({
    required this.feeItemId,
    required this.label,
    required this.amount,
  });
}