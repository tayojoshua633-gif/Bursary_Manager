import 'dart:io';
import 'package:flutter/material.dart';
import '../../db/database_helper.dart';

class PaymentHistoryScreen extends StatefulWidget {
  final int studentId;
  final String studentName;

  const PaymentHistoryScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic>? _student;
  Map<String, dynamic>? _school;

  double _totalPaid = 0;
  double _outstanding = 0;

  bool _loading = true;

  // ADDED ↓↓↓
  String _activeTerm = "";
  String _activeSession = "";
  // ADDED ↑↑↑

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ----------------------------------------------------------------
  // LOAD DATA
  // ----------------------------------------------------------------
  Future<void> _load() async {
    setState(() => _loading = true);

    final db = await _db.database;

    // Load active term/session
    _activeTerm = await _db.getActiveTerm();
    _activeSession =
        (await _db.getActiveSession())?['sessionName'] ?? "";

    // School profile
    _school = await _db.getSchoolProfile();

    // Student information
    _student = await _db.getStudentById(widget.studentId);

    // Load ALL payments for this student
    _payments = await db.query(
      "payments",
      where: "studentId = ?",
      whereArgs: [widget.studentId],
      orderBy: "paymentDate ASC",
    );

    // Compute totals
    _totalPaid = 0;
    for (var p in _payments) {
      final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
      _totalPaid += amt;
    }

    // Compute outstanding
    _outstanding = await _db.computeOutstandingBalance(widget.studentId);

    if (mounted) setState(() => _loading = false);
  }

  // Print placeholder
  Future<void> _printReceipt() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Printing... (Thermal printer pending)")),
    );
  }

  // ----------------------------------------------------------------
  // UI
  // ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final schoolName = _school?['name'] ?? "School Name";
    final schoolAddr = _school?['address'] ?? "School Address";
    final schoolEmail = _school?['email'] ?? "Email";
    final schoolPhone = _school?['phone'] ?? "Phone";
    final schoolLogo = _school?['logoPath'];

    final className = _student?['className'] ?? "";
    final armName = _student?['armName'] ?? "";

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.studentName} – Payment History"),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ===================================================
                // SCHOOL HEADER
                // ===================================================
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundImage: (schoolLogo != null &&
                              schoolLogo.toString().isNotEmpty &&
                              File(schoolLogo).existsSync())
                          ? FileImage(File(schoolLogo))
                          : null,
                      child: (schoolLogo == null ||
                              schoolLogo.toString().isEmpty)
                          ? const Icon(Icons.school, size: 45)
                          : null,
                    ),

                    const SizedBox(height: 10),

                    Text(
                      schoolName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 4),

                    Text(
                      schoolAddr,
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),

                    Text(
                      schoolEmail,
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),

                    Text(
                      "Phone: $schoolPhone",
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),
                    const Divider(),
                  ],
                ),

                const SizedBox(height: 12),

                // ===================================================
                // STUDENT DETAILS
                // ===================================================
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  "Class: $className  |  Arm: $armName",
                  style: const TextStyle(fontSize: 14),
                ),

                const SizedBox(height: 4),

                // ADDED: TERM & SESSION
                Text(
                  "Term: $_activeTerm  |  Session: $_activeSession",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey,
                  ),
                ),

                const SizedBox(height: 12),
                const Divider(),

                // ===================================================
                // PAYMENT LIST
                // ===================================================
                const Text(
                  "Payment History",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                ..._payments.map((p) {
                  final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
                  final method = p['method'] ?? '';
                  final date = p['paymentDate'] ?? '';

                  return ListTile(
                    leading: const Icon(Icons.payment),
                    title: Text(
                      "₦${amount.toStringAsFixed(2)}  ($method)",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(date),
                  );
                }),

                if (_payments.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text("No payment history found."),
                    ),
                  ),

                const SizedBox(height: 20),

                // ===================================================
                // TOTAL PAID + OUTSTANDING
                // ===================================================
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "Total Amount Paid: ₦${_totalPaid.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Outstanding Balance: ₦${_outstanding.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color:
                              _outstanding > 0 ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // ===================================================
                // PRINT BUTTON
                // ===================================================
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text("Print / Share Receipt"),
                    onPressed: _printReceipt,
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
    );
  }
}
