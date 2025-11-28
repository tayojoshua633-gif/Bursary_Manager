// lib/screens/students/student_statement_screen.dart

import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';

class StudentStatementScreen extends StatefulWidget {
  final int studentId;
  final String studentName;

  const StudentStatementScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentStatementScreen> createState() =>
      _StudentStatementScreenState();
}

class _StudentStatementScreenState extends State<StudentStatementScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  bool _loading = true;

  String _activeTerm = "";
  String _activeSession = "";

  List<Map<String, dynamic>> _bills = [];
  List<Map<String, dynamic>> _payments = [];

  double _totalBills = 0.0;
  double _totalPayments = 0.0;
  double _outstanding = 0.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Active term & session
    final sess = await _db.getActiveSession();
    _activeSession = sess?['sessionName'] ?? "";
    _activeTerm = await _db.getActiveTerm();

    final db = await _db.database;

    // ---------------------------------------------
    // FETCH BILLS FOR THIS STUDENT
    // ---------------------------------------------
    _bills = await db.rawQuery(
      '''
      SELECT *
      FROM student_bills
      WHERE studentId = ?
      ORDER BY billDate DESC
      ''',
      [widget.studentId],
    );

    // ---------------------------------------------
    // FETCH PAYMENTS FOR THIS STUDENT
    // ---------------------------------------------
    _payments = await db.rawQuery(
      '''
      SELECT *
      FROM payments
      WHERE studentId = ?
      ORDER BY paymentDate DESC
      ''',
      [widget.studentId],
    );

    // ---------------------------------------------
    // TOTALS
    // ---------------------------------------------
    _totalBills = 0;
    for (var b in _bills) {
      final total = (b['totalAmount'] ?? 0) as num;
      final prev = (b['previousBalance'] ?? 0) as num;
      _totalBills += (total + prev).toDouble();
    }

    _totalPayments = 0;
    for (var p in _payments) {
      final amt = (p['amount'] ?? 0) as num;
      _totalPayments += amt.toDouble();
    }

    _outstanding = await _db.computeOutstandingBalance(widget.studentId);

    if (mounted) setState(() => _loading = false);
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _moneyRow(String label, double amount, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          "₦${amount.toStringAsFixed(2)}",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Statement – ${widget.studentName}"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  "Statement for $_activeTerm ($_activeSession)",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),

                // ---------------------------------------------
                // SUMMARY CARD
                // ---------------------------------------------
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _moneyRow("Total Bills", _totalBills),
                        const SizedBox(height: 6),
                        _moneyRow("Total Payments", _totalPayments),
                        const Divider(height: 22),
                        _moneyRow(
                          "Outstanding Balance",
                          _outstanding,
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 25),

                // ---------------------------------------------
                // LIST OF BILLS
                // ---------------------------------------------
                _sectionTitle("Bills"),
                if (_bills.isEmpty)
                  const Text("No bills found for this student.")
                else
                  ..._bills.map(
                    (b) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long),
                        title: Text(
                            "₦${(b['totalAmount'] as num).toStringAsFixed(2)}"),
                        subtitle: Text(b['billDate'] ?? ""),
                        trailing: Text(
                          "+₦${(b['previousBalance'] as num).toStringAsFixed(2)}",
                          style: const TextStyle(color: Colors.orange),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 25),

                // ---------------------------------------------
                // LIST OF PAYMENTS
                // ---------------------------------------------
                _sectionTitle("Payments"),
                if (_payments.isEmpty)
                  const Text("No payments made yet.")
                else
                  ..._payments.map(
                    (p) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.payment),
                        title: Text(
                          "₦${(p['amount'] as num).toStringAsFixed(2)}",
                        ),
                        subtitle: Text(p['paymentDate'] ?? ""),
                        trailing: Text(
                          p['method']?.toString() ?? "",
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 20),
              ],
            ),
    );
  }
}
