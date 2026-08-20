// lib/screens/staff/staff_payroll/salary_payment_record_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/database_helper_wrapper.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import '../../../utils/salary_payment_pdf_generator.dart';
import '../../../utils/write_guard.dart';
import '../../expenses/expense_form_screen.dart';

class SalaryPaymentRecordScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const SalaryPaymentRecordScreen({super.key, required this.currentUser});

  @override
  State<SalaryPaymentRecordScreen> createState() => _SalaryPaymentRecordScreenState();
}

class _SalaryPaymentRecordScreenState extends State<SalaryPaymentRecordScreen> {
  final _dbHelper = DatabaseHelper();
  // Salary payments, loans, incentives, and deductions are wired through
  // the repository layer; payroll computation reads and the salary expense
  // posting ledger stay on DatabaseHelper directly — out of scope.
  final _repoDb = DatabaseHelperWrapper();
  final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  List<Map<String, dynamic>> _paymentRecords = [];
  String _selectedMonth = '';
  bool _isLoading = true;
  bool _isExporting = false;

  // Summary data
  int _totalStaff = 0;
  int _paidCount = 0;
  int _unpaidCount = 0;
  double _totalPaidAmount = 0;
  double _totalUnpaidAmount = 0;

  // How much of this month's paid salary has already been posted to Expenses
  double _totalPostedAmount = 0;

  @override
  void initState() {
    super.initState();
    WriteGuard.enforce(context);
    _selectedMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    _loadPaymentRecords();
  }

  Future<void> _loadPaymentRecords() async {
    setState(() => _isLoading = true);
    try {
      // Get all active staff
      final staffMaps = await _dbHelper.getStaff();

      // Get payment status for the month
      final salaryPayments = await _repoDb.getSalaryPaymentsByMonth(_selectedMonth);
      Map<int, Map<String, dynamic>> paymentMap = {};
      for (var payment in salaryPayments) {
        paymentMap[payment['staffId'] as int] = payment;
      }

      // Deactivated staff who were already paid/marked for this month keep
      // showing here so their historical payment record isn't lost.
      final inactiveStaffMaps = await _dbHelper.getInactiveStaff();
      final inactiveWithRecords =
          inactiveStaffMaps.where((m) => paymentMap.containsKey(m['id']));

      final staffList = [...staffMaps, ...inactiveWithRecords]
          .map((m) => Staff.fromMap(m))
          // Hide staff from months before they were employed (e.g. a staff
          // member hired this month shouldn't show up in prior months' records)
          // and from months after a (possibly back-dated) deactivation.
          .where((s) =>
              _dbHelper.isStaffEmployedByMonth(s.dateOfEmployment, _selectedMonth) &&
              _dbHelper.isStaffActiveByMonth(s.deactivationDate, _selectedMonth))
          .toList();

      // Get incentives, loans, deductions for calculations. Loans are
      // fetched regardless of status so a loan that gets fully paid off this
      // month (status flips to 'Completed') can still be shown as deducted
      // for the month it completed in, instead of vanishing from the record.
      final incentives = await _repoDb.getStaffIncentivesByMonth(_selectedMonth);
      final allLoans = await _repoDb.getAllStaffLoans();
      final deductions = await _repoDb.getStaffDeductionsByMonth(_selectedMonth);

      // Build payment records
      List<Map<String, dynamic>> records = [];
      _totalStaff = staffList.length;
      _paidCount = 0;
      _unpaidCount = 0;
      _totalPaidAmount = 0;
      _totalUnpaidAmount = 0;

      for (var staff in staffList) {
        final paymentInfo = paymentMap[staff.id];
        final isPaid = paymentInfo != null && (paymentInfo['isPaid'] as int) == 1;

        // Calculate salary components
        final staffIncentives = incentives
            .where((i) => i['staffId'] == staff.id)
            .fold<double>(0, (sum, i) => sum + (i['amount'] as num).toDouble());

        final staffLoans = allLoans
            .where((l) => l['staffId'] == staff.id && l['status'] == 'Active')
            .toList();

        // If this staff was already marked paid for this month and had loan
        // deductions applied, keep showing that loan for this month even if
        // it's since flipped to 'Completed' — otherwise the deduction (and
        // the amount actually paid) silently disappears from the record.
        final appliedJson = paymentInfo?['loanDeductionsApplied'] as String?;
        if (appliedJson != null && appliedJson.isNotEmpty) {
          try {
            final Map<String, dynamic> applied = jsonDecode(appliedJson);
            for (final loanIdStr in applied.keys) {
              final loanId = int.tryParse(loanIdStr);
              if (loanId == null) continue;
              if (staffLoans.any((l) => l['id'] == loanId)) continue;
              final completedLoan = allLoans.where((l) => l['id'] == loanId);
              if (completedLoan.isNotEmpty) {
                staffLoans.add(completedLoan.first);
              }
            }
          } catch (_) {}
        }

        double loanDeduction = 0;
        for (var loan in staffLoans) {
          loanDeduction += (loan['deductionPerMonth'] as num).toDouble();
        }

        final staffDeductions = deductions
            .where((d) => d['staffId'] == staff.id)
            .fold<double>(0, (sum, d) => sum + (d['amount'] as num).toDouble());

        // Use salary history for the correct salary in this month, then
        // apply the resolved payroll basis (Full/Percentage/Days/Weeks)
        final basicSalary = await _dbHelper.getProratedBasicSalaryForMonth(
          staff.id!,
          _selectedMonth,
          fallbackSalary: staff.salary,
        );
        final payrollBasis = await _dbHelper.resolvePayrollBasis(staff.id!, _selectedMonth);

        final netSalary = basicSalary + staffIncentives - loanDeduction - staffDeductions;

        // Arrears from previous unpaid months
        final arrears = await _dbHelper.getSalaryArrearsForStaff(
          staff.id!,
          _selectedMonth,
          fallbackSalary: basicSalary,
          employmentDate: staff.dateOfEmployment,
        );

        // Loan arrears from missed months
        final loanArrears = await _dbHelper.getLoanArrearsForStaff(
          staff.id!,
          _selectedMonth,
          employmentDate: staff.dateOfEmployment,
        );

        // Total = net (current) + salary arrears − loan arrears.
        // Loan arrears shown accumulated in loan column; subtract to avoid double-count.
        final totalPayable = netSalary + arrears - loanArrears;

        if (isPaid) {
          _paidCount++;
          _totalPaidAmount += totalPayable;
        } else {
          _unpaidCount++;
          _totalUnpaidAmount += totalPayable;
        }

        records.add({
          'id': staff.id,
          'staffId': staff.staffId,
          'staffName': staff.fullName,
          'basicSalary': basicSalary,
          'payrollBasis': payrollBasis,
          'incentives': staffIncentives,
          'loanDeduction': loanDeduction,
          'loanArrears': loanArrears,
          'penalties': staffDeductions,
          'netSalary': netSalary,
          'arrears': arrears,
          'totalPayable': totalPayable,
          'isPaid': isPaid,
          'paymentDate': paymentInfo?['paymentDate'],
          'paymentMethod': paymentInfo?['paymentMethod'],
          'bankName': staff.bankName ?? '',
          'accountNumber': staff.accountNumber ?? '',
        });
      }

      // Sort: paid first, then by name
      records.sort((a, b) {
        if (a['isPaid'] != b['isPaid']) {
          return (b['isPaid'] as bool) ? 1 : -1;
        }
        return (a['staffName'] as String).compareTo(b['staffName'] as String);
      });

      // How much of this month's paid salary has already been posted to
      // Expenses, so we can warn about duplicates / detect top-ups.
      final totalPosted = await _dbHelper.getTotalPostedForMonth(_selectedMonth);

      setState(() {
        _paymentRecords = records;
        _totalPostedAmount = totalPosted;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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
      _loadPaymentRecords();
    }
  }

  Future<void> _exportToPDF() async {
    if (_paymentRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No records to export')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final schoolProfile = await _dbHelper.getSchoolProfile();

      final filePath = await SalaryPaymentPDFGenerator.generateSalaryPaymentPDF(
        paymentRecords: _paymentRecords,
        month: _selectedMonth,
        schoolProfile: schoolProfile ?? {},
        totalStaff: _totalStaff,
        paidCount: _paidCount,
        unpaidCount: _unpaidCount,
        totalPaidAmount: _totalPaidAmount,
        totalUnpaidAmount: _totalUnpaidAmount,
      );

      if (mounted) {
        setState(() => _isExporting = false);
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Salary Payment Record - $_selectedMonth',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _postToExpenses() async {
    if (_totalPaidAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No paid salary to post for this month')),
      );
      return;
    }

    final delta = _totalPaidAmount - _totalPostedAmount;
    double amountToPost;

    if (_totalPostedAmount <= 0) {
      // Never posted before — confirm, then post the full amount.
      final confirmed = await _showConfirmPostDialog(_totalPaidAmount);
      if (confirmed != true) return;
      amountToPost = _totalPaidAmount;
    } else if (delta > 0.01) {
      // Already posted some, but more has been paid since (e.g. staff were
      // marked paid after rolling back to this month) — offer to post just
      // the new amount instead of duplicating the whole month.
      final choice = await _showTopUpDialog(delta);
      if (choice == null) return;
      amountToPost = choice;
    } else if (delta < -0.01) {
      // Posted more than the current paid total — likely a staff payment
      // was reversed after posting. Nothing new to post; just warn.
      await _showOverPostedWarning();
      return;
    } else {
      // Fully posted already and nothing has changed — guard against an
      // accidental duplicate post.
      final proceed = await _showAlreadyPostedDialog();
      if (proceed != true) return;
      amountToPost = _totalPaidAmount;
    }

    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          currentUser: widget.currentUser,
          initialAmount: amountToPost,
          initialCategory: 'Paid Salary',
          initialDescription: 'STAFF SALARY FOR ${_selectedMonth.toUpperCase()}',
        ),
      ),
    );

    if (result == true && mounted) {
      await _dbHelper.insertSalaryExpensePosting(
        month: _selectedMonth,
        amount: amountToPost,
        postedBy: widget.currentUser['username'] as String?,
      );
      final updatedPosted = await _dbHelper.getTotalPostedForMonth(_selectedMonth);
      if (mounted) {
        setState(() => _totalPostedAmount = updatedPosted);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_currencyFormat.format(amountToPost)} posted to Expenses for $_selectedMonth',
            ),
          ),
        );
      }
    }
  }

  Future<bool?> _showConfirmPostDialog(double amount) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post to Expenses'),
        content: Text(
          'Post ${_currencyFormat.format(amount)} in paid salaries for $_selectedMonth to Expenses?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }

  Future<double?> _showTopUpDialog(double delta) {
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Additional Salary Paid'),
        content: Text(
          'You already posted ${_currencyFormat.format(_totalPostedAmount)} to Expenses for '
          '$_selectedMonth. Since then, ${_currencyFormat.format(delta)} more has been paid '
          '(e.g. staff marked paid after rolling back to this month).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _totalPaidAmount),
            child: const Text('Post Full Amount'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, delta),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text('Post Additional Only'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showAlreadyPostedDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Already Posted'),
        content: Text(
          'You already posted ${_currencyFormat.format(_totalPostedAmount)} to Expenses for '
          '$_selectedMonth, and nothing has changed since then.\n\n'
          'Posting again will create a duplicate expense entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Post Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOverPostedWarning() {
    final diff = _totalPostedAmount - _totalPaidAmount;
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Posted Amount Exceeds Current Total'),
        content: Text(
          'You posted ${_currencyFormat.format(_totalPostedAmount)} to Expenses for $_selectedMonth, '
          'but the current paid total is only ${_currencyFormat.format(_totalPaidAmount)} '
          '(${_currencyFormat.format(diff)} less). This can happen if a staff payment was marked '
          'NOT PAID after the posting was made.\n\n'
          'Nothing new to post — you may want to review the Expenses entry for this month.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paidRecords = _paymentRecords.where((r) => r['isPaid'] == true).toList();
    final unpaidRecords = _paymentRecords.where((r) => r['isPaid'] == false).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salary Payment Record'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.post_add),
            onPressed: _postToExpenses,
            tooltip: 'Post to Expenses',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _selectMonth,
            tooltip: 'Select Month',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Month header and summary
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.teal.shade50,
                  child: Column(
                    children: [
                      Text(
                        _selectedMonth,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _summaryBox('Total Staff', '$_totalStaff', Colors.blue, Icons.people),
                          _summaryBox('Paid', '$_paidCount', Colors.green, Icons.check_circle),
                          _summaryBox('Unpaid', '$_unpaidCount', Colors.red, Icons.cancel),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('Total Paid', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text(
                                _currencyFormat.format(_totalPaidAmount),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('Outstanding', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text(
                                _currencyFormat.format(_totalUnpaidAmount),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _totalPostedAmount > 0 ? Colors.green.shade200 : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _totalPostedAmount > 0 ? Icons.check_circle : Icons.receipt_long,
                              size: 14,
                              color: _totalPostedAmount > 0 ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _totalPostedAmount > 0
                                  ? 'Posted ${_currencyFormat.format(_totalPostedAmount)} to Expenses'
                                  : 'Not yet posted to Expenses',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _totalPostedAmount > 0 ? Colors.green.shade700 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Export button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isExporting ? null : _exportToPDF,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf),
                      label: Text(_isExporting ? 'Exporting...' : 'Export as PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),

                // Payment records list
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        TabBar(
                          labelColor: Colors.teal,
                          unselectedLabelColor: Colors.grey,
                          tabs: [
                            Tab(text: 'Paid (${paidRecords.length})'),
                            Tab(text: 'Unpaid (${unpaidRecords.length})'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildRecordsList(paidRecords, true),
                              _buildRecordsList(unpaidRecords, false),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summaryBox(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildRecordsList(List<Map<String, dynamic>> records, bool isPaidTab) {
    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPaidTab ? Icons.check_circle_outline : Icons.hourglass_empty,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              isPaidTab ? 'No paid staff for this month' : 'All staff have been paid!',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: records.length,
      itemBuilder: (ctx, i) {
        final record = records[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
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
                            record['staffName'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'ID: ${record['staffId']}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isPaidTab ? Colors.green.shade100 : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isPaidTab ? 'PAID' : 'UNPAID',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isPaidTab ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _miniStat('Basic', record['basicSalary'], Colors.grey),
                    _miniStat('+Incentive', record['incentives'], Colors.green),
                    _miniStat(
                      (record['loanArrears'] as double? ?? 0) > 0 ? '-Loan*' : '-Loan',
                      (record['loanDeduction'] as num).toDouble() + (record['loanArrears'] as double? ?? 0),
                      Colors.orange,
                    ),
                    _miniStat('-Penalty', record['penalties'], Colors.red),
                  ],
                ),
                if (_basisSummary(record['payrollBasis'] as Map<String, dynamic>?) != 'Full Payment (100%)') ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.tune, size: 12, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Basis: ${_basisSummary(record['payrollBasis'] as Map<String, dynamic>?)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                if ((record['arrears'] as double) > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Net Salary:', style: TextStyle(color: Colors.grey[600])),
                      Text(
                        _currencyFormat.format(record['netSalary']),
                        style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('+Arrears:', style: TextStyle(color: Colors.orange[700], fontSize: 13)),
                      Text(
                        _currencyFormat.format(record['arrears']),
                        style: TextStyle(color: Colors.orange[700], fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      (record['arrears'] as double) > 0 ? 'Total Payable:' : 'Net Salary:',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    Text(
                      _currencyFormat.format(record['totalPayable']),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                if (isPaidTab && record['paymentDate'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Paid on: ${_formatDate(record['paymentDate'])}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
                if (record['bankName'] != null && record['bankName'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.account_balance, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${record['bankName']} - ${record['accountNumber']}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
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

  Widget _miniStat(String label, dynamic value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: color)),
        Text(
          _currencyFormat.format(value),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
        ),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy, HH:mm').format(date);
    } catch (_) {
      return dateStr;
    }
  }
}
