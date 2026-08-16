// lib/screens/staff/staff_payroll/staff_deduction_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/database_helper_wrapper.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import '../../../models/staff_deduction.dart';
import '../../../utils/staff_deduction_pdf_generator.dart';

class StaffDeductionScreen extends StatefulWidget {
  const StaffDeductionScreen({super.key});

  @override
  State<StaffDeductionScreen> createState() => _StaffDeductionScreenState();
}

class _StaffDeductionScreenState extends State<StaffDeductionScreen> with SingleTickerProviderStateMixin {
  final _dbHelper = DatabaseHelper();
  // Deductions and salary payments are wired through the repository layer
  // (client/server sync + audit logging); staff bio data and school
  // profile stay on DatabaseHelper directly.
  final _repoDb = DatabaseHelperWrapper();
  final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);
  final _currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());

  late final TabController _tabController;

  List<Map<String, dynamic>> _deductions = [];
  List<Map<String, dynamic>> _thisMonthDeductions = [];
  Map<int, bool> _salaryPaidStatus = {}; // staffId -> isPaid for the current month
  List<Staff> _staffList = [];
  String _selectedMonth = '';
  bool _isLoading = true;
  bool _isExporting = false;

  final List<String> _deductionReasons = [
    'Late Coming',
    'Absenteeism',
    'Damage to Property',
    'Misconduct',
    'Unauthorized Leave',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedMonth = _currentMonth;
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
      final deductions = await _repoDb.getStaffDeductionsByMonth(_selectedMonth);
      final thisMonthDeductions = _selectedMonth == _currentMonth
          ? deductions
          : await _repoDb.getStaffDeductionsByMonth(_currentMonth);
      final salaryPayments = await _repoDb.getSalaryPaymentsByMonth(_currentMonth);

      setState(() {
        _staffList = staffMaps.map((m) => Staff.fromMap(m)).toList();
        _deductions = deductions;
        _thisMonthDeductions = thisMonthDeductions;
        _salaryPaidStatus = {
          for (var p in salaryPayments) p['staffId'] as int: (p['isPaid'] as int) == 1,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showAddDeductionDialog() {
    Staff? selectedStaff;
    String selectedReason = _deductionReasons[0];
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Penalty/Deduction'),
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
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: selectedReason,
                  items: _deductionReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedReason = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                    prefixText: 'N ',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(DateTime.now().year - 1),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Additional details about the deduction',
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
                if (selectedStaff == null || amountController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select staff and enter amount')),
                  );
                  return;
                }

                final deduction = StaffDeduction(
                  staffId: selectedStaff!.id!,
                  staffName: selectedStaff!.fullName,
                  month: _selectedMonth,
                  amount: double.tryParse(amountController.text) ?? 0,
                  reason: selectedReason,
                  description: descriptionController.text.isNotEmpty
                      ? descriptionController.text
                      : null,
                  date: DateFormat('yyyy-MM-dd').format(selectedDate),
                );

                await _repoDb.insertStaffDeduction(deduction.toMap());
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Deduction added successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                _loadData();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
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
      _loadData();
    }
  }

  Future<void> _deleteDeduction(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Deduction'),
        content: const Text('Are you sure you want to delete this deduction record?'),
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
      await _repoDb.deleteStaffDeduction(id);
      _loadData();
    }
  }

  void _showEditDeductionDialog(Map<String, dynamic> deduction) {
    String selectedReason = deduction['reason'] ?? _deductionReasons[0];
    final amountController = TextEditingController(text: deduction['amount'].toString());
    final descriptionController = TextEditingController(text: deduction['description'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Deduction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: deduction['staffName'] ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Staff Name',
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                  enabled: false,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: selectedReason,
                  items: _deductionReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedReason = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                    prefixText: 'N ',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
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
                    const SnackBar(content: Text('Please enter amount')),
                  );
                  return;
                }

                await _repoDb.updateStaffDeduction(deduction['id'], {
                  'amount': double.tryParse(amountController.text) ?? 0,
                  'reason': selectedReason,
                  'description': descriptionController.text.isNotEmpty
                      ? descriptionController.text
                      : null,
                });

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Deduction updated successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                _loadData();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportToPDF() async {
    if (_deductions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No deductions to export')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final schoolProfile = await _dbHelper.getSchoolProfile();
      final totalDeductions = _deductions.fold<double>(
        0,
        (sum, d) => sum + (d['amount'] as num).toDouble(),
      );

      final Map<String, double> reasonTotals = {};
      for (var d in _deductions) {
        final reason = d['reason'] as String;
        reasonTotals[reason] = (reasonTotals[reason] ?? 0) + (d['amount'] as num).toDouble();
      }

      final filePath = await StaffDeductionPDFGenerator.generateDeductionPDF(
        deductions: _deductions,
        month: _selectedMonth,
        schoolProfile: schoolProfile ?? {},
        totalAmount: totalDeductions,
        reasonTotals: reasonTotals,
      );

      if (mounted) {
        setState(() => _isExporting = false);
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Staff Deductions - $_selectedMonth',
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

  IconData _getReasonIcon(String reason) {
    switch (reason) {
      case 'Late Coming':
        return Icons.access_time;
      case 'Absenteeism':
        return Icons.event_busy;
      case 'Damage to Property':
        return Icons.broken_image;
      case 'Misconduct':
        return Icons.warning;
      case 'Unauthorized Leave':
        return Icons.exit_to_app;
      default:
        return Icons.remove_circle;
    }
  }

  Color _getReasonColor(String reason) {
    switch (reason) {
      case 'Late Coming':
        return Colors.orange;
      case 'Absenteeism':
        return Colors.red;
      case 'Damage to Property':
        return Colors.brown;
      case 'Misconduct':
        return Colors.purple;
      case 'Unauthorized Leave':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Penalty/Deduction'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _selectMonth,
            tooltip: 'Select Month',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.red.shade100,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Deductions'),
            Tab(text: 'This Month'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDeductionDialog,
        backgroundColor: Colors.red,
        icon: const Icon(Icons.add),
        label: const Text('Add Deduction'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDeductionsTab(),
                _buildThisMonthTab(),
              ],
            ),
    );
  }

  Widget _buildDeductionsTab() {
    final totalDeductions = _deductions.fold<double>(
      0,
      (sum, d) => sum + (d['amount'] as num).toDouble(),
    );

    // Group deductions by reason for summary
    final Map<String, double> reasonTotals = {};
    for (var d in _deductions) {
      final reason = d['reason'] as String;
      reasonTotals[reason] = (reasonTotals[reason] ?? 0) + (d['amount'] as num).toDouble();
    }

    return Column(
              children: [
                // Month and summary header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.red.shade50,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Selected Month',
                                style: TextStyle(color: Colors.grey),
                              ),
                              Text(
                                _selectedMonth,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Total Deductions',
                                style: TextStyle(color: Colors.grey),
                              ),
                              Text(
                                _currencyFormat.format(totalDeductions),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (reasonTotals.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: reasonTotals.entries.map((e) {
                            return Chip(
                              avatar: Icon(
                                _getReasonIcon(e.key),
                                size: 16,
                                color: _getReasonColor(e.key),
                              ),
                              label: Text(
                                '${e.key}: ${_currencyFormat.format(e.value)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : _exportToPDF,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf),
                          label: Text(_isExporting ? 'Generating PDF...' : 'Export as PDF'),
                        ),
                      ),
                    ],
                  ),
                ),

                // Deductions list
                Expanded(
                  child: _deductions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, size: 64, color: Colors.green[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No deductions for $_selectedMonth',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Great! All staff are performing well.',
                                style: TextStyle(color: Colors.green[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _deductions.length,
                          itemBuilder: (ctx, i) => _buildDeductionTile(_deductions[i]),
                        ),
                ),
              ],
            );
  }

  Widget _buildThisMonthTab() {
    final paid = _thisMonthDeductions
        .where((d) => _salaryPaidStatus[d['staffId']] == true)
        .toList();
    final unpaid = _thisMonthDeductions
        .where((d) => _salaryPaidStatus[d['staffId']] != true)
        .toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.red.shade50,
            child: Row(
              children: [
                Icon(Icons.calendar_month, size: 16, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Text(
                  'Deductions for $_currentMonth',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                ),
              ],
            ),
          ),
          TabBar(
            labelColor: Colors.red,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Paid (${paid.length})'),
              Tab(text: 'Unpaid (${unpaid.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildDeductionList(paid, 'No paid deductions for $_currentMonth'),
                _buildDeductionList(unpaid, 'No unpaid deductions for $_currentMonth'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeductionList(List<Map<String, dynamic>> deductions, String emptyMessage) {
    if (deductions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green[300]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: deductions.length,
      itemBuilder: (ctx, i) => _buildDeductionTile(deductions[i]),
    );
  }

  Widget _buildDeductionTile(Map<String, dynamic> ded) {
    final reason = ded['reason'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getReasonColor(reason).withValues(alpha: 0.2),
          child: Icon(
            _getReasonIcon(reason),
            color: _getReasonColor(reason),
          ),
        ),
        title: Text(
          ded['staffName'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reason),
            if (ded['description'] != null && ded['description'].toString().isNotEmpty)
              Text(
                ded['description'],
                style: const TextStyle(fontSize: 12),
              ),
            Text(
              ded['date'] ?? '',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currencyFormat.format(ded['amount']),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
                fontSize: 16,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showEditDeductionDialog(ded),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteDeduction(ded['id']),
              tooltip: 'Delete',
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
