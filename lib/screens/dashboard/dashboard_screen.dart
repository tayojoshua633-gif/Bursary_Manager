import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';

import '../students/student_list_screen.dart';
import '../billing/bill_student_select_screen.dart';
import '../payments/payment_student_select_screen.dart';
import '../classes/class_list_screen.dart';
import '../fees/fee_item_list_screen.dart';
import '../reports/daily_report_screen.dart';
import '../settings/clear_data_screen.dart';

// NEW IMPORTS - Deactivation features
import '../students/deactivate_student_screen.dart';
import '../students/inactive_students_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  int _totalActiveStudents = 0;
  int _totalInactiveStudents = 0;
  
  // CORRECTED: Term-specific financial data
  double _totalBills = 0;
  double _totalPayments = 0;
  double _outstanding = 0;
  
  String _currentTerm = "";
  String _currentSession = "";

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    if (mounted) setState(() => _loading = true);

    try {
      // Use the database helper methods instead of raw queries
      final activeStudents = await _db.getActiveStudents();
      _totalActiveStudents = activeStudents.length;

      final inactiveStudents = await _db.getInactiveStudents();
      _totalInactiveStudents = inactiveStudents.length;

      // Get current term and session
      _currentTerm = await _db.getActiveTerm();
      final sessionData = await _db.getActiveSession();
      _currentSession = sessionData?['sessionName'] ?? "";

      // Get database for financial queries
      final db = await _db.database;

      // CORRECTED: Total bills for CURRENT TERM only
      final bills = await db.rawQuery(
        "SELECT COALESCE(SUM(totalAmount), 0) AS total FROM student_bills WHERE term = ? AND session = ?",
        [_currentTerm, _currentSession],
      );
      _totalBills = bills.isNotEmpty
          ? (bills.first["total"] as num? ?? 0).toDouble()
          : 0;

      // CORRECTED: Total payments for CURRENT TERM only
      final pays = await db.rawQuery(
        "SELECT COALESCE(SUM(amount), 0) AS paid FROM payments WHERE term = ? AND session = ?",
        [_currentTerm, _currentSession],
      );
      _totalPayments =
          pays.isNotEmpty ? (pays.first["paid"] as num? ?? 0).toDouble() : 0;

      // CORRECTED: Outstanding for CURRENT TERM
      _outstanding = _totalBills - _totalPayments;
    } catch (e, st) {
      debugPrint("Dashboard load error: $e\n$st");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, size: 28, color: color),
        ),
        title: Text(title),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _quickButton(
    String title,
    IconData icon,
    Widget screen,
    BuildContext context,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          );
          // Refresh dashboard when returning from certain screens
          if (screen is DeactivateStudentScreen ||
              screen is InactiveStudentsScreen) {
            _loadDashboardData();
          }
        },
        child: Card(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40, color: Colors.blue),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Dashboard"),
            if (_currentTerm.isNotEmpty && _currentSession.isNotEmpty)
              Text(
                "$_currentTerm - $_currentSession",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Stats - Active Students
                  _statCard(
                    "Total Students",
                    "$_totalActiveStudents",
                    Icons.people,
                    Colors.indigo,
                  ),

                  // Show inactive students count if there are any
                  if (_totalInactiveStudents > 0)
                    _statCard(
                      "Inactive Students",
                      "$_totalInactiveStudents",
                      Icons.person_off,
                      Colors.orange,
                    ),

                  // CORRECTED: Term-specific financial stats
                  _statCard(
                    "Total Fees Expected (This Term)",
                    "₦${_totalBills.toStringAsFixed(2)}",
                    Icons.account_balance_wallet,
                    Colors.green,
                  ),

                  _statCard(
                    "Total Payments Received (This Term)",
                    "₦${_totalPayments.toStringAsFixed(2)}",
                    Icons.check_circle,
                    Colors.blue,
                  ),

                  _statCard(
                    "Outstanding Balance (This Term)",
                    "₦${_outstanding.toStringAsFixed(2)}",
                    Icons.warning,
                    Colors.red,
                  ),

                  const SizedBox(height: 20),
                  const Text(
                    "Quick Access",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // ROW 1
                  Row(
                    children: [
                      _quickButton("Students", Icons.person,
                          const StudentListScreen(), context),
                      _quickButton(
                        "Bills",
                        Icons.receipt_long,
                        const BillStudentSelectScreen(),
                        context,
                      ),
                    ],
                  ),

                  // ROW 2
                  Row(
                    children: [
                      _quickButton("Payments", Icons.attach_money,
                          const PaymentStudentSelectScreen(), context),
                      _quickButton("Classes", Icons.school,
                          const ClassListScreen(), context),
                    ],
                  ),

                  // ROW 3
                  Row(
                    children: [
                      _quickButton(
                        "Fee Items",
                        Icons.list,
                        const FeeItemListScreen(),
                        context,
                      ),
                      _quickButton(
                        "Daily Report",
                        Icons.pie_chart,
                        const DailyReportScreen(),
                        context,
                      ),
                    ],
                  ),

                  // ROW 4 - Student Deactivation Features
                  Row(
                    children: [
                      _quickButton(
                        "Deactivate Students",
                        Icons.person_off,
                        const DeactivateStudentScreen(),
                        context,
                      ),
                      _quickButton(
                        "Inactive Students",
                        Icons.archive,
                        const InactiveStudentsScreen(),
                        context,
                      ),
                    ],
                  ),

                  // ROW 5 - Data Management
                  Row(
                    children: [
                      _quickButton(
                        "Data Management",
                        Icons.delete_forever,
                        const ClearDataScreen(),
                        context,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}