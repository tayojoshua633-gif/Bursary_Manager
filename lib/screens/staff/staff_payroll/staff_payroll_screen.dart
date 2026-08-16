// lib/screens/staff/staff_payroll/staff_payroll_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/database_helper_wrapper.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import '../../../utils/staff_payroll_pdf_generator.dart';

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
      final paymentRecordByStaffId = <int, Map<String, dynamic>>{};
      for (var payment in salaryPayments) {
        final sid = payment['staffId'] as int;
        _paymentStatus[sid] = (payment['isPaid'] as int) == 1;
        paymentRecordByStaffId[sid] = payment;
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

      // Get incentives, loans, and deductions for the month. Loans are
      // fetched regardless of status so a loan that gets fully paid off this
      // month (status flips to 'Completed') can still be shown as deducted
      // for the month it completed in, instead of vanishing from the card.
      final incentives = await _repoDb.getStaffIncentivesByMonth(_selectedMonth);
      final allLoans = await _repoDb.getAllStaffLoans();
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

        // Get active loan deductions for this staff (for details display)
        final staffLoansList = allLoans
            .where((l) => l['staffId'] == staff.id && l['status'] == 'Active')
            .toList();

        // If this staff was already marked paid for this month and had loan
        // deductions applied, keep showing those loans for this month even
        // if they've since flipped to 'Completed' — otherwise the deduction
        // (and the amount actually paid) silently disappears from the card.
        final appliedJson =
            paymentRecordByStaffId[staff.id]?['loanDeductionsApplied'] as String?;
        if (appliedJson != null && appliedJson.isNotEmpty) {
          try {
            final Map<String, dynamic> applied = jsonDecode(appliedJson);
            for (final loanIdStr in applied.keys) {
              final loanId = int.tryParse(loanIdStr);
              if (loanId == null) continue;
              if (staffLoansList.any((l) => l['id'] == loanId)) continue;
              final completedLoan = allLoans.where((l) => l['id'] == loanId);
              if (completedLoan.isNotEmpty) {
                staffLoansList.add(completedLoan.first);
              }
            }
          } catch (_) {}
        }

        double loanDeduction = 0;
        for (var loan in staffLoansList) {
          loanDeduction += (loan['deductionPerMonth'] as num).toDouble();
        }

        // Get individual deductions/penalties for this staff (for details display)
        final staffDeductionsList = deductions
            .where((d) => d['staffId'] == staff.id)
            .toList();
        final totalDeductions = staffDeductionsList
            .fold<double>(0, (sum, d) => sum + (d['amount'] as num).toDouble());

        // Use salary history to get correct salary for this month, then
        // apply the resolved payroll basis (Full/Percentage/Days/Weeks)
        final basicSalary = await _dbHelper.getProratedBasicSalaryForMonth(
          staff.id!,
          _selectedMonth,
          fallbackSalary: staff.salary,
        );
        final payrollBasis = await _dbHelper.resolvePayrollBasis(staff.id!, _selectedMonth);

        // Calculate current-month net salary
        final netSalary = basicSalary + totalIncentives - loanDeduction - totalDeductions;

        // Calculate salary arrears from previous unpaid months
        final arrears = await _dbHelper.getSalaryArrearsForStaff(
          staff.id!,
          _selectedMonth,
          fallbackSalary: basicSalary,
          employmentDate: staff.dateOfEmployment,
        );

        // Calculate loan arrears (unpaid months loan accumulation)
        final loanArrears = await _dbHelper.getLoanArrearsForStaff(
          staff.id!,
          _selectedMonth,
          employmentDate: staff.dateOfEmployment,
        );

        // Total = current net + salary arrears (basic+incentives−deductions for
        // unpaid months) − loan arrears (loan is shown accumulated in the loan
        // column, so subtract here to avoid double-counting).
        // Mathematically equals: sum of NET salary for current + all unpaid months.
        final totalPayable = netSalary + arrears - loanArrears;

        payrollData.add({
          'id': staff.id, // Include database ID for payment tracking
          'staffId': staff.staffId,
          'staffName': staff.fullName,
          'dateOfEmployment': staff.dateOfEmployment,
          'basicSalary': basicSalary,
          'payrollBasis': payrollBasis,
          'totalIncentives': totalIncentives,
          'loanDeduction': loanDeduction,
          'loanArrears': loanArrears,
          'totalDeductions': totalDeductions,
          'netSalary': netSalary,
          'arrears': arrears,
          'totalPayable': totalPayable,
          'bankName': staff.bankName ?? '',
          'accountName': staff.accountName ?? '',
          'accountNumber': staff.accountNumber ?? '',
          // Include detailed lists for display
          'incentivesList': staffIncentivesList,
          'loansList': staffLoansList,
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

  Future<void> _togglePaymentStatus(int staffId, bool currentStatus) async {
    final newStatus = !currentStatus;

    // Find staff data to get loan info. Only genuinely 'Active' loans are
    // eligible for a new deduction here — staffData['loansList'] may also
    // include a loan that already completed this month (kept there purely
    // so the card still shows its deduction), which must never be
    // re-processed as if it still had months remaining.
    final staffData = _payrollData.firstWhere(
      (s) => s['id'] == staffId,
      orElse: () => {},
    );
    final allStaffLoans = staffData['loansList'] as List<Map<String, dynamic>>? ?? [];
    final loansList = allStaffLoans.where((l) => l['status'] == 'Active').toList();
    final hasActiveLoans = loansList.isNotEmpty;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newStatus ? 'Mark as Paid?' : 'Mark as Not Paid?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              newStatus
                  ? 'This will mark the staff as paid for $_selectedMonth.'
                  : 'This will mark the staff as NOT paid for $_selectedMonth.',
            ),
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
                    ...loansList.map((loan) {
                      final loanArrears = (staffData['loanArrears'] as double? ?? 0);
                      final arrearsMonths = loanArrears > 0
                          ? ' +${(loanArrears / (loan['deductionPerMonth'] as num).toDouble()).round()} arrears month(s)'
                          : '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• ${loan['reason']}: ${_currencyFormat.format(loan['deductionPerMonth'])}/month (${loan['monthsRemaining']} months left$arrearsMonths)',
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
              backgroundColor: newStatus ? Colors.green : Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(newStatus ? 'Mark Paid' : 'Mark Not Paid'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _repoDb.toggleStaffSalaryPayment(staffId, _selectedMonth, newStatus);

      var loanReversed = false;

      // If marking as paid, auto-deduct from active loans for this month +
      // any unpaid previous months (loan arrears)
      if (newStatus && hasActiveLoans) {
        final unpaidMonths = await _dbHelper.getUnpaidMonthsCount(
          staffId,
          _selectedMonth,
          employmentDate: staffData['dateOfEmployment'] as String?,
        );
        final monthsToDeduct = unpaidMonths + 1; // current month + arrears months

        // Track exactly how much was taken off each loan so marking this
        // payment NOT PAID later can restore precisely that amount instead
        // of the loan record permanently losing those months.
        final Map<String, int> deductionsApplied = {};

        for (var loan in loansList) {
          final current = (loan['monthsRemaining'] as int);
          final newMonthsRemaining = (current - monthsToDeduct).clamp(0, current);
          final actuallyDeducted = current - newMonthsRemaining;
          final newLoanStatus = newMonthsRemaining <= 0 ? 'Completed' : 'Active';

          await _repoDb.updateStaffLoan(loan['id'], {
            'monthsRemaining': newMonthsRemaining,
            'status': newLoanStatus,
          });

          if (actuallyDeducted > 0) {
            deductionsApplied[loan['id'].toString()] = actuallyDeducted;
          }
        }

        if (deductionsApplied.isNotEmpty) {
          await _repoDb.setLoanDeductionsAppliedForPayment(
            staffId,
            _selectedMonth,
            jsonEncode(deductionsApplied),
          );
        }
      } else if (!newStatus) {
        // Undo: restore whatever was deducted from loans when this staff
        // was marked paid for this month, so a mistaken mark-paid doesn't
        // permanently consume loan months. The loan stays pending until
        // the staff is genuinely due and marked paid again.
        final existingPayment = await _repoDb.getStaffSalaryPayment(staffId, _selectedMonth);
        final appliedJson = existingPayment?['loanDeductionsApplied'] as String?;

        if (appliedJson != null && appliedJson.isNotEmpty) {
          final Map<String, dynamic> applied = jsonDecode(appliedJson);
          for (final entry in applied.entries) {
            final loanId = int.tryParse(entry.key);
            final monthsToRestore = (entry.value as num).toInt();
            if (loanId == null) continue;

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
              newStatus
                  ? hasActiveLoans
                      ? 'Staff marked as paid. Loan deduction applied.'
                      : 'Staff marked as paid'
                  : loanReversed
                      ? 'Staff marked as not paid. Loan deduction reversed.'
                      : 'Staff marked as not paid',
            ),
            backgroundColor: newStatus ? Colors.green : Colors.orange,
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

  Future<void> _exportToPDF() async {
    if (_payrollData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No payroll data to export')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      // Get school profile
      final schoolProfile = await _dbHelper.getSchoolProfile();

      final filePath = await StaffPayrollPDFGenerator.generatePayrollPDF(
        payrollData: _payrollData,
        month: _selectedMonth,
        schoolProfile: schoolProfile ?? {},
      );

      if (mounted) {
        setState(() => _isExporting = false);

        // Share the file
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Staff Payroll - $_selectedMonth',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
  Widget build(BuildContext context) {
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
      totalPayable += (staff['totalPayable'] as num? ?? staff['netSalary'] as num).toDouble();
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
                            final isPositive = totalPayableForStaff >= 0;
                            final isPaid = _paymentStatus[staffDbId] ?? false;

                            // Get detail lists
                            final incentivesList = staff['incentivesList'] as List<Map<String, dynamic>>? ?? [];
                            final loansList = staff['loansList'] as List<Map<String, dynamic>>? ?? [];
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

                                      // Per-staff payment basis (Full/Percentage/Days/Weeks) for this month
                                      const SizedBox(height: 8),
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
                                      if (incentivesList.isNotEmpty || loansList.isNotEmpty || deductionsList.isNotEmpty) ...[
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
                                              // Loans
                                              if (loansList.isNotEmpty)
                                                ...loansList.map((loan) => Padding(
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
                                                      Text(
                                                        '-${_currencyFormat.format(loan['deductionPerMonth'])}',
                                                        style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                                                      ),
                                                    ],
                                                  ),
                                                )),
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

                                      // Paid/Not Paid Toggle Button
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          InkWell(
                                            onTap: () => _togglePaymentStatus(staffDbId, isPaid),
                                            borderRadius: BorderRadius.circular(20),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isPaid ? Colors.green.shade100 : Colors.red.shade100,
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: isPaid ? Colors.green : Colors.red,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    isPaid ? Icons.check_circle : Icons.cancel,
                                                    size: 18,
                                                    color: isPaid ? Colors.green.shade700 : Colors.red.shade700,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    isPaid ? 'PAID' : 'NOT PAID',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: isPaid ? Colors.green.shade700 : Colors.red.shade700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
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

      if (isPaid) {
        paidCount++;
        totalPaidAmount += staffPayable;
      } else {
        unpaidCount++;
        totalUnpaidAmount += staffPayable;
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
