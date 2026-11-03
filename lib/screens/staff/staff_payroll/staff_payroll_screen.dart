// lib/screens/staff/staff_payroll/staff_payroll_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/database_helper_wrapper.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import '../../../utils/staff_payroll_pdf_generator.dart';
import '../../../utils/staff_payslip_pdf_generator.dart';
import '../../../utils/pdf_export_helper.dart';
import '../../../widgets/quick_access_sidebar.dart';

class StaffPayrollScreen extends StatefulWidget {
  const StaffPayrollScreen({super.key});

  @override
  State<StaffPayrollScreen> createState() => _StaffPayrollScreenState();
}

class _StaffPayrollScreenState extends State<StaffPayrollScreen> {
  final _dbHelper = DatabaseHelper();
  // Salary payments, loans, incentives, and deductions are wired through
  // the repository layer (client/server sync + audit logging); payroll
  // computation reads (prorating, arrears, basis settings) stay on
  // DatabaseHelper directly — out of scope, not editable records.
  final _repoDb = DatabaseHelperWrapper();
  final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  List<Map<String, dynamic>> _payrollData = [];
  String _selectedMonth = '';
  bool _isLoading = true;
  bool _isExporting = false;
  Map<int, bool> _paymentStatus = {}; // Track paid status by staff ID
  String _paymentFilter = 'all'; // 'all' | 'paid' | 'unpaid'
  Map<String, dynamic>? _monthBasis; // Month-wide default payroll basis

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    _loadPayrollData();
  }

  Future<void> _loadPayrollData({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _isLoading = true);
    try {
      // Get all active staff
      final staffMaps = await _dbHelper.getStaff();

      // Get payment status for all staff
      final salaryPayments = await _repoDb.getSalaryPaymentsByMonth(_selectedMonth);
      _paymentStatus = {};
      final paymentByStaffId = <int, Map<String, dynamic>>{};
      for (var payment in salaryPayments) {
        final sid = payment['staffId'] as int;
        _paymentStatus[sid] = (payment['isPaid'] as int) == 1;
        paymentByStaffId[sid] = payment;
      }

      // Month-wide default payroll basis (Full/Percentage/Days/Weeks)
      _monthBasis = await _dbHelper.getPayrollMonthBasis(_selectedMonth);

      // Deactivated staff who were already paid/marked for this month keep
      // showing here so their historical payroll record isn't lost.
      final paidStaffIds = salaryPayments.map((p) => p['staffId'] as int).toSet();
      final inactiveStaffMaps = await _dbHelper.getInactiveStaff();
      final inactiveWithRecords =
          inactiveStaffMaps.where((m) => paidStaffIds.contains(m['id']));

      final staffList = [...staffMaps, ...inactiveWithRecords]
          .map((m) => Staff.fromMap(m))
          // Hide staff from months before they were employed (e.g. a staff
          // member hired this month shouldn't show up in prior months' payroll)
          // and from months after a (possibly back-dated) deactivation.
          .where((s) =>
              _dbHelper.isStaffEmployedByMonth(s.dateOfEmployment, _selectedMonth) &&
              _dbHelper.isStaffActiveByMonth(s.deactivationDate, _selectedMonth))
          .toList();

      // Get incentives and deductions for the month (loan deductions come
      // from getLoanDeductionPlan per staff below)
      final incentives = await _repoDb.getStaffIncentivesByMonth(_selectedMonth);
      final deductions = await _repoDb.getStaffDeductionsByMonth(_selectedMonth);

      // Build payroll data for each staff
      List<Map<String, dynamic>> payrollData = [];

      for (var staff in staffList) {
        // Get individual incentives for this staff (for details display)
        final staffIncentivesList = incentives
            .where((i) => i['staffId'] == staff.id)
            .toList();
        final totalIncentives = staffIncentivesList
            .fold<double>(0, (sum, i) => sum + (i['amount'] as num).toDouble());

        // Loan deductions for this month: what was actually deducted if
        // already paid, otherwise what falls due (this month + missed months
        // since each loan started, capped at the months left on the loan).
        final loanPlan = await _dbHelper.getLoanDeductionPlan(
          staff.id!,
          _selectedMonth,
          employmentDate: staff.dateOfEmployment,
        );
        final loanPlanEntries = loanPlan['loans'] as List<Map<String, dynamic>>;
        final loanSkipEntries = loanPlan['skipped'] as List<Map<String, dynamic>>;
        final staffLoansList = [
          for (final e in loanPlanEntries) e['loan'] as Map<String, dynamic>,
        ];
        final loanDeduction = loanPlan['currentDeduction'] as double;
        final loanArrears = loanPlan['arrearsDeduction'] as double;

        // Get individual deductions/penalties for this staff (for details display)
        final staffDeductionsList = deductions
            .where((d) => d['staffId'] == staff.id)
            .toList();
        final totalDeductions = staffDeductionsList
            .fold<double>(0, (sum, d) => sum + (d['amount'] as num).toDouble());

        // Per-Period staff (Per-Time teaching staff paid by periods taken)
        // are paid periodsWorked × periodRate for the month, saved on the
        // Staff Payroll card — this replaces the usual salary-history +
        // Full/Percentage/Days/Weeks proration entirely, since the periods
        // entered already reflect the actual work done that month.
        final isPerPeriodPay = staff.isPerPeriodPay;
        double basicSalary;
        Map<String, dynamic> payrollBasis;
        double periodsWorked = 0;
        double periodRate = staff.perPeriodRate ?? 0;
        double arrears = 0;

        if (isPerPeriodPay) {
          final periodRecord = await _dbHelper.getStaffPeriodRecord(staff.id!, _selectedMonth);
          if (periodRecord != null) {
            periodsWorked = (periodRecord['periodsWorked'] as num).toDouble();
            periodRate = (periodRecord['periodRate'] as num).toDouble();
            basicSalary = (periodRecord['amount'] as num).toDouble();
          } else {
            basicSalary = 0;
          }
          payrollBasis = {'basisType': 'per_period', 'isOverride': false};
        } else {
          // Use salary history to get correct salary for this month, then
          // apply the resolved payroll basis (Full/Percentage/Days/Weeks)
          basicSalary = await _dbHelper.getProratedBasicSalaryForMonth(
            staff.id!,
            _selectedMonth,
            fallbackSalary: staff.salary,
          );
          payrollBasis = await _dbHelper.resolvePayrollBasis(staff.id!, _selectedMonth);

          // Calculate salary arrears from previous unpaid months
          arrears = await _dbHelper.getSalaryArrearsForStaff(
            staff.id!,
            _selectedMonth,
            fallbackSalary: basicSalary,
            employmentDate: staff.dateOfEmployment,
          );
        }

        // Calculate current-month net salary
        final netSalary = basicSalary + totalIncentives - loanDeduction - totalDeductions;

        // Total = current net + salary arrears (basic+incentives−deductions for
        // unpaid months) − loan arrears (loan is shown accumulated in the loan
        // column, so subtract here to avoid double-counting).
        // Mathematically equals: sum of NET salary for current + all unpaid months.
        // Amount still owed from the last settled salary (net went negative
        // after all deductions) — deducted in full from this salary.
        final owing = await _dbHelper.getOwingBroughtForward(
          staff.id!,
          _selectedMonth,
          employmentDate: staff.dateOfEmployment,
        );
        final owingBroughtForward = (owing?['amount'] as num?)?.toDouble() ?? 0;
        final owingCarried =
            (paymentByStaffId[staff.id]?['owingCarriedForward'] as num?)?.toDouble() ?? 0;
        final isSettled = (_paymentStatus[staff.id] ?? false) && owingCarried > 0;
        // Closed because a later salary already paid this month as arrears
        final paidWithMonth = paymentByStaffId[staff.id]?['paidWithMonth'] as String?;

        final totalPayable = netSalary + arrears - loanArrears - owingBroughtForward;

        payrollData.add({
          'id': staff.id, // Include database ID for payment tracking
          'staffId': staff.staffId,
          'staffName': staff.fullName,
          'staffType': staff.isPerTime ? '${staff.staffType} (${staff.employmentType})' : staff.staffType,
          'dateOfEmployment': staff.dateOfEmployment,
          'basicSalary': basicSalary,
          'payrollBasis': payrollBasis,
          'isPerPeriodPay': isPerPeriodPay,
          'periodsWorked': periodsWorked,
          'periodRate': periodRate,
          'totalIncentives': totalIncentives,
          'loanDeduction': loanDeduction,
          'loanArrears': loanArrears,
          'totalDeductions': totalDeductions,
          'netSalary': netSalary,
          'arrears': arrears,
          'totalPayable': totalPayable,
          'owingBroughtForward': owingBroughtForward,
          'owingFromMonth': owing?['fromMonth'],
          'owingCarried': owingCarried,
          'isSettled': isSettled,
          'paidWithMonth': paidWithMonth,
          'isPaid': _paymentStatus[staff.id] ?? false,
          'bankName': staff.bankName ?? '',
          'accountName': staff.accountName ?? '',
          'accountNumber': staff.accountNumber ?? '',
          // Include detailed lists for display
          'incentivesList': staffIncentivesList,
          'loansList': staffLoansList,
          'loanPlanEntries': loanPlanEntries,
          'loanSkipEntries': loanSkipEntries,
          'deductionsList': staffDeductionsList,
        });
      }

      // Sort by name
      payrollData.sort((a, b) => (a['staffName'] as String).compareTo(b['staffName'] as String));

      setState(() {
        _payrollData = payrollData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredPayrollData {
    if (_paymentFilter == 'all') return _payrollData;
    return _payrollData.where((staff) {
      final isPaid = _paymentStatus[staff['id'] as int] ?? false;
      return _paymentFilter == 'paid' ? isPaid : !isPaid;
    }).toList();
  }

  String _skipModeLabel(String mode) =>
      mode == 'carry' ? 'carried to next salary' : 'loan extended';

  String? _encodeLoanSkips(Map<int, Map<String, dynamic>> skips) => skips.isEmpty
      ? null
      : jsonEncode({for (final e in skips.entries) e.key.toString(): e.value});

  /// Lets a staff member skip one loan's repayment on this month's salary,
  /// choosing per skip whether the loan runs a month longer or the amount
  /// is collected with the next salary.
  Future<void> _showSkipLoanDialog(Map<String, dynamic> staff, Map<String, dynamic> entry) async {
    final loan = entry['loan'] as Map<String, dynamic>;
    final months = entry['months'] as List<String>;
    final perMonth = (loan['deductionPerMonth'] as num).toDouble();
    final amount = perMonth * months.length;
    final noteController = TextEditingController();
    String mode = 'extend';

    Widget option(StateSetter setDialogState, String value, String title, String subtitle) {
      final selected = mode == value;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? Colors.blue : Colors.grey,
        ),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        onTap: () => setDialogState(() => mode = value),
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Skip Loan Repayment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${staff['staffName']} — ${loan['reason'] ?? 'Loan'}\n'
                  '${_currencyFormat.format(amount)} will not be deducted from the '
                  '$_selectedMonth salary (${months.join(', ')}).',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('How should it be repaid?', style: TextStyle(fontWeight: FontWeight.bold)),
                option(
                  setDialogState,
                  'extend',
                  'Extend the loan',
                  'Same ${_currencyFormat.format(perMonth)}/month; the loan finishes '
                      '${months.length} month${months.length > 1 ? 's' : ''} later.',
                ),
                option(
                  setDialogState,
                  'carry',
                  'Add to next salary',
                  'Next salary deducts ${_currencyFormat.format(amount)} extra on top '
                      'of its own repayment.',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'e.g. Staff request — family emergency',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Skip This Month'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final staffId = staff['id'] as int;
    final prefs = await SharedPreferences.getInstance();
    final payment = await _repoDb.getStaffSalaryPayment(staffId, _selectedMonth);
    final skips = _dbHelper.parseLoanSkips(payment?['loanSkips'] as String?);
    skips[loan['id'] as int] = {
      'mode': mode,
      'note': noteController.text.trim().isEmpty ? null : noteController.text.trim(),
      'by': prefs.getString('username'),
      'at': DateTime.now().toIso8601String(),
    };
    await _repoDb.setLoanSkipsForPayment(staffId, _selectedMonth, _encodeLoanSkips(skips));
    await _loadPayrollData(showSpinner: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loan repayment skipped for $_selectedMonth (${_skipModeLabel(mode)}).')),
      );
    }
  }

  Future<void> _undoLoanSkip(Map<String, dynamic> staff, Map<String, dynamic> entry) async {
    final staffId = staff['id'] as int;
    final loanId = (entry['loan'] as Map<String, dynamic>)['id'] as int;
    final payment = await _repoDb.getStaffSalaryPayment(staffId, _selectedMonth);
    final skips = _dbHelper.parseLoanSkips(payment?['loanSkips'] as String?)..remove(loanId);
    await _repoDb.setLoanSkipsForPayment(staffId, _selectedMonth, _encodeLoanSkips(skips));
    await _loadPayrollData(showSpinner: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loan skip removed — repayment will be deducted.')),
      );
    }
  }

  String _shortMonth(String month) =>
      DateFormat('MMM yyyy').format(DateFormat('MMMM yyyy').parse(month)).toUpperCase();

  String _shiftMonth(String month, int by) {
    final d = DateFormat('MMMM yyyy').parse(month);
    return DateFormat('MMMM yyyy').format(DateTime(d.year, d.month + by, 1));
  }

  /// The later salary (if any) that has already deducted the amount this
  /// month's settlement carried forward: the first paid/settled month after
  /// [_selectedMonth], since every month in between is unpaid.
  Future<String?> _salaryUsingOwing(int staffId) async {
    final payments = await _repoDb.getSalaryPaymentsForStaff(staffId);
    final paidMonths = {
      for (final p in payments)
        if ((p['isPaid'] as int? ?? 0) == 1) p['month'] as String: p['paidWithMonth'] as String?,
    };
    for (int i = 1; i <= 24; i++) {
      final m = _shiftMonth(_selectedMonth, i);
      if (paidMonths.containsKey(m)) return paidMonths[m] ?? m;
    }
    return null;
  }

  Widget _buildPaymentStatusChip(Map<String, dynamic> staff, int staffDbId, bool isPaid) {
    final payable = (staff['totalPayable'] as num? ?? 0).toDouble();
    final isSettled = staff['isSettled'] == true;
    final paidWithMonth = staff['paidWithMonth'] as String?;
    final canSettle = !isPaid && payable < -0.005;
    final MaterialColor color = isSettled || canSettle
        ? Colors.deepOrange
        : isPaid
            ? Colors.green
            : Colors.red;
    final label = paidWithMonth != null
        ? 'PAID WITH ${_shortMonth(paidWithMonth)}'
        : isSettled
        ? 'SETTLED – OWING'
        : canSettle
            ? 'SETTLE & CARRY FORWARD'
            : isPaid
                ? 'PAID'
                : 'NOT PAID';
    final icon = isSettled || canSettle
        ? Icons.redo
        : isPaid
            ? Icons.check_circle
            : Icons.cancel;
    return InkWell(
      onTap: () => _togglePaymentStatus(staffDbId, isPaid),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePaymentStatus(int staffId, bool currentStatus) async {
    final newStatus = !currentStatus;

    // Find staff data to get loan info. Only genuinely 'Active' loans are
    // eligible for a new deduction here — a paid month's plan may include
    // a loan that has since completed (kept purely so the card still shows
    // its deduction), which must never be re-processed.
    final staffData = _payrollData.firstWhere(
      (s) => s['id'] == staffId,
      orElse: () => {},
    );
    final planEntries =
        staffData['loanPlanEntries'] as List<Map<String, dynamic>>? ?? [];
    final duePlan = planEntries
        .where((e) => (e['loan'] as Map<String, dynamic>)['status'] == 'Active')
        .toList();
    final hasActiveLoans = duePlan.isNotEmpty;
    final skippedPlan = (staffData['loanSkipEntries'] as List<Map<String, dynamic>>? ?? [])
        .where((e) => (e['loan'] as Map<String, dynamic>)['status'] == 'Active')
        .toList();

    // A negative total after every deduction means the staff owes the
    // school: the month is settled (closed, nothing paid) instead of paid,
    // and the amount owed is deducted in full from the next salary.
    final totalPayable = (staffData['totalPayable'] as num?)?.toDouble() ?? 0;
    final isSettle = newStatus && totalPayable < -0.005;
    final owingAmount = isSettle ? double.parse((-totalPayable).toStringAsFixed(2)) : 0.0;
    final nextMonth = _shiftMonth(_selectedMonth, 1);
    final wasSettled = !newStatus && staffData['isSettled'] == true;
    final owingCarried = (staffData['owingCarried'] as num?)?.toDouble() ?? 0;

    // A month paid as arrears with a later salary is undone from that salary
    final paidWithMonth = staffData['paidWithMonth'] as String?;
    if (!newStatus && paidWithMonth != null) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Paid With a Later Salary'),
          content: Text(
            'The $_selectedMonth salary was paid as arrears with the $paidWithMonth salary. '
            'Mark $paidWithMonth as Not Paid instead — that reopens this month too.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    // Earlier unpaid months this salary pays as arrears — closed with it so
    // they can't be paid a second time later. (Per-Period pay has no salary
    // arrears.)
    final arrearsMonths = newStatus && staffData['isPerPeriodPay'] != true
        ? await _dbHelper.getSalaryArrearsMonths(
            staffId,
            _selectedMonth,
            employmentDate: staffData['dateOfEmployment'] as String?,
          )
        : <String>[];
    if (!mounted) return;

    // Undoing a settlement is only safe while the next salary hasn't
    // already deducted the amount it carried forward.
    if (wasSettled) {
      final usedBy = await _salaryUsingOwing(staffId);
      if (usedBy != null) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cannot Undo Settlement'),
            content: Text(
              'The ${_currencyFormat.format(owingCarried)} owed from $_selectedMonth has already '
              'been deducted from the $usedBy salary. Mark $usedBy as Not Paid first, '
              'then undo this month.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        return;
      }
      if (!mounted) return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSettle
            ? 'Settle & Carry Forward?'
            : newStatus
                ? 'Mark as Paid?'
                : 'Mark as Not Paid?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSettle
                  ? 'After all deductions, the net salary for $_selectedMonth is '
                      '${_currencyFormat.format(totalPayable)}, so nothing will be paid. '
                      'The deductions below will be applied and the '
                      '${_currencyFormat.format(owingAmount)} owing will be deducted from '
                      'the $nextMonth salary.'
                  : newStatus
                      ? 'This will mark the staff as paid for $_selectedMonth.'
                      : wasSettled
                          ? 'This will undo the settlement for $_selectedMonth. Loan '
                              'deductions are reversed and the '
                              '${_currencyFormat.format(owingCarried)} owing is no longer '
                              'carried to the next salary.'
                          : 'This will mark the staff as NOT paid for $_selectedMonth.',
            ),
            if (arrearsMonths.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Also closes ${arrearsMonths.join(', ')} — paid as arrears with this salary.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
            if (newStatus && hasActiveLoans) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Loan Deduction',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The following loan(s) will be automatically deducted:',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 4),
                    ...duePlan.map((e) {
                      final loan = e['loan'] as Map<String, dynamic>;
                      final months = e['months'] as List<String>;
                      final perMonth = (loan['deductionPerMonth'] as num).toDouble();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• ${loan['reason']}: ${_currencyFormat.format(perMonth * months.length)} '
                          'for ${months.join(', ')} (${loan['monthsRemaining']} months left)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
            if (newStatus && skippedPlan.isNotEmpty) ...[
              const SizedBox(height: 12),
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
                    Text(
                      'Skipped this month (not deducted):',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    ...skippedPlan.map((e) {
                      final loan = e['loan'] as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• ${loan['reason']}: ${_skipModeLabel(e['mode'] as String)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isSettle
                  ? Colors.deepOrange
                  : newStatus
                      ? Colors.green
                      : Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(isSettle
                ? 'Settle'
                : newStatus
                    ? 'Mark Paid'
                    : 'Mark Not Paid'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _repoDb.toggleStaffSalaryPayment(staffId, _selectedMonth, newStatus);

      var loanReversed = false;

      // If marking as paid, deduct each due loan for exactly the months
      // its plan covers (this month + missed months since the loan started).
      if (newStatus && hasActiveLoans) {
        // Record which months were taken off each loan so marking this
        // payment NOT PAID later can restore precisely those months, and so
        // a later payment for one of those months doesn't deduct them again.
        final Map<String, List<String>> deductionsApplied = {};

        for (final e in duePlan) {
          final loan = e['loan'] as Map<String, dynamic>;
          final current = (loan['monthsRemaining'] as int);
          final months = (e['months'] as List<String>).take(current).toList();
          final newMonthsRemaining = current - months.length;

          await _repoDb.updateStaffLoan(loan['id'], {
            'monthsRemaining': newMonthsRemaining,
            'status': newMonthsRemaining <= 0 ? 'Completed' : 'Active',
          });

          if (months.isNotEmpty) {
            deductionsApplied[loan['id'].toString()] = months;
          }
        }

        if (deductionsApplied.isNotEmpty) {
          await _repoDb.setLoanDeductionsAppliedForPayment(
            staffId,
            _selectedMonth,
            jsonEncode(deductionsApplied),
          );
        }
      }

      // Freeze which loan months each skip postponed, so later salaries
      // know to leave them (extended loan) or collect them (carried over).
      if (newStatus && skippedPlan.isNotEmpty) {
        final payment = await _repoDb.getStaffSalaryPayment(staffId, _selectedMonth);
        final skips = _dbHelper.parseLoanSkips(payment?['loanSkips'] as String?);
        for (final e in skippedPlan) {
          final loanId = (e['loan'] as Map<String, dynamic>)['id'] as int;
          skips[loanId]?['months'] = e['months'];
        }
        await _repoDb.setLoanSkipsForPayment(staffId, _selectedMonth, _encodeLoanSkips(skips));
      }

      if (arrearsMonths.isNotEmpty) {
        await _repoDb.markSalaryMonthsPaidWith(staffId, arrearsMonths, _selectedMonth);
      } else if (!newStatus) {
        await _repoDb.reopenSalaryMonthsPaidWith(staffId, _selectedMonth);
      }

      if (isSettle) {
        await _repoDb.setOwingCarriedForwardForPayment(staffId, _selectedMonth, owingAmount);
      } else if (wasSettled) {
        await _repoDb.setOwingCarriedForwardForPayment(staffId, _selectedMonth, null);
      }

      if (!newStatus) {
        // Undo: restore whatever was deducted from loans when this staff
        // was marked paid for this month, so a mistaken mark-paid doesn't
        // permanently consume loan months. The loan stays pending until
        // the staff is genuinely due and marked paid again.
        final existingPayment = await _repoDb.getStaffSalaryPayment(staffId, _selectedMonth);
        final appliedJson = existingPayment?['loanDeductionsApplied'] as String?;

        if (appliedJson != null && appliedJson.isNotEmpty) {
          final applied = _dbHelper.parseLoanDeductionsApplied(appliedJson, _selectedMonth);
          for (final entry in applied.entries) {
            final loanId = entry.key;
            final monthsToRestore = entry.value.length;

            final loan = await _repoDb.getStaffLoanById(loanId);
            if (loan == null) continue;

            final restoredMonths = (loan['monthsRemaining'] as int) + monthsToRestore;
            await _repoDb.updateStaffLoan(loanId, {
              'monthsRemaining': restoredMonths,
              'status': 'Active',
            });
          }

          await _repoDb.setLoanDeductionsAppliedForPayment(staffId, _selectedMonth, null);
          loanReversed = true;
        }
      }

      // Reload data to reflect loan changes without resetting scroll position
      await _loadPayrollData(showSpinner: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSettle
                  ? 'Settled. ${_currencyFormat.format(owingAmount)} owing carried to the '
                      '$nextMonth salary.'
                  : newStatus
                  ? hasActiveLoans
                      ? 'Staff marked as paid. Loan deduction applied.'
                      : 'Staff marked as paid'
                  : loanReversed
                      ? 'Staff marked as not paid. Loan deduction reversed.'
                      : 'Staff marked as not paid',
            ),
            backgroundColor: isSettle
                ? Colors.deepOrange
                : newStatus
                    ? Colors.green
                    : Colors.orange,
          ),
        );
      }
    }
  }

  void _selectMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateFormat('MMMM yyyy').format(picked);
      });
      _loadPayrollData();
    }
  }

  String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  String _basisSummary(Map<String, dynamic>? basis) {
    if (basis == null) return 'Full Payment (100%)';
    final type = basis['basisType'] as String? ?? 'full';
    switch (type) {
      case 'per_period':
        return 'Per-Period Pay';
      case 'percentage':
        final pct = (basis['percentageValue'] as num?)?.toDouble() ?? 100;
        return '${_fmtNum(pct)}% of Salary';
      case 'days':
      case 'weeks':
        final total = (basis['totalUnits'] as num?)?.toDouble() ?? 0;
        final worked = (basis['workedUnits'] as num?)?.toDouble() ?? 0;
        final pct = total > 0 ? (worked / total * 100) : 100;
        final unit = type == 'days' ? 'Working Days' : 'Working Weeks';
        return '${_fmtNum(worked)}/${_fmtNum(total)} $unit (${pct.toStringAsFixed(0)}%)';
      case 'full':
      default:
        return 'Full Payment (100%)';
    }
  }

  Widget _basisRadioTile(String value, String label, String groupValue, ValueChanged<String> onChanged) {
    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onChanged: (v) => onChanged(v!),
    );
  }

  Widget _unitsFields(
    TextEditingController totalController,
    TextEditingController workedController,
    String totalLabel,
    String workedLabel,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: totalController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: totalLabel, isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: workedController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: workedLabel, isDense: true),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the payment-basis picker. When [staffId] is null this sets the
  /// month-wide default (used by every staff member without their own
  /// override); otherwise it sets/clears an override for that one staff
  /// member only, for [_selectedMonth].
  Future<void> _showBasisDialog({int? staffId, String? staffName}) async {
    Map<String, dynamic> current;
    bool hasOverride = false;
    if (staffId != null) {
      current = await _dbHelper.resolvePayrollBasis(staffId, _selectedMonth);
      hasOverride = current['isOverride'] == true;
    } else {
      current = _monthBasis ?? {'basisType': 'full'};
    }
    if (!mounted) return;

    String basisType = current['basisType'] as String? ?? 'full';
    final defaultTotalDays = _dbHelper.getWorkingDaysInMonth(_selectedMonth).toDouble();

    final percentageController = TextEditingController(
      text: _fmtNum((current['percentageValue'] as num?)?.toDouble() ?? 100),
    );
    final totalController = TextEditingController(
      text: _fmtNum(
        (current['totalUnits'] as num?)?.toDouble() ?? (basisType == 'weeks' ? 4 : defaultTotalDays),
      ),
    );
    final workedController = TextEditingController(
      text: _fmtNum(
        (current['workedUnits'] as num?)?.toDouble() ?? (basisType == 'weeks' ? 4 : defaultTotalDays),
      ),
    );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(staffId == null ? 'Payment Basis — $_selectedMonth' : 'Payment Basis: $staffName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      staffId == null
                          ? 'Default basis applied to staff paid this month. Individual staff can still be overridden below.'
                          : hasOverride
                              ? 'Overriding the month default for this staff member only.'
                              : 'Currently using the month default (${_basisSummary(_monthBasis)}). Choosing a basis here overrides it for this staff member only.',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  _basisRadioTile(
                    'full',
                    'Full Payment (100%)',
                    basisType,
                    (v) => setDialogState(() => basisType = v),
                  ),
                  _basisRadioTile(
                    'percentage',
                    'Percentage of Salary',
                    basisType,
                    (v) => setDialogState(() => basisType = v),
                  ),
                  if (basisType == 'percentage')
                    Padding(
                      padding: const EdgeInsets.only(left: 32, bottom: 8),
                      child: TextField(
                        controller: percentageController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Percentage (%)', isDense: true),
                      ),
                    ),
                  _basisRadioTile(
                    'days',
                    'Number of Working Days (Mon–Fri)',
                    basisType,
                    (v) => setDialogState(() => basisType = v),
                  ),
                  if (basisType == 'days')
                    _unitsFields(totalController, workedController, 'Total Working Days', 'Days Worked'),
                  _basisRadioTile(
                    'weeks',
                    'Number of Working Weeks (~4/month)',
                    basisType,
                    (v) => setDialogState(() => basisType = v),
                  ),
                  if (basisType == 'weeks')
                    _unitsFields(totalController, workedController, 'Total Working Weeks', 'Weeks Worked'),
                ],
              ),
            ),
            actions: [
              if (staffId != null && hasOverride)
                TextButton(
                  onPressed: () async {
                    await _dbHelper.clearStaffPayrollBasisOverride(staffId, _selectedMonth);
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadPayrollData(showSpinner: false);
                  },
                  child: const Text('Use Month Default'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final percentageValue = double.tryParse(percentageController.text);
                  final totalUnits = double.tryParse(totalController.text);
                  final workedUnits = double.tryParse(workedController.text);
                  final isUnitsBasis = basisType == 'days' || basisType == 'weeks';

                  if (staffId == null) {
                    await _dbHelper.setPayrollMonthBasis(
                      _selectedMonth,
                      basisType: basisType,
                      percentageValue: basisType == 'percentage' ? percentageValue : null,
                      totalUnits: isUnitsBasis ? totalUnits : null,
                      workedUnits: isUnitsBasis ? workedUnits : null,
                    );
                  } else {
                    await _dbHelper.setStaffPayrollBasisOverride(
                      staffId,
                      _selectedMonth,
                      basisType: basisType,
                      percentageValue: basisType == 'percentage' ? percentageValue : null,
                      totalUnits: isUnitsBasis ? totalUnits : null,
                      workedUnits: isUnitsBasis ? workedUnits : null,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadPayrollData(showSpinner: false);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Opens the periods-worked entry dialog for a Per-Period staff member for
  /// [_selectedMonth] — periodsWorked × periodRate is computed and saved as
  /// that month's payable basic pay.
  Future<void> _showPeriodDialog({
    required int staffId,
    required String staffName,
    required double currentPeriodsWorked,
    required double currentPeriodRate,
  }) async {
    final periodsController = TextEditingController(
      text: currentPeriodsWorked > 0 ? _fmtNum(currentPeriodsWorked) : '',
    );
    final rateController = TextEditingController(
      text: currentPeriodRate > 0 ? _fmtNum(currentPeriodRate) : '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final periods = double.tryParse(periodsController.text) ?? 0;
          final rate = double.tryParse(rateController.text) ?? 0;
          return AlertDialog(
            title: Text('Periods This Month: $staffName'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the number of periods taken in $_selectedMonth and the agreed rate per period.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: periodsController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Periods Taken', isDense: true, border: OutlineInputBorder()),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rate per Period',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixText: 'N ',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Amount to Pay', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        _currencyFormat.format(periods * rate),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _dbHelper.setStaffPeriodRecord(
                    staffId,
                    _selectedMonth,
                    periodsWorked: periods,
                    periodRate: rate,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadPayrollData(showSpinner: false);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sharePayslip(Map<String, dynamic> staff) async {
    try {
      await PdfExportHelper.exportPdf(
        context,
        shareSubject: 'Payslip - ${staff['staffName']} - $_selectedMonth',
        successMessage: 'Payslip exported successfully!',
        generate: ({required saveToDownloads}) async {
          final schoolProfile = await _dbHelper.getSchoolProfile();
          return StaffPayslipPDFGenerator.generatePayslipPDF(
            staff: staff,
            month: _selectedMonth,
            schoolProfile: schoolProfile ?? {},
            saveToDownloads: saveToDownloads,
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share payslip: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportToPDF() async {
    if (_payrollData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No payroll data to export')),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      await PdfExportHelper.exportPdf(
        context,
        shareSubject: 'Staff Payroll - $_selectedMonth',
        successMessage: 'Staff payroll exported successfully!',
        generate: ({required saveToDownloads}) async {
          final schoolProfile = await _dbHelper.getSchoolProfile();
          return StaffPayrollPDFGenerator.generatePayrollPDF(
            payrollData: _payrollData,
            month: _selectedMonth,
            schoolProfile: schoolProfile ?? {},
            saveToDownloads: saveToDownloads,
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showStaffPayrollDetails(Map<String, dynamic> staff) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(staff['staffName'] ?? 'Payroll Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailCard(
                'Earnings',
                Colors.green,
                [
                  _detailRow('Basic Salary', _currencyFormat.format(staff['basicSalary'])),
                  _detailRow(
                    'Payment Basis',
                    _basisSummary(staff['payrollBasis'] as Map<String, dynamic>?),
                  ),
                  _detailRow('Incentives/Grants', _currencyFormat.format(staff['totalIncentives'])),
                  if ((staff['arrears'] as num? ?? 0) > 0)
                    _detailRow(
                      'Salary Arrears (prev. months)',
                      _currencyFormat.format(staff['arrears']),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailCard(
                'Deductions',
                Colors.red,
                [
                  _detailRow(
                    (staff['loanArrears'] as num? ?? 0) > 0
                        ? 'Loan (this month)'
                        : 'Loan Deduction',
                    _currencyFormat.format(staff['loanDeduction']),
                  ),
                  if ((staff['loanArrears'] as num? ?? 0) > 0) ...[
                    _detailRow(
                      'Loan Arrears (missed months)',
                      _currencyFormat.format(staff['loanArrears']),
                    ),
                    _detailRow(
                      'Total Loan Clearing',
                      _currencyFormat.format(
                        (staff['loanDeduction'] as num).toDouble() +
                        (staff['loanArrears'] as num? ?? 0).toDouble(),
                      ),
                    ),
                  ],
                  _detailRow('Penalties', _currencyFormat.format(staff['totalDeductions'])),
                  if ((staff['owingBroughtForward'] as num? ?? 0) > 0)
                    _detailRow(
                      'Owing from ${staff['owingFromMonth']}',
                      _currencyFormat.format(staff['owingBroughtForward']),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      (staff['arrears'] as num? ?? 0) > 0 ? 'Total Payable' : 'Net Salary',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      _currencyFormat.format(
                        staff['totalPayable'] ?? staff['netSalary'],
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildDetailCard(
                'Bank Account Details',
                Colors.grey,
                [
                  _detailRow('Bank Name', staff['bankName'] ?? 'Not provided'),
                  _detailRow('Account Name', staff['accountName'] ?? 'Not provided'),
                  _detailRow('Account Number', staff['accountNumber'] ?? 'Not provided'),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String title, Color color, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => QuickAccessScaffold(
        group: QuickAccessGroup.viewStaff,
        currentId: 'payroll',
        child: _buildScreenContent(context),
      );

  Widget _buildScreenContent(BuildContext context) {
    // Calculate totals
    double totalBasicSalary = 0;
    double totalIncentives = 0;
    double totalLoanDeductions = 0;
    double totalPenalties = 0;
    double totalArrears = 0;
    double totalPayable = 0;

    for (var staff in _filteredPayrollData) {
      totalBasicSalary += (staff['basicSalary'] as num).toDouble();
      totalIncentives += (staff['totalIncentives'] as num).toDouble();
      totalLoanDeductions += (staff['loanDeduction'] as num).toDouble()
          + (staff['loanArrears'] as num? ?? 0).toDouble();
      totalPenalties += (staff['totalDeductions'] as num).toDouble();
      totalArrears += (staff['arrears'] as num? ?? 0).toDouble();
      final payable = (staff['totalPayable'] as num? ?? staff['netSalary'] as num).toDouble();
      // Staff who owe are paid nothing; a month paid with a later salary is
      // already counted in that salary.
      if (staff['paidWithMonth'] == null) totalPayable += payable > 0 ? payable : 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Payroll'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _selectMonth,
            tooltip: 'Select Month',
          ),
          if (!_isExporting)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: _exportToPDF,
              tooltip: 'Export to PDF',
            )
          else
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Month and summary header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Column(
                    children: [
                      Text(
                        _selectedMonth,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _paymentFilter == 'all'
                            ? '${_payrollData.length} Staff Members'
                            : '${_filteredPayrollData.length} of ${_payrollData.length} Staff',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),

                      // Month-wide default payment basis (Full / Percentage / Days / Weeks)
                      InkWell(
                        onTap: () => _showBasisDialog(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.tune, size: 14, color: Colors.blue),
                              const SizedBox(width: 6),
                              Text(
                                'Basis: ${_basisSummary(_monthBasis)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.edit, size: 12, color: Colors.blue),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Payment filter chips
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _filterChip('All', 'all', Colors.blue),
                          const SizedBox(width: 8),
                          _filterChip('Paid', 'paid', Colors.green),
                          const SizedBox(width: 8),
                          _filterChip('Unpaid', 'unpaid', Colors.red),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _summaryChip('Basic', totalBasicSalary, Colors.grey),
                            const SizedBox(width: 8),
                            _summaryChip('Incentives', totalIncentives, Colors.green),
                            const SizedBox(width: 8),
                            _summaryChip('Loans', totalLoanDeductions, Colors.orange),
                            const SizedBox(width: 8),
                            _summaryChip('Penalties', totalPenalties, Colors.red),
                            if (totalArrears > 0) ...[
                              const SizedBox(width: 8),
                              _summaryChip('Arrears', totalArrears, Colors.deepOrange),
                            ],
                            const SizedBox(width: 8),
                            _summaryChip('Total Payable', totalPayable, Colors.blue),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Payroll list
                Expanded(
                  child: _filteredPayrollData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                _paymentFilter == 'all'
                                    ? 'No staff found'
                                    : 'No ${_paymentFilter == 'paid' ? 'paid' : 'unpaid'} staff for $_selectedMonth',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredPayrollData.length,
                          itemBuilder: (ctx, i) {
                            final staff = _filteredPayrollData[i];
                            final staffDbId = staff['id'] as int;
                            final totalPayableForStaff = (staff['totalPayable'] as num? ?? staff['netSalary'] as num).toDouble();
                            final arrears = (staff['arrears'] as num? ?? 0).toDouble();
                            final loanArrears = (staff['loanArrears'] as num? ?? 0).toDouble();
                            final owingBroughtForward = (staff['owingBroughtForward'] as num? ?? 0).toDouble();
                            final isPositive = totalPayableForStaff >= 0;
                            final isPaid = _paymentStatus[staffDbId] ?? false;

                            // Get detail lists
                            final incentivesList = staff['incentivesList'] as List<Map<String, dynamic>>? ?? [];
                            final loanPlanEntries = staff['loanPlanEntries'] as List<Map<String, dynamic>>? ?? [];
                            final loanSkipEntries = staff['loanSkipEntries'] as List<Map<String, dynamic>>? ?? [];
                            final deductionsList = staff['deductionsList'] as List<Map<String, dynamic>>? ?? [];

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                onTap: () => _showStaffPayrollDetails(staff),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  staff['staffName'] ?? '',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                Text(
                                                  'ID: ${staff['staffId']}',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                arrears > 0 ? 'Total Payable' : 'Net Salary',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              Text(
                                                _currencyFormat.format(totalPayableForStaff),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                  color: isPositive ? Colors.blue : Colors.red,
                                                ),
                                              ),
                                              if (arrears > 0)
                                                Text(
                                                  'incl. ${_currencyFormat.format(arrears)} arrears',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.deepOrange.shade600,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              if (staff['paidWithMonth'] != null)
                                                Text(
                                                  'paid with ${staff['paidWithMonth']} salary',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.green.shade700,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                )
                                              else if (staff['isSettled'] == true || (!isPaid && !isPositive))
                                                Text(
                                                  staff['isSettled'] == true
                                                      ? 'owing carried to next month'
                                                      : 'staff owes — settle to carry forward',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.deepOrange.shade600,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const Divider(),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          _miniStat('Basic', staff['basicSalary'], Colors.grey),
                                          _miniStat('+Incentive', staff['totalIncentives'], Colors.green),
                                          _miniStat(
                                            loanArrears > 0 ? '-Loan*' : '-Loan',
                                            (staff['loanDeduction'] as num).toDouble() + loanArrears,
                                            Colors.orange,
                                          ),
                                          _miniStat('-Penalty', staff['totalDeductions'], Colors.red),
                                          if (arrears > 0)
                                            _miniStat('+Arrears', arrears, Colors.deepOrange),
                                        ],
                                      ),

                                      // Per-staff payment basis (Full/Percentage/Days/Weeks) for
                                      // this month — Per-Period staff get a periods × rate entry
                                      // instead, since their pay isn't prorated off a fixed salary.
                                      const SizedBox(height: 8),
                                      if (staff['isPerPeriodPay'] == true)
                                        InkWell(
                                          onTap: () => _showPeriodDialog(
                                            staffId: staffDbId,
                                            staffName: staff['staffName'] ?? '',
                                            currentPeriodsWorked: (staff['periodsWorked'] as num? ?? 0).toDouble(),
                                            currentPeriodRate: (staff['periodRate'] as num? ?? 0).toDouble(),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.calculate, size: 12, color: Colors.grey.shade600),
                                              const SizedBox(width: 4),
                                              Text(
                                                (staff['periodsWorked'] as num? ?? 0) > 0
                                                    ? '${_fmtNum((staff['periodsWorked'] as num).toDouble())} periods × '
                                                        '${_currencyFormat.format(staff['periodRate'])} = '
                                                        '${_currencyFormat.format(staff['basicSalary'])}'
                                                    : 'Tap to enter periods taken this month',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(Icons.edit, size: 10, color: Colors.grey.shade500),
                                            ],
                                          ),
                                        )
                                      else
                                        InkWell(
                                          onTap: () => _showBasisDialog(
                                            staffId: staffDbId,
                                            staffName: staff['staffName'] ?? '',
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.tune, size: 12, color: Colors.grey.shade600),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Basis: ${_basisSummary(staff['payrollBasis'] as Map<String, dynamic>?)}'
                                                '${(staff['payrollBasis'] as Map<String, dynamic>?)?['isOverride'] == true ? ' (override)' : ''}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(Icons.edit, size: 10, color: Colors.grey.shade500),
                                            ],
                                          ),
                                        ),

                                      // Show details for the month (Incentives, Loans, Penalties)
                                      if (incentivesList.isNotEmpty ||
                                          loanPlanEntries.isNotEmpty ||
                                          loanSkipEntries.isNotEmpty ||
                                          owingBroughtForward > 0 ||
                                          deductionsList.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Details for $_selectedMonth',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              // Incentives
                                              if (incentivesList.isNotEmpty)
                                                ...incentivesList.map((inc) => Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.add_circle, size: 12, color: Colors.green.shade600),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          inc['description'] ?? 'Incentive',
                                                          style: const TextStyle(fontSize: 11),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        _currencyFormat.format(inc['amount']),
                                                        style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w500),
                                                      ),
                                                    ],
                                                  ),
                                                )),
                                              // Loans (Skip only while this month is unpaid)
                                              ...loanPlanEntries.map((e) {
                                                final loan = e['loan'] as Map<String, dynamic>;
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.remove_circle, size: 12, color: Colors.orange.shade600),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          'Loan: ${loan['reason'] ?? 'Deduction'} (${loan['monthsRemaining']} months left)',
                                                          style: const TextStyle(fontSize: 11),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      if (!isPaid && loan['status'] == 'Active')
                                                        InkWell(
                                                          onTap: () => _showSkipLoanDialog(staff, e),
                                                          child: Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                                            child: Text(
                                                              'Skip',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors.blue.shade700,
                                                                fontWeight: FontWeight.w600,
                                                                decoration: TextDecoration.underline,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      Text(
                                                        '-${_currencyFormat.format(loan['deductionPerMonth'])}',
                                                        style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                              ...loanSkipEntries.map((e) {
                                                final loan = e['loan'] as Map<String, dynamic>;
                                                final note = e['note'] as String?;
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.pause_circle, size: 12, color: Colors.blue.shade600),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          'Loan skipped: ${loan['reason'] ?? 'Loan'} — '
                                                          '${_skipModeLabel(e['mode'] as String)}'
                                                          '${note != null && note.isNotEmpty ? ' ($note)' : ''}',
                                                          style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      if (!isPaid)
                                                        InkWell(
                                                          onTap: () => _undoLoanSkip(staff, e),
                                                          child: Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                                            child: Text(
                                                              'Undo',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors.blue.shade700,
                                                                fontWeight: FontWeight.w600,
                                                                decoration: TextDecoration.underline,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      Text(
                                                        _currencyFormat.format(0),
                                                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                              if (loanArrears > 0)
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.warning_amber, size: 12, color: Colors.deepOrange.shade600),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          'Loan arrears (missed months)',
                                                          style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade700),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        '-${_currencyFormat.format(loanArrears)}',
                                                        style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade700, fontWeight: FontWeight.w500),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (owingBroughtForward > 0)
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.redo, size: 12, color: Colors.deepOrange.shade600),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          'Owing from ${staff['owingFromMonth']}',
                                                          style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade700),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        '-${_currencyFormat.format(owingBroughtForward)}',
                                                        style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade700, fontWeight: FontWeight.w500),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              // Deductions/Penalties
                                              if (deductionsList.isNotEmpty)
                                                ...deductionsList.map((ded) => Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.remove_circle, size: 12, color: Colors.red.shade600),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          '${ded['reason'] ?? 'Penalty'}',
                                                          style: const TextStyle(fontSize: 11),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        '-${_currencyFormat.format(ded['amount'])}',
                                                        style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w500),
                                                      ),
                                                    ],
                                                  ),
                                                )),
                                            ],
                                          ),
                                        ),
                                      ],

                                      if (staff['bankName'] != null && staff['bankName'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.account_balance, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${staff['bankName']} - ${staff['accountNumber']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],

                                      // Share Payslip + Paid/Not Paid Toggle Buttons
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () => _sharePayslip(staff),
                                            icon: const Icon(Icons.share, size: 16),
                                            label: const Text('Payslip'),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildPaymentStatusChip(staff, staffDbId, isPaid),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Payment Summary Card at bottom
                _buildPaymentSummaryCard(),
              ],
            ),
    );
  }

  Widget _buildPaymentSummaryCard() {
    // Calculate payment statistics
    int totalStaff = _payrollData.length;
    int paidCount = 0;
    int unpaidCount = 0;
    double totalPaidAmount = 0;
    double totalUnpaidAmount = 0;

    for (var staff in _payrollData) {
      final staffId = staff['id'] as int;
      final staffPayable = (staff['totalPayable'] as num? ?? staff['netSalary'] as num).toDouble();
      final isPaid = _paymentStatus[staffId] ?? false;

      // Staff who owe (negative total) are paid nothing, settled or not.
      final payout = staffPayable > 0 && staff['paidWithMonth'] == null ? staffPayable : 0.0;
      if (isPaid) {
        paidCount++;
        totalPaidAmount += payout;
      } else {
        unpaidCount++;
        totalUnpaidAmount += payout;
      }
    }

    if (totalStaff == 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Payment Summary - $_selectedMonth',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _paymentStatBox(
                'Total Staff',
                totalStaff.toString(),
                Colors.blue,
                Icons.people,
              ),
              _paymentStatBox(
                'Paid',
                '$paidCount',
                Colors.green,
                Icons.check_circle,
              ),
              _paymentStatBox(
                'Unpaid',
                '$unpaidCount',
                Colors.red,
                Icons.cancel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text(
                    'Total Paid',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    _currencyFormat.format(totalPaidAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  const Text(
                    'Outstanding',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    _currencyFormat.format(totalUnpaidAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  const Text(
                    'Total Payroll',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    _currencyFormat.format(totalPaidAmount + totalUnpaidAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentStatBox(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value, Color color) {
    final isSelected = _paymentFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  Widget _summaryChip(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color),
          ),
          Text(
            _currencyFormat.format(value),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, dynamic value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color),
        ),
        Text(
          _currencyFormat.format(value),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
