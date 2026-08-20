// lib/screens/staff/staff_payroll/staff_loan_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/database_helper_wrapper.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import '../../../models/staff_loan.dart';
import '../../../utils/staff_loan_pdf_generator.dart';
import '../../../utils/write_guard.dart';

class StaffLoanScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const StaffLoanScreen({super.key, required this.currentUser});

  @override
  State<StaffLoanScreen> createState() => _StaffLoanScreenState();
}

class _StaffLoanScreenState extends State<StaffLoanScreen> with SingleTickerProviderStateMixin {
  final _dbHelper = DatabaseHelper();
  // Loans, salary payments, and their linked Expense records are wired
  // through the repository layer (client/server sync + audit logging);
  // everything else here (staff bio data, term/session, school profile)
  // talks to DatabaseHelper directly.
  final _repoDb = DatabaseHelperWrapper();
  final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);
  final _currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());

  late final TabController _tabController;

  List<Map<String, dynamic>> _loans = [];
  List<Staff> _staffList = [];
  Map<int, bool> _salaryPaidStatus = {}; // staffId -> isPaid for the current month
  // staffId -> loanDeductionsApplied JSON for the current month's payment
  // (which loan ids had a deduction applied when marked paid this month)
  Map<int, String?> _loanDeductionsAppliedByStaffId = {};
  bool _isLoading = true;
  bool _isExporting = false;
  String _filterStatus = 'All'; // 'All', 'Active', 'Completed'
  String? _selectedMonth; // null means 'All months'

  @override
  void initState() {
    super.initState();
    WriteGuard.enforce(context);
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final staffMaps = await _dbHelper.getStaff();
      final loans = await _repoDb.getAllStaffLoans();
      final salaryPayments = await _repoDb.getSalaryPaymentsByMonth(_currentMonth);

      setState(() {
        _staffList = staffMaps.map((m) => Staff.fromMap(m)).toList();
        _loans = loans;
        _salaryPaidStatus = {
          for (var p in salaryPayments) p['staffId'] as int: (p['isPaid'] as int) == 1,
        };
        _loanDeductionsAppliedByStaffId = {
          for (var p in salaryPayments)
            p['staffId'] as int: p['loanDeductionsApplied'] as String?,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredLoans {
    var filtered = _loans.toList();

    // Filter by status
    if (_filterStatus != 'All') {
      filtered = filtered.where((l) => l['status'] == _filterStatus).toList();
    }

    // Filter by month (using collection date)
    if (_selectedMonth != null) {
      filtered = filtered.where((l) {
        if (l['collectionDate'] == null || l['collectionDate'].toString().isEmpty) {
          return false;
        }
        try {
          final collectionDate = DateTime.parse(l['collectionDate']);
          final loanMonth = DateFormat('MMMM yyyy').format(collectionDate);
          return loanMonth == _selectedMonth;
        } catch (_) {
          return false;
        }
      }).toList();
    }

    return filtered;
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
    }
  }

  void _clearMonthFilter() {
    setState(() {
      _selectedMonth = null;
    });
  }

  static const List<String> _paymentMethods = ['Cash', 'Transfer', 'POS'];

  void _showAddLoanDialog() {
    Staff? selectedStaff;
    final amountController = TextEditingController();
    final deductionController = TextEditingController();
    final reasonController = TextEditingController();
    int repaymentMonths = 1;
    DateTime? collectionDate = DateTime.now();
    String paymentMethod = 'Cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Calculate monthly deduction
          final amount = double.tryParse(amountController.text) ?? 0;
          if (repaymentMonths > 0 && amount > 0) {
            deductionController.text = (amount / repaymentMonths).toStringAsFixed(2);
          }

          return AlertDialog(
            title: const Text('Add Staff Loan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Staff>(
                    decoration: const InputDecoration(
                      labelText: 'Select Staff',
                      border: OutlineInputBorder(),
                    ),
                    items: _staffList
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s.fullName),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedStaff = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Loan Amount',
                      border: OutlineInputBorder(),
                      prefixText: 'N ',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  // Collection Date Picker
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: collectionDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => collectionDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Collection Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        collectionDate != null
                            ? DateFormat('dd MMM yyyy').format(collectionDate!)
                            : 'Select date',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Repayment Period: '),
                      IconButton(
                        onPressed: repaymentMonths > 1
                            ? () => setDialogState(() => repaymentMonths--)
                            : null,
                        icon: const Icon(Icons.remove_circle),
                      ),
                      Text(
                        '$repaymentMonths month${repaymentMonths > 1 ? 's' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => setDialogState(() => repaymentMonths++),
                        icon: const Icon(Icons.add_circle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: deductionController,
                    decoration: const InputDecoration(
                      labelText: 'Monthly Deduction',
                      border: OutlineInputBorder(),
                      prefixText: 'N ',
                    ),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Payment Method',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payment),
                    ),
                    initialValue: paymentMethod,
                    items: _paymentMethods
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => paymentMethod = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Loan',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., Medical expenses, Education, etc.',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedStaff == null ||
                      amountController.text.isEmpty ||
                      reasonController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill all fields')),
                    );
                    return;
                  }

                  final loan = StaffLoan(
                    staffId: selectedStaff!.id!,
                    staffName: selectedStaff!.fullName,
                    month: DateFormat('MMMM yyyy').format(DateTime.now()),
                    amount: double.tryParse(amountController.text) ?? 0,
                    deductionPerMonth: double.tryParse(deductionController.text) ?? 0,
                    monthsRemaining: repaymentMonths,
                    reason: reasonController.text,
                    status: 'Active',
                    collectionDate: collectionDate != null
                        ? DateFormat('yyyy-MM-dd').format(collectionDate!)
                        : null,
                    paymentMethod: paymentMethod,
                  );

                  final confirmed = await _showConfirmAddLoanDialog(loan);
                  if (confirmed != true) return;

                  final expenseId = await _postLoanToExpenses(loan);
                  loan.linkedExpenseId = expenseId;
                  await _repoDb.insertStaffLoan(loan.toMap());
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Loan added and posted to Expenses'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  _loadData(); // Refresh the list
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Lets the user review the loan (and what will be posted to Expenses)
  /// before it's actually saved.
  Future<bool?> _showConfirmAddLoanDialog(StaffLoan loan) {
    final dateDisplay = loan.collectionDate != null
        ? DateFormat('dd MMM yyyy').format(DateTime.parse(loan.collectionDate!))
        : 'Not set';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Loan Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Staff', loan.staffName),
              _detailRow('Loan Amount', _currencyFormat.format(loan.amount)),
              _detailRow('Collection Date', dateDisplay),
              _detailRow(
                'Repayment Period',
                '${loan.monthsRemaining} month${loan.monthsRemaining > 1 ? 's' : ''}',
              ),
              _detailRow('Monthly Deduction', _currencyFormat.format(loan.deductionPerMonth)),
              _detailRow('Reason', loan.reason),
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.receipt_long, size: 16, color: Colors.brown.shade700),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Will be posted to Expenses as:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _detailRow('Category', 'Staff Loan'),
              _detailRow('Recipient/Vendor', loan.staffName),
              _detailRow('Amount', _currencyFormat.format(loan.amount)),
              _detailRow('Payment Method', loan.paymentMethod ?? 'Cash'),
              _detailRow('Expense Date', dateDisplay),
              _detailRow('Description', loan.reason),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Confirm & Post'),
          ),
        ],
      ),
    );
  }

  /// Automatically posts a newly issued loan to Expenses, since the amount
  /// will be recovered from the staff's salary anyway. Returns the id of the
  /// inserted expense so the loan record can keep a link to it.
  Future<int> _postLoanToExpenses(StaffLoan loan) async {
    final activeTerm = await _dbHelper.getActiveTerm();
    final sessionData = await _dbHelper.getActiveSession();
    final activeSession = sessionData?['sessionName'];

    final expenseDate = loan.collectionDate != null
        ? (DateTime.tryParse(loan.collectionDate!) ?? DateTime.now())
        : DateTime.now();

    return _repoDb.insertExpense({
      'amount': loan.amount,
      'category': 'Staff Loan',
      'customCategory': null,
      'description': loan.reason,
      'expenseDate': expenseDate.toIso8601String(),
      'paymentMethod': loan.paymentMethod ?? 'Cash',
      'recipient': loan.staffName,
      'term': activeTerm,
      'session': activeSession,
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': widget.currentUser['username'],
    });
  }

  void _showLoanDetailsDialog(Map<String, dynamic> loan) {
    final loanModel = StaffLoan.fromMap(loan);

    // Format collection date for display
    String collectionDateDisplay = 'Not set';
    if (loan['collectionDate'] != null && loan['collectionDate'].toString().isNotEmpty) {
      try {
        final date = DateTime.parse(loan['collectionDate']);
        collectionDateDisplay = DateFormat('dd MMM yyyy').format(date);
      } catch (_) {
        collectionDateDisplay = loan['collectionDate'].toString();
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loan['staffName'] ?? 'Loan Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Loan Amount', _currencyFormat.format(loan['amount'])),
              _detailRow('Collection Date', collectionDateDisplay),
              _detailRow('Payment Method', loan['paymentMethod'] ?? 'Cash'),
              _detailRow('Monthly Deduction', _currencyFormat.format(loan['deductionPerMonth'])),
              _detailRow('Months Remaining', '${loan['monthsRemaining']}'),
              _detailRow('Total Paid', _currencyFormat.format(loanModel.totalPaid)),
              _detailRow('Balance', _currencyFormat.format(loanModel.balance)),
              _detailRow('Status', loan['status']),
              _detailRow('Reason', loan['reason'] ?? ''),
              _detailRow('Started', loan['month'] ?? ''),
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _deleteLoan(Map<String, dynamic> loan) async {
    final loanModel = StaffLoan.fromMap(loan);
    final hasBeenPaid = loanModel.status == 'Completed' || loanModel.totalPaid > 0.01;

    if (hasBeenPaid) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Delete Loan'),
          content: Text(
            loanModel.status == 'Completed'
                ? 'This loan has already been fully paid off and cannot be deleted, '
                    'to preserve the payment history.'
                : 'This loan has already had ${_currencyFormat.format(loanModel.totalPaid)} '
                    'deducted from salary and cannot be deleted, to preserve the payment '
                    'history. You can mark it Completed instead if it should stop deducting.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Loan'),
        content: const Text(
          'Are you sure you want to delete this loan record?\n\n'
          'This will also remove the matching entry from Expenses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repoDb.deleteStaffLoan(loan['id']);
      final linkedExpenseId = loan['linkedExpenseId'] as int?;
      if (linkedExpenseId != null) {
        await _repoDb.deleteExpense(linkedExpenseId);
      }
      _loadData();
    }
  }

  void _showEditLoanDialog(Map<String, dynamic> loan) {
    final loanModel = StaffLoan.fromMap(loan);
    final hasBeenPaid = loanModel.status == 'Completed' || loanModel.totalPaid > 0.01;

    if (hasBeenPaid) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Edit Loan'),
          content: Text(
            loanModel.status == 'Completed'
                ? 'This loan has already been fully paid off and cannot be edited, '
                    'to preserve the payment history.'
                : 'This loan has already had ${_currencyFormat.format(loanModel.totalPaid)} '
                    'deducted from salary and cannot be edited, to preserve the payment '
                    'history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final amountController = TextEditingController(text: loan['amount'].toString());
    final deductionController = TextEditingController(text: loan['deductionPerMonth'].toString());
    final reasonController = TextEditingController(text: loan['reason'] ?? '');
    int monthsRemaining = loan['monthsRemaining'] ?? 1;
    String status = loan['status'] ?? 'Active';
    String paymentMethod = loan['paymentMethod'] ?? 'Cash';
    DateTime? collectionDate;

    // Parse existing collection date if available
    if (loan['collectionDate'] != null && loan['collectionDate'].toString().isNotEmpty) {
      try {
        collectionDate = DateTime.parse(loan['collectionDate']);
      } catch (_) {}
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Staff Loan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Staff name (read-only)
                  TextFormField(
                    initialValue: loan['staffName'] ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Staff Name',
                      border: OutlineInputBorder(),
                    ),
                    readOnly: true,
                    enabled: false,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Loan Amount',
                      border: OutlineInputBorder(),
                      prefixText: 'N ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  // Collection Date Picker
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: collectionDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => collectionDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Collection Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        collectionDate != null
                            ? DateFormat('dd MMM yyyy').format(collectionDate!)
                            : 'Select date',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Months Remaining: '),
                      IconButton(
                        onPressed: monthsRemaining > 0
                            ? () => setDialogState(() => monthsRemaining--)
                            : null,
                        icon: const Icon(Icons.remove_circle),
                      ),
                      Text(
                        '$monthsRemaining',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => setDialogState(() => monthsRemaining++),
                        icon: const Icon(Icons.add_circle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: deductionController,
                    decoration: const InputDecoration(
                      labelText: 'Monthly Deduction',
                      border: OutlineInputBorder(),
                      prefixText: 'N ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: status,
                    items: const [
                      DropdownMenuItem(value: 'Active', child: Text('Active')),
                      DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Payment Method',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payment),
                    ),
                    initialValue: paymentMethod,
                    items: _paymentMethods
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => paymentMethod = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Loan',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (amountController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter loan amount')),
                    );
                    return;
                  }

                  final updatedAmount = double.tryParse(amountController.text) ?? 0;
                  final updatedCollectionDate = collectionDate != null
                      ? DateFormat('yyyy-MM-dd').format(collectionDate!)
                      : loan['collectionDate'];

                  await _repoDb.updateStaffLoan(loan['id'], {
                    'amount': updatedAmount,
                    'deductionPerMonth': double.tryParse(deductionController.text) ?? 0,
                    'monthsRemaining': monthsRemaining,
                    'status': status,
                    'reason': reasonController.text,
                    'collectionDate': updatedCollectionDate,
                    'paymentMethod': paymentMethod,
                  });

                  final linkedExpenseId = loan['linkedExpenseId'] as int?;
                  if (linkedExpenseId != null) {
                    final expenseDate = updatedCollectionDate != null
                        ? (DateTime.tryParse(updatedCollectionDate.toString()) ?? DateTime.now())
                        : DateTime.now();
                    await _repoDb.updateExpense(linkedExpenseId, {
                      'amount': updatedAmount,
                      'description': reasonController.text,
                      'expenseDate': expenseDate.toIso8601String(),
                      'paymentMethod': paymentMethod,
                    });
                  }

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Loan updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  _loadData(); // Refresh the list
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
    if (_filteredLoans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No loans to export')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final schoolProfile = await _dbHelper.getSchoolProfile();
      final totalLoans = _filteredLoans.fold<double>(
        0,
        (sum, l) => sum + (l['amount'] as num).toDouble(),
      );
      final totalBalance = _filteredLoans.fold<double>(
        0,
        (sum, l) {
          final loan = StaffLoan.fromMap(l);
          return sum + loan.balance;
        },
      );

      final filePath = await StaffLoanPDFGenerator.generateLoanPDF(
        loans: _filteredLoans,
        schoolProfile: schoolProfile ?? {},
        filterStatus: _filterStatus,
        totalLoans: totalLoans,
        totalBalance: totalBalance,
      );

      if (mounted) {
        setState(() => _isExporting = false);
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Staff Loans - $_filterStatus',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Loans'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _selectMonth,
            tooltip: 'Filter by Month',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _filterStatus = v),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'All', child: Text('All Loans')),
              const PopupMenuItem(value: 'Active', child: Text('Active Loans')),
              const PopupMenuItem(value: 'Completed', child: Text('Completed')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.orange.shade100,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'All Loans'),
            Tab(text: 'This Month'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddLoanDialog,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add),
        label: const Text('Add Loan'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAllLoansTab(),
                _buildThisMonthTab(),
              ],
            ),
    );
  }

  Widget _buildAllLoansTab() {
    final totalLoans = _filteredLoans.fold<double>(
      0,
      (sum, l) => sum + (l['amount'] as num).toDouble(),
    );
    final totalBalance = _filteredLoans.fold<double>(
      0,
      (sum, l) {
        final loan = StaffLoan.fromMap(l);
        return sum + loan.balance;
      },
    );

    return Column(
              children: [
                // Summary card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.shade50,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text(
                                'Total Loans',
                                style: TextStyle(color: Colors.grey),
                              ),
                              Text(
                                _currencyFormat.format(totalLoans),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Text(
                                'Outstanding',
                                style: TextStyle(color: Colors.grey),
                              ),
                              Text(
                                _currencyFormat.format(totalBalance),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Text(
                                'Status',
                                style: TextStyle(color: Colors.grey),
                              ),
                              Text(
                                _filterStatus,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Month filter indicator
                      if (_selectedMonth != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_month, size: 16, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text(
                                _selectedMonth!,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: _clearMonthFilter,
                                child: const Icon(Icons.close, size: 18, color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Export PDF button
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

                // Loans list
                Expanded(
                  child: _filteredLoans.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No loans found',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredLoans.length,
                          itemBuilder: (ctx, i) => _buildLoanCard(_filteredLoans[i]),
                        ),
                ),
              ],
            );
  }

  Widget _buildThisMonthTab() {
    // Loans still being deducted, PLUS loans that were fully paid off this
    // exact month (status flipped to 'Completed') — otherwise a loan that
    // completes this month vanishes from "This Month" instead of showing
    // under Paid.
    final relevantLoans = _loans.where((l) {
      if (l['status'] == 'Active') return true;
      final appliedJson = _loanDeductionsAppliedByStaffId[l['staffId']];
      if (appliedJson == null || appliedJson.isEmpty) return false;
      try {
        final Map<String, dynamic> applied = jsonDecode(appliedJson);
        return applied.containsKey(l['id'].toString());
      } catch (_) {
        return false;
      }
    }).toList();
    final paidLoans = relevantLoans
        .where((l) => _salaryPaidStatus[l['staffId']] == true)
        .toList();
    final unpaidLoans = relevantLoans
        .where((l) => _salaryPaidStatus[l['staffId']] != true)
        .toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                Icon(Icons.calendar_month, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Loan deductions for $_currentMonth',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ],
            ),
          ),
          TabBar(
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Paid (${paidLoans.length})'),
              Tab(text: 'Unpaid (${unpaidLoans.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildMonthLoanList(paidLoans, 'No paid loans for $_currentMonth'),
                _buildMonthLoanList(unpaidLoans, 'No unpaid loans for $_currentMonth'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthLoanList(List<Map<String, dynamic>> loans, String emptyMessage) {
    if (loans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: loans.length,
      itemBuilder: (ctx, i) => _buildLoanCard(loans[i]),
    );
  }

  Widget _buildLoanCard(Map<String, dynamic> loan) {
    final loanModel = StaffLoan.fromMap(loan);
    final isActive = loan['status'] == 'Active';
    final hasBeenPaid = loanModel.status == 'Completed' || loanModel.totalPaid > 0.01;

    String collectionDateDisplay = '';
    if (loan['collectionDate'] != null && loan['collectionDate'].toString().isNotEmpty) {
      try {
        final date = DateTime.parse(loan['collectionDate']);
        collectionDateDisplay = DateFormat('dd MMM yyyy').format(date);
      } catch (_) {
        collectionDateDisplay = loan['collectionDate'].toString();
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showLoanDetailsDialog(loan),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    loan['staffName'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.orange : Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      loan['status'] ?? 'Active',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                loan['reason'] ?? '',
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (collectionDateDisplay.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      'Collected: $collectionDateDisplay',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Loan Amount',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        _currencyFormat.format(loan['amount']),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Balance',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        _currencyFormat.format(loanModel.balance),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Months Left',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        '${loan['monthsRemaining']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(
                      hasBeenPaid ? Icons.lock_outline : Icons.edit,
                      color: hasBeenPaid ? Colors.grey : Colors.blue,
                    ),
                    onPressed: () => _showEditLoanDialog(loan),
                    tooltip: hasBeenPaid
                        ? 'Cannot edit — loan has been paid/partly paid'
                        : 'Edit Loan',
                  ),
                  IconButton(
                    icon: Icon(
                      hasBeenPaid ? Icons.lock_outline : Icons.delete,
                      color: hasBeenPaid ? Colors.grey : Colors.red,
                    ),
                    onPressed: () => _deleteLoan(loan),
                    tooltip: hasBeenPaid
                        ? 'Cannot delete — loan has been paid/partly paid'
                        : 'Delete Loan',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
