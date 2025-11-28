import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';

import '../students/student_list_screen.dart';
import '../billing/bill_student_select_screen.dart';
import '../payments/payment_student_select_screen.dart';
import '../classes/class_list_screen.dart';
import '../fees/fee_item_list_screen.dart';
import '../reports/daily_report_screen.dart';

// NEW IMPORT — Data Management Page
import '../settings/clear_data_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  int _totalStudents = 0;
  double _totalBills = 0;
  double _totalPayments = 0;
  double _outstanding = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    if (mounted) setState(() => _loading = true);

    try {
      final db = await _db.database;

      // Total students
      final students =
          await db.rawQuery("SELECT COUNT(*) AS count FROM students");
      _totalStudents =
          students.isNotEmpty ? (students.first["count"] as int? ?? 0) : 0;

      // Total expected bills
      final bills =
          await db.rawQuery("SELECT SUM(totalAmount) AS total FROM student_bills");
      _totalBills =
          bills.isNotEmpty ? (bills.first["total"] as num? ?? 0).toDouble() : 0;

      // Total payments
      final pays =
          await db.rawQuery("SELECT SUM(amount) AS paid FROM payments");
      _totalPayments =
          pays.isNotEmpty ? (pays.first["paid"] as num? ?? 0).toDouble() : 0;

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
          backgroundColor: color.withAlpha((0.15 * 255).round()),
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
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          );
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
      appBar: AppBar(title: const Text("Dashboard")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Stats
                  _statCard("Total Students", "$_totalStudents",
                      Icons.people, Colors.indigo),

                  _statCard("Total Fees Expected",
                      "₦${_totalBills.toStringAsFixed(2)}",
                      Icons.account_balance_wallet, Colors.green),

                  _statCard("Total Payments Received",
                      "₦${_totalPayments.toStringAsFixed(2)}",
                      Icons.check_circle, Colors.blue),

                  _statCard("Outstanding Balance",
                      "₦${_outstanding.toStringAsFixed(2)}",
                      Icons.warning, Colors.red),

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

                  // ROW 4 — NEW: DATA CLEARING PAGE
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
