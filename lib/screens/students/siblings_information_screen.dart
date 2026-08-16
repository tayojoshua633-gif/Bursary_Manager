// lib/screens/students/siblings_information_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/student.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/thermal_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../../utils/usb_printer_manager.dart';
import '../settings/thermal_printer_screen.dart';
import '../settings/usb_printer_screen.dart';
import 'student_details_screen.dart';
import 'siblings_payment_screen.dart';
import 'siblings_payment_history_screen.dart';
import '../../utils/sms_service.dart';

class SiblingsInformationScreen extends StatefulWidget {
  final Map<String, dynamic> siblingGroup;
  final Color groupColor;

  const SiblingsInformationScreen({
    super.key,
    required this.siblingGroup,
    required this.groupColor,
  });

  @override
  State<SiblingsInformationScreen> createState() => _SiblingsInformationScreenState();
}

class _SiblingsInformationScreenState extends State<SiblingsInformationScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  Map<String, dynamic> _currentUser = {};
  String _activeTerm = "";
  String _activeSession = "";
  Map<String, dynamic>? _school;
  bool _loading = true;

  // Financial data for the group
  List<Map<String, dynamic>> _studentsWithFinancials = [];
  double _groupTotalBills = 0;
  double _groupTotalPaid = 0;
  double _groupTotalOutstanding = 0;

  bool _showBreakdown = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    // Load current user for sidebar navigation
    final prefs = await SharedPreferences.getInstance();
    _currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };

    try {
      final db = await _db.database;

      // Get current term and session
      _activeTerm = await _db.getActiveTerm();
      final sessionData = await _db.getActiveSession();
      _activeSession = sessionData?['sessionName'] ?? "";
      _school = await _db.getSchoolProfile();

      final students = widget.siblingGroup['students'] as List<Map<String, dynamic>>;

      double groupTotalBills = 0;
      double groupTotalPaid = 0;
      double groupTotalOutstanding = 0;

      final List<Map<String, dynamic>> studentsWithFinancials = [];

      for (final student in students) {
        final studentId = student['id'] as int;

        // Calculate previous balance fresh
        final previousBalance = await _db.computeOutstandingBeforeTerm(
          studentId,
          term: _activeTerm,
          session: _activeSession,
        );

        // Get current term bill
        final bill = await _db.getBillForStudent(studentId, _activeTerm, _activeSession);

        double currentTermBill = 0;
        double grandTotal = previousBalance;
        List<Map<String, dynamic>> billItems = [];

        if (bill != null) {
          final storedTotal = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final storedPrevBalance = (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;
          currentTermBill = storedTotal - storedPrevBalance;
          grandTotal = previousBalance + currentTermBill;

          // Load bill items for this student
          final items = await db.rawQuery('''
            SELECT sfb.id, sfb.billId, sfb.feeItemId, sfb.amount,
                   COALESCE(
                     NULLIF(TRIM(sfb.label), ''),
                     fi.name,
                     'Fee Item'
                   ) as feeName
            FROM student_fee_breakdown sfb
            LEFT JOIN fee_items fi ON sfb.feeItemId = fi.id
            WHERE sfb.billId = ?
            ORDER BY sfb.id ASC
          ''', [bill['id']]);
          billItems = items.map((item) => Map<String, dynamic>.from(item)).toList();
        }

        // Get total payments for current term
        final payments = await db.rawQuery('''
          SELECT COALESCE(SUM(amount), 0) as totalPaid
          FROM payments
          WHERE studentId = ? AND term = ? AND session = ?
        ''', [studentId, _activeTerm, _activeSession]);

        final totalPaid = (payments.first['totalPaid'] as num?)?.toDouble() ?? 0.0;
        final outstanding = grandTotal - totalPaid;

        // Add financial data to student
        final studentWithFinancials = Map<String, dynamic>.from(student);
        studentWithFinancials['grandTotal'] = grandTotal;
        studentWithFinancials['totalPaid'] = totalPaid;
        studentWithFinancials['outstanding'] = outstanding;
        studentWithFinancials['previousBalance'] = previousBalance;
        studentWithFinancials['currentTermBill'] = currentTermBill;
        studentWithFinancials['billItems'] = billItems;

        studentsWithFinancials.add(studentWithFinancials);

        // Add to group totals
        groupTotalBills += grandTotal;
        groupTotalPaid += totalPaid;
        groupTotalOutstanding += outstanding;
      }

      if (mounted) {
        setState(() {
          _studentsWithFinancials = studentsWithFinancials;
          _groupTotalBills = groupTotalBills;
          _groupTotalPaid = groupTotalPaid;
          _groupTotalOutstanding = groupTotalOutstanding;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading siblings financial data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = widget.siblingGroup['students'] as List<Map<String, dynamic>>;
    final parentName = widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone = widget.siblingGroup['parentPhone'] as String;
    final familySurname = students.isNotEmpty
        ? (students.first['surname'] as String? ?? 'Family')
        : 'Family';

    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: Text('$familySurname Family'),
        backgroundColor: widget.groupColor,
        foregroundColor: Colors.white,
        actions: [
          // Print button
          IconButton(
            onPressed: () => _showSiblingsBillPrintOptions(),
            icon: const Icon(Icons.print),
            tooltip: 'Print Bills',
          ),
          // SMS button
          IconButton(
            onPressed: _studentsWithFinancials.isEmpty ? null : _sendFamilyBillSms,
            icon: const Icon(Icons.sms),
            tooltip: 'Send Family SMS',
          ),
          if (_activeTerm.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _activeTerm,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _studentsWithFinancials.isEmpty
                            ? null
                            : _openSiblingsPayment,
                        icon: const Icon(Icons.add_card, size: 20),
                        label: const Text(
                          'Pay for Siblings',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _studentsWithFinancials.isEmpty
                            ? null
                            : _openSiblingsPaymentHistory,
                        icon: const Icon(Icons.history, size: 20),
                        label: const Text(
                          'Payment History',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Family header card
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [widget.groupColor, widget.groupColor.withValues(alpha: 0.7)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.family_restroom,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'The $familySurname Family',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${students.length} ${students.length == 1 ? 'child' : 'children'}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Parent info card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: widget.groupColor.withValues(alpha: 0.1),
                              child: Icon(Icons.person, color: widget.groupColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    parentName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: widget.groupColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        parentPhone,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Children section header
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: widget.groupColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Children',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: widget.groupColor,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _showFamilyTermComparison,
                          icon: const Icon(Icons.compare_arrows, size: 16),
                          label: const Text('Compare', style: TextStyle(fontSize: 13)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => setState(() => _showBreakdown = !_showBreakdown),
                          icon: Icon(
                            _showBreakdown ? Icons.receipt_long : Icons.receipt_long_outlined,
                            size: 16,
                          ),
                          label: Text(
                            _showBreakdown ? 'Hide Breakdown' : 'Show Breakdown',
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.groupColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Students list with financial details
                    ..._studentsWithFinancials.map((student) => _buildStudentTile(student)),

                    const SizedBox(height: 20),

                    // Family Summary Card
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [widget.groupColor.withValues(alpha: 0.1), widget.groupColor.withValues(alpha: 0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: widget.groupColor.withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.summarize, size: 20, color: widget.groupColor),
                                const SizedBox(width: 8),
                                Text(
                                  'Family Summary',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: widget.groupColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                // Total Bills
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Total Bills',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '\u20A6${formatter.format(_groupTotalBills)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Total Paid
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Total Paid',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '\u20A6${formatter.format(_groupTotalPaid)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Total Outstanding
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Outstanding',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '\u20A6${formatter.format(_groupTotalOutstanding)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: _groupTotalOutstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // PAYMENT STATUS BADGE
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _groupTotalOutstanding <= 0
                                    ? Colors.green.shade600
                                    : Colors.red.shade600,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _groupTotalOutstanding <= 0
                                        ? Icons.check_circle
                                        : Icons.warning_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _groupTotalOutstanding <= 0
                                        ? 'BALANCED'
                                        : 'YET TO BALANCE',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStudentTile(Map<String, dynamic> student) {
    final fullName = '${student['surname']} ${student['firstName']} ${student['otherName'] ?? ''}'.trim();
    final className = student['className'] ?? 'N/A';
    final armName = student['armName'];
    final classDisplay = armName != null && armName.isNotEmpty ? '$className - $armName' : className;
    final gender = student['gender'] ?? 'Male';

    final grandTotal = (student['grandTotal'] as num?)?.toDouble() ?? 0.0;
    final totalPaid = (student['totalPaid'] as num?)?.toDouble() ?? 0.0;
    final outstanding = (student['outstanding'] as num?)?.toDouble() ?? 0.0;

    final formatter = NumberFormat('#,##0.00');

    return InkWell(
      onTap: () async {
        final db = await _db.database;
        final result = await db.rawQuery('''
          SELECT s.*, c.name as className, a.name as armName
          FROM students s
          LEFT JOIN classes c ON s.classId = c.id
          LEFT JOIN arms a ON s.armId = a.id
          WHERE s.id = ?
        ''', [student['id']]);

        if (result.isNotEmpty && mounted) {
          final studentModel = Student.fromMap(result.first);
          await NavigationHelper.pushWithSidebar(
            context,
            page: StudentDetailsScreen(student: studentModel),
            currentUser: _currentUser,
            pageId: 'student_management/students',
          );
          // Reload data when returning
          _loadData();
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.groupColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Student info row
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: gender == 'Male' ? Colors.blue.shade100 : Colors.pink.shade100,
                    child: Icon(
                      gender == 'Male' ? Icons.boy : Icons.girl,
                      size: 22,
                      color: gender == 'Male' ? Colors.blue.shade700 : Colors.pink.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: widget.groupColor,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          classDisplay,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 16, color: widget.groupColor.withValues(alpha: 0.5)),
                ],
              ),

              const SizedBox(height: 12),
              Divider(height: 1, color: widget.groupColor.withValues(alpha: 0.2)),
              const SizedBox(height: 10),

              // Financial details
              Row(
                children: [
                  // Bills
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Bills',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\u20A6${formatter.format(grandTotal)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Paid
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Paid',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\u20A6${formatter.format(totalPaid)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Outstanding
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Outstanding',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\u20A6${formatter.format(outstanding)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: outstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Inline fee breakdown \u2014 shown when _showBreakdown toggle is on
              if (_showBreakdown) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: widget.groupColor.withValues(alpha: 0.2)),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  final billItems =
                      (student['billItems'] as List<Map<String, dynamic>>?) ?? [];
                  final previousBalance =
                      (student['previousBalance'] as num?)?.toDouble() ?? 0.0;

                  if (billItems.isEmpty && previousBalance <= 0) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_outlined,
                              size: 14, color: Colors.grey.shade400),
                          const SizedBox(width: 6),
                          Text(
                            'No bill issued for this term',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.receipt_long,
                              size: 13, color: widget.groupColor),
                          const SizedBox(width: 5),
                          Text(
                            'Fee Breakdown',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: widget.groupColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...billItems.map((item) {
                        final feeName = item['feeName'] as String? ?? 'Fee';
                        final amount =
                            (item['amount'] as num?)?.toDouble() ?? 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(Icons.circle,
                                  size: 5, color: Colors.grey.shade400),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(feeName,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                              Text(
                                '\u20A6${formatter.format(amount)}',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (previousBalance > 0) ...[
                        Divider(color: Colors.grey.shade200, height: 14),
                        Row(
                          children: [
                            Icon(Icons.history,
                                size: 13, color: Colors.orange.shade700),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Previous Balance (B/F)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            Text(
                              '\u20A6${formatter.format(previousBalance)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                }),
              ],

            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSiblingsPayment() async {
    await NavigationHelper.pushWithSidebar(
      context,
      page: SiblingsPaymentScreen(
        siblingGroup: widget.siblingGroup,
        studentsWithFinancials: _studentsWithFinancials,
        activeTerm: _activeTerm,
        activeSession: _activeSession,
        school: _school,
        groupColor: widget.groupColor,
        currentUser: _currentUser,
      ),
      currentUser: _currentUser,
      pageId: 'student_management/siblings',
    );
    // Always refresh — a payment may have been recorded (and a receipt
    // printed) even if the exact pop result didn't carry a `true` flag.
    if (mounted) _loadData();
  }

  Future<void> _openSiblingsPaymentHistory() async {
    await NavigationHelper.pushWithSidebar(
      context,
      page: SiblingsPaymentHistoryScreen(
        siblingGroup: widget.siblingGroup,
        activeTerm: _activeTerm,
        activeSession: _activeSession,
        groupColor: widget.groupColor,
        currentUser: _currentUser,
      ),
      currentUser: _currentUser,
      pageId: 'student_management/siblings',
    );
    if (mounted) _loadData();
  }

  List<Map<String, dynamic>> _getBankAccounts() {
    if (_school == null) return [];
    final accounts = <Map<String, dynamic>>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = _school!['bankName$i']?.toString() ?? '';
      final accNum = _school!['accountNumber$i']?.toString() ?? '';
      final accName = _school!['accountName$i']?.toString() ?? '';
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add({'bankName': bankName, 'accountNumber': accNum, 'accountName': accName});
      }
    }
    return accounts;
  }

  List<pw.Widget> _buildBankDetailsPdf() {
    final bankAccounts = _getBankAccounts();
    if (bankAccounts.isEmpty) return [];
    return [
      pw.SizedBox(height: 15),
      pw.Text('Bank Account Details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 5),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.cyan100),
        cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft},
        data: [
          ['Bank Name', 'Account Number', 'Account Name'],
          ...bankAccounts.map((a) => [
            a['bankName']?.toString() ?? '',
            a['accountNumber']?.toString() ?? '',
            a['accountName']?.toString() ?? '',
          ]),
        ],
      ),
    ];
  }

  // Show print options dialog for siblings bills
  Future<void> _sendFamilyBillSms() async {
    final parentName = widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone = widget.siblingGroup['parentPhone'] as String?;
    final schoolName = _school?['name']?.toString() ?? 'the school';

    final children = _studentsWithFinancials.map((student) {
      final name = '${student['surname']} ${student['firstName']}'.trim();
      final outstanding = (student['outstanding'] as num?)?.toDouble() ?? 0.0;
      return FamilyChildSummary(studentName: name, outstanding: outstanding);
    }).toList();

    final message = buildFamilySms(
      schoolName: schoolName,
      parentName: parentName,
      children: children,
      totalOutstanding: _groupTotalOutstanding,
      term: _activeTerm,
      session: _activeSession,
    );

    final result = await SmsService.send(
      rawPhone: parentPhone,
      message: message,
      context: 'family_bill',
    );

    if (mounted) {
      final label = result.success
          ? (result.requiresManualConfirmation ? 'Messaging app opened — tap Send to deliver it' : 'Family SMS sent to parent')
          : (result.errorMessage ?? 'Failed to send SMS');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _showSiblingsBillPrintOptions() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.print, color: widget.groupColor),
            const SizedBox(width: 8),
            const Text('Print Siblings Bills'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Print bills for ${_studentsWithFinancials.length} siblings',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Total Outstanding: \u20A6${NumberFormat('#,##0.00').format(_groupTotalOutstanding)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _groupTotalOutstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printSiblingsBillsPDF();
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printSiblingsBillsThermal();
            },
            icon: const Icon(Icons.print),
            label: const Text('Thermal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printSiblingsBillsViaUsb();
            },
            icon: const Icon(Icons.usb),
            label: const Text('USB'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Print siblings bills as PDF
  Future<void> _printSiblingsBillsPDF() async {
    if (_studentsWithFinancials.isEmpty) return;

    final parentName = widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone = widget.siblingGroup['parentPhone'] as String? ?? '';

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final pdf = pw.Document();
      final formatter = NumberFormat('#,##0.00');

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return [
              // School Name
              pw.Center(
                child: pw.Text(
                  _school?['name']?.toString().toUpperCase() ?? 'SCHOOL NAME',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo700),
                ),
              ),
              pw.SizedBox(height: 5),
              if (_school?['address'] != null)
                pw.Center(
                  child: pw.Text(
                    _school!['address'].toString(),
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                ),
              pw.SizedBox(height: 15),

              // Title
              pw.Center(
                child: pw.Text(
                  'SIBLINGS BILL SUMMARY',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'Term: $_activeTerm | Session: $_activeSession',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                ),
              ),
              pw.SizedBox(height: 20),

              // Parent Info
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.cyan300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Parent: $parentName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Phone: $parentPhone', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Individual Student Bills with Breakdown
              ..._studentsWithFinancials.asMap().entries.expand((entry) {
                final index = entry.key;
                final student = entry.value;
                final fullName = '${student['surname']} ${student['firstName']}'.trim();
                final className = student['className'] ?? 'N/A';
                final armName = student['armName'];
                final classDisplay = armName != null && armName.isNotEmpty ? '$className - $armName' : className;
                final grandTotal = (student['grandTotal'] as num?)?.toDouble() ?? 0.0;
                final paid = (student['totalPaid'] as num?)?.toDouble() ?? 0.0;
                final outstanding = (student['outstanding'] as num?)?.toDouble() ?? 0.0;
                final previousBalance = (student['previousBalance'] as num?)?.toDouble() ?? 0.0;
                final billItems = student['billItems'] as List<Map<String, dynamic>>? ?? [];

                return [
                  // Student header
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.cyan100,
                      borderRadius: const pw.BorderRadius.only(
                        topLeft: pw.Radius.circular(5),
                        topRight: pw.Radius.circular(5),
                      ),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Container(
                          width: 24,
                          height: 24,
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.cyan700,
                            shape: pw.BoxShape.circle,
                          ),
                          child: pw.Center(
                            child: pw.Text(
                              '${index + 1}',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                fullName,
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                              ),
                              pw.Text(
                                classDisplay,
                                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bill breakdown table
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.cyan200),
                      borderRadius: const pw.BorderRadius.only(
                        bottomLeft: pw.Radius.circular(5),
                        bottomRight: pw.Radius.circular(5),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Bill items
                        if (billItems.isNotEmpty) ...[
                          pw.Text(
                            'Bill Breakdown:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey700),
                          ),
                          pw.SizedBox(height: 5),
                          ...billItems.map((item) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 2),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Expanded(
                                  child: pw.Text(
                                    item['feeName']?.toString() ?? 'Fee Item',
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ),
                                pw.Text(
                                  'N${formatter.format((item['amount'] as num?)?.toDouble() ?? 0)}',
                                  style: const pw.TextStyle(fontSize: 9),
                                ),
                              ],
                            ),
                          )),
                          pw.Divider(color: PdfColors.grey300),
                        ],

                        // Previous balance if any
                        if (previousBalance > 0)
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 2),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('Previous Balance:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.orange700)),
                                pw.Text('N${formatter.format(previousBalance)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.orange700)),
                              ],
                            ),
                          ),

                        // Summary row
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 5),
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey100,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                            children: [
                              pw.Column(
                                children: [
                                  pw.Text('Total Bill', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                                  pw.Text('N${formatter.format(grandTotal)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.purple700)),
                                ],
                              ),
                              pw.Column(
                                children: [
                                  pw.Text('Paid', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                                  pw.Text('N${formatter.format(paid)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                                ],
                              ),
                              pw.Column(
                                children: [
                                  pw.Text('Outstanding', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                                  pw.Text('N${formatter.format(outstanding)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: outstanding > 0 ? PdfColors.red700 : PdfColors.green700)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 15),
                ];
              }),

              pw.SizedBox(height: 10),

              // Summary
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.cyan400, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total Bills:', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N${formatter.format(_groupTotalBills)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total Paid:', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N${formatter.format(_groupTotalPaid)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.green)),
                      ],
                    ),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('TOTAL OUTSTANDING:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                        pw.Text('N${formatter.format(_groupTotalOutstanding)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: _groupTotalOutstanding > 0 ? PdfColors.red : PdfColors.green)),
                      ],
                    ),
                  ],
                ),
              ),

              // Bank Account Details
              ..._buildBankDetailsPdf(),

              pw.SizedBox(height: 30),
              pw.Divider(),
              pw.Text(
                'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ];
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${dir.path}/siblings_bills_${parentName.replaceAll(' ', '_')}_$dateStr.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Siblings Bills - $parentName',
        text: 'Bills for ${_studentsWithFinancials.length} siblings. Total Outstanding: N${NumberFormat('#,##0.00').format(_groupTotalOutstanding)}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Siblings bills PDF generated!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  // Print siblings bills via thermal printer
  Future<void> _printSiblingsBillsThermal() async {
    if (_studentsWithFinancials.isEmpty) return;

    final parentName = widget.siblingGroup['parentName'] as String? ?? 'Parent';

    if (!ThermalPrinterManager.isConnected) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to a thermal printer first'),
          duration: Duration(seconds: 2),
        ),
      );

      await NavigationHelper.pushWithSidebar(
        context,
        page: const ThermalPrinterScreen(),
        currentUser: _currentUser,
        pageId: 'student_management/students',
      );

      if (!ThermalPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Printer not connected. Printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final schoolName = _school?['name'] ?? 'School Name';
      final schoolAddress = _school?['address'] ?? '';

      // Build sibling items with full financial data
      final List<Map<String, dynamic>> siblingItems = [];
      for (final student in _studentsWithFinancials) {
        final fullName = '${student['surname']} ${student['firstName']}'.trim();
        final className = student['className'] ?? '';
        final armName = student['armName'] ?? '';
        final classLabel = armName.isNotEmpty ? '$className - $armName' : className;
        siblingItems.add({
          'name': fullName,
          'className': classLabel,
          'totalBill': (student['grandTotal'] as num?)?.toDouble() ?? 0.0,
          'totalPaid': (student['totalPaid'] as num?)?.toDouble() ?? 0.0,
          'outstanding': (student['outstanding'] as num?)?.toDouble() ?? 0.0,
        });
      }

      await ThermalPrinterManager.printSiblingsBills(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        parentName: parentName,
        siblingCount: _studentsWithFinancials.length,
        term: '$_activeTerm $_activeSession',
        siblingItems: siblingItems,
        groupTotalBills: _groupTotalBills,
        groupTotalPaid: _groupTotalPaid,
        groupTotalOutstanding: _groupTotalOutstanding,
      );
      await PrintCounterHelper.incrementBillsPrinted();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Siblings bills printed successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing: $e')),
      );
    }
  }

  // Print siblings bills via USB printer
  Future<void> _printSiblingsBillsViaUsb() async {
    if (_studentsWithFinancials.isEmpty) return;

    final parentName = widget.siblingGroup['parentName'] as String? ?? 'Parent';

    if (!UsbPrinterManager.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect a USB printer first'),
          duration: Duration(seconds: 2),
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UsbPrinterScreen()),
      );
      if (!UsbPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('USB printer not connected. Printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final schoolName = _school?['name'] ?? 'School Name';
      final schoolAddress = _school?['address'] ?? '';

      final paperSize = await UsbPrinterManager.getPaperSizeEnum();

      final List<Map<String, dynamic>> siblingItems = [];
      for (final student in _studentsWithFinancials) {
        final fullName = '${student['surname']} ${student['firstName']}'.trim();
        final className = student['className'] ?? '';
        final armName = student['armName'] ?? '';
        final classLabel = armName.isNotEmpty ? '$className - $armName' : className;
        siblingItems.add({
          'name': fullName,
          'className': classLabel,
          'totalBill': (student['grandTotal'] as num?)?.toDouble() ?? 0.0,
          'totalPaid': (student['totalPaid'] as num?)?.toDouble() ?? 0.0,
          'outstanding': (student['outstanding'] as num?)?.toDouble() ?? 0.0,
        });
      }

      await UsbPrinterManager.printSiblingsBills(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        parentName: parentName,
        siblingCount: _studentsWithFinancials.length,
        term: '$_activeTerm $_activeSession',
        siblingItems: siblingItems,
        groupTotalBills: _groupTotalBills,
        groupTotalPaid: _groupTotalPaid,
        groupTotalOutstanding: _groupTotalOutstanding,
        paperSize: paperSize,
      );
      await PrintCounterHelper.incrementBillsPrinted();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Siblings bills printed via USB successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('USB print error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showFamilyTermComparison() async {
    if (_loading || _studentsWithFinancials.isEmpty) return;

    final prevTermSession = DatabaseHelperWrapper.previousTermSession(
      term: _activeTerm,
      session: _activeSession,
    );

    if (prevTermSession == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous term data available')),
      );
      return;
    }

    final prevTerm = prevTermSession['term']!;
    final prevSession = prevTermSession['session']!;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final db = await _db.database;

      double prevGroupBills = 0;
      double prevGroupPaid = 0;
      double prevGroupOutstanding = 0;
      final List<Map<String, dynamic>> studentComparisons = [];

      for (final student in _studentsWithFinancials) {
        final studentId = student['id'] as int;
        final currentPreviousBalance =
            (student['previousBalance'] as num?)?.toDouble() ?? 0.0;

        final bill = await _db.getBillForStudent(studentId, prevTerm, prevSession);
        double prevCurrentTermBill = 0;
        if (bill != null) {
          final storedTotal = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final storedPrevBal =
              (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;
          prevCurrentTermBill = storedTotal - storedPrevBal;
        }

        final paymentsSum = await db.rawQuery('''
          SELECT COALESCE(SUM(amount), 0) as totalPaid
          FROM payments WHERE studentId = ? AND term = ? AND session = ?
        ''', [studentId, prevTerm, prevSession]);
        final prevTotalPaid =
            (paymentsSum.first['totalPaid'] as num?)?.toDouble() ?? 0.0;

        final prevNetOutstanding = prevCurrentTermBill - prevTotalPaid;
        final prevPreviousBalance =
            (currentPreviousBalance - prevNetOutstanding).clamp(0.0, double.infinity);
        final prevGrandTotal = prevPreviousBalance + prevCurrentTermBill;
        final prevOutstanding = prevGrandTotal - prevTotalPaid;

        prevGroupBills += prevGrandTotal;
        prevGroupPaid += prevTotalPaid;
        prevGroupOutstanding += prevOutstanding;

        final armName = student['armName']?.toString() ?? '';
        final className = student['className']?.toString() ?? '';
        studentComparisons.add({
          'name': '${student['surname']} ${student['firstName']}'.trim(),
          'classDisplay':
              armName.isNotEmpty ? '$className - $armName' : className,
          'currGrandTotal': (student['grandTotal'] as num?)?.toDouble() ?? 0.0,
          'currTotalPaid': (student['totalPaid'] as num?)?.toDouble() ?? 0.0,
          'currOutstanding': (student['outstanding'] as num?)?.toDouble() ?? 0.0,
          'prevGrandTotal': prevGrandTotal,
          'prevTotalPaid': prevTotalPaid,
          'prevOutstanding': prevOutstanding,
        });
      }

      if (!mounted) return;
      Navigator.pop(context);

      final students =
          widget.siblingGroup['students'] as List<Map<String, dynamic>>;
      final familySurname = students.isNotEmpty
          ? (students.first['surname'] as String? ?? 'Family')
          : 'Family';

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => _SiblingTermCompSheet(
          familySurname: familySurname,
          prevTerm: prevTerm,
          prevSession: prevSession,
          currentTerm: _activeTerm,
          currentSession: _activeSession,
          prevGroupBills: prevGroupBills,
          prevGroupPaid: prevGroupPaid,
          prevGroupOutstanding: prevGroupOutstanding,
          currentGroupBills: _groupTotalBills,
          currentGroupPaid: _groupTotalPaid,
          currentGroupOutstanding: _groupTotalOutstanding,
          studentComparisons: studentComparisons,
          groupColor: widget.groupColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading comparison data: $e')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Family Term Comparison Sheet
// ---------------------------------------------------------------------------

class _SiblingTermCompSheet extends StatelessWidget {
  final String familySurname;
  final String prevTerm;
  final String prevSession;
  final String currentTerm;
  final String currentSession;
  final double prevGroupBills;
  final double prevGroupPaid;
  final double prevGroupOutstanding;
  final double currentGroupBills;
  final double currentGroupPaid;
  final double currentGroupOutstanding;
  final List<Map<String, dynamic>> studentComparisons;
  final Color groupColor;

  const _SiblingTermCompSheet({
    required this.familySurname,
    required this.prevTerm,
    required this.prevSession,
    required this.currentTerm,
    required this.currentSession,
    required this.prevGroupBills,
    required this.prevGroupPaid,
    required this.prevGroupOutstanding,
    required this.currentGroupBills,
    required this.currentGroupPaid,
    required this.currentGroupOutstanding,
    required this.studentComparisons,
    required this.groupColor,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Gradient header
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade800, Colors.teal.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.compare_arrows,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Term Comparison',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'The $familySurname Family',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.85)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
              children: [
                // ── Family aggregate comparison card ─────────────────────
                _SibCompCard(
                  prevTerm: prevTerm,
                  prevSession: prevSession,
                  currentTerm: currentTerm,
                  currentSession: currentSession,
                  prevBills: prevGroupBills,
                  prevPaid: prevGroupPaid,
                  prevOutstanding: prevGroupOutstanding,
                  currBills: currentGroupBills,
                  currPaid: currentGroupPaid,
                  currOutstanding: currentGroupOutstanding,
                  fmt: fmt,
                ),

                const SizedBox(height: 20),

                // ── Per-student breakdown ─────────────────────────────────
                _SibCompSectionHeader(
                  icon: Icons.people_alt_outlined,
                  label: 'Per Student',
                  color: groupColor,
                  badge: '${studentComparisons.length}',
                ),
                const SizedBox(height: 8),

                ...studentComparisons.map((s) {
                  final prevOut =
                      (s['prevOutstanding'] as num?)?.toDouble() ?? 0.0;
                  final currOut =
                      (s['currOutstanding'] as num?)?.toDouble() ?? 0.0;
                  final prevBill =
                      (s['prevGrandTotal'] as num?)?.toDouble() ?? 0.0;
                  final currBill =
                      (s['currGrandTotal'] as num?)?.toDouble() ?? 0.0;
                  final prevPaid =
                      (s['prevTotalPaid'] as num?)?.toDouble() ?? 0.0;
                  final currPaid =
                      (s['currTotalPaid'] as num?)?.toDouble() ?? 0.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: groupColor.withValues(alpha: 0.25)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Student name header
                          Container(
                            color: groupColor.withValues(alpha: 0.06),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            child: Row(
                              children: [
                                Icon(Icons.person,
                                    size: 14, color: groupColor),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s['name'] as String,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: groupColor,
                                    ),
                                  ),
                                ),
                                Text(
                                  s['classDisplay'] as String,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                              height: 1,
                              color: groupColor.withValues(alpha: 0.15)),
                          // Comparison rows
                          _SibCompRow(
                              label: 'Total Bill',
                              prevAmt: prevBill,
                              currAmt: currBill,
                              fmt: fmt,
                              prevColor: Colors.purple.shade700,
                              currColor: Colors.purple.shade700),
                          Divider(
                              height: 1, color: Colors.grey.shade100),
                          _SibCompRow(
                              label: 'Paid',
                              prevAmt: prevPaid,
                              currAmt: currPaid,
                              fmt: fmt,
                              prevColor: Colors.green.shade700,
                              currColor: Colors.green.shade700),
                          Divider(
                              height: 1, color: Colors.grey.shade100),
                          _SibCompRow(
                            label: 'Outstanding',
                            prevAmt: prevOut,
                            currAmt: currOut,
                            fmt: fmt,
                            bold: true,
                            showDelta: true,
                            highlight: true,
                            prevColor: prevOut > 0
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            currColor: currOut > 0
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Aggregate comparison card ──────────────────────────────────────────────

class _SibCompCard extends StatelessWidget {
  final String prevTerm;
  final String prevSession;
  final String currentTerm;
  final String currentSession;
  final double prevBills;
  final double prevPaid;
  final double prevOutstanding;
  final double currBills;
  final double currPaid;
  final double currOutstanding;
  final NumberFormat fmt;

  const _SibCompCard({
    required this.prevTerm,
    required this.prevSession,
    required this.currentTerm,
    required this.currentSession,
    required this.prevBills,
    required this.prevPaid,
    required this.prevOutstanding,
    required this.currBills,
    required this.currPaid,
    required this.currOutstanding,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            // Term chip header
            Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  const Expanded(flex: 5, child: SizedBox()),
                  Expanded(
                    flex: 4,
                    child: _SibTermChip(
                      label: prevTerm,
                      sub: prevSession,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 4,
                    child: _SibTermChip(
                      label: currentTerm,
                      sub: currentSession,
                      color: Colors.teal.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
            _SibCompRow(
              label: 'Total Bill',
              prevAmt: prevBills,
              currAmt: currBills,
              fmt: fmt,
              prevColor: Colors.purple.shade700,
              currColor: Colors.purple.shade700,
              bold: true,
              highlight: true,
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
            _SibCompRow(
              label: 'Total Paid',
              prevAmt: prevPaid,
              currAmt: currPaid,
              fmt: fmt,
              prevColor: Colors.green.shade700,
              currColor: Colors.green.shade700,
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
            _SibCompRow(
              label: 'Outstanding',
              prevAmt: prevOutstanding,
              currAmt: currOutstanding,
              fmt: fmt,
              bold: true,
              highlight: true,
              showDelta: true,
              prevColor: prevOutstanding > 0
                  ? Colors.red.shade700
                  : Colors.green.shade700,
              currColor: currOutstanding > 0
                  ? Colors.red.shade700
                  : Colors.green.shade700,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────

class _SibTermChip extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;

  const _SibTermChip(
      {required this.label, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12, color: color),
              textAlign: TextAlign.center),
          Text(sub,
              style: TextStyle(
                  fontSize: 10, color: color.withValues(alpha: 0.75)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _SibCompSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? badge;

  const _SibCompSectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: color)),
        if (badge != null) ...[
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(badge!,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }
}

class _SibCompRow extends StatelessWidget {
  final String label;
  final double prevAmt;
  final double currAmt;
  final NumberFormat fmt;
  final Color? prevColor;
  final Color? currColor;
  final bool bold;
  final bool highlight;
  final bool showDelta;

  const _SibCompRow({
    required this.label,
    required this.prevAmt,
    required this.currAmt,
    required this.fmt,
    this.prevColor,
    this.currColor,
    this.bold = false,
    this.highlight = false,
    this.showDelta = false,
  });

  @override
  Widget build(BuildContext context) {
    final diff = currAmt - prevAmt;
    final fontWeight = bold ? FontWeight.bold : FontWeight.normal;

    Widget deltaIcon = const SizedBox(width: 14);
    if (showDelta && diff != 0) {
      deltaIcon = Icon(
        diff > 0 ? Icons.arrow_upward : Icons.arrow_downward,
        size: 11,
        color: Colors.grey.shade400,
      );
    }

    return Container(
      color: highlight ? Colors.grey.shade50 : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: fontWeight,
                  color: Colors.grey.shade800),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '₦${fmt.format(prevAmt)}',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: fontWeight,
                color: prevColor ?? Colors.grey.shade800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          deltaIcon,
          const SizedBox(width: 4),
          Expanded(
            flex: 4,
            child: Text(
              '₦${fmt.format(currAmt)}',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: fontWeight,
                color: currColor ?? Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
