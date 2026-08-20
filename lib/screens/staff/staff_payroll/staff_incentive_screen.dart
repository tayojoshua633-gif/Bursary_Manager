// lib/screens/staff/staff_payroll/staff_incentive_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/database_helper_wrapper.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';
import '../../../models/staff_incentive.dart';
import '../../../utils/staff_incentive_pdf_generator.dart';
import '../../../utils/write_guard.dart';

class StaffIncentiveScreen extends StatefulWidget {
  const StaffIncentiveScreen({super.key});

  @override
  State<StaffIncentiveScreen> createState() => _StaffIncentiveScreenState();
}

class _StaffIncentiveScreenState extends State<StaffIncentiveScreen> with SingleTickerProviderStateMixin {
  final _dbHelper = DatabaseHelper();
  // Incentives and salary payments are wired through the repository layer
  // (client/server sync + audit logging); staff bio data and school
  // profile stay on DatabaseHelper directly.
  final _repoDb = DatabaseHelperWrapper();
  final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);
  final _currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());

  late final TabController _tabController;

  List<Map<String, dynamic>> _incentives = [];
  List<Map<String, dynamic>> _thisMonthIncentives = [];
  Map<int, bool> _salaryPaidStatus = {}; // staffId -> isPaid for the current month
  List<Staff> _staffList = [];
  String _selectedMonth = '';
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    WriteGuard.enforce(context);
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
      final incentives = await _repoDb.getStaffIncentivesByMonth(_selectedMonth);
      final thisMonthIncentives = _selectedMonth == _currentMonth
          ? incentives
          : await _repoDb.getStaffIncentivesByMonth(_currentMonth);
      final salaryPayments = await _repoDb.getSalaryPaymentsByMonth(_currentMonth);

      setState(() {
        _staffList = staffMaps.map((m) => Staff.fromMap(m)).toList();
        _incentives = incentives;
        _thisMonthIncentives = thisMonthIncentives;
        _salaryPaidStatus = {
          for (var p in salaryPayments) p['staffId'] as int: (p['isPaid'] as int) == 1,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showAddIncentiveDialog() {
    Staff? selectedStaff;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Staff Incentive'),
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
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Performance bonus, Holiday allowance',
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
                    descriptionController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }

                final incentive = StaffIncentive(
                  staffId: selectedStaff!.id!,
                  staffName: selectedStaff!.fullName,
                  month: _selectedMonth,
                  amount: double.tryParse(amountController.text) ?? 0,
                  description: descriptionController.text,
                );

                await _repoDb.insertStaffIncentive(incentive.toMap());
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Incentive added successfully'),
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

  void _showEditIncentiveDialog(Map<String, dynamic> incentive) {
    final amountController = TextEditingController(text: incentive['amount'].toString());
    final descriptionController = TextEditingController(text: incentive['description'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Incentive'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: incentive['staffName'] ?? '',
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
                  labelText: 'Description',
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

              await _repoDb.updateStaffIncentive(incentive['id'], {
                'amount': double.tryParse(amountController.text) ?? 0,
                'description': descriptionController.text,
              });

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Incentive updated successfully'),
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

  Future<void> _deleteIncentive(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Incentive'),
        content: const Text('Are you sure you want to delete this incentive?'),
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
      await _repoDb.deleteStaffIncentive(id);
      _loadData();
    }
  }

  Future<void> _exportToPDF() async {
    if (_incentives.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No incentives to export')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final schoolProfile = await _dbHelper.getSchoolProfile();
      final totalIncentives = _incentives.fold<double>(
        0,
        (sum, i) => sum + (i['amount'] as num).toDouble(),
      );

      final filePath = await StaffIncentivePDFGenerator.generateIncentivePDF(
        incentives: _incentives,
        month: _selectedMonth,
        schoolProfile: schoolProfile ?? {},
        totalAmount: totalIncentives,
      );

      if (mounted) {
        setState(() => _isExporting = false);
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Staff Incentives - $_selectedMonth',
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
        title: const Text('Staff Incentive/Grant'),
        backgroundColor: Colors.green,
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
          unselectedLabelColor: Colors.green.shade100,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Incentives'),
            Tab(text: 'This Month'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddIncentiveDialog,
        backgroundColor: Colors.green,
        icon: const Icon(Icons.add),
        label: const Text('Add Incentive'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildIncentivesTab(),
                _buildThisMonthTab(),
              ],
            ),
    );
  }

  Widget _buildIncentivesTab() {
    final totalIncentives = _incentives.fold<double>(
      0,
      (sum, i) => sum + (i['amount'] as num).toDouble(),
    );

    return Column(
              children: [
                // Month selector card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.green.shade50,
                  child: Row(
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
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Total Incentives',
                            style: TextStyle(color: Colors.grey),
                          ),
                          Text(
                            _currencyFormat.format(totalIncentives),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
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

                // Incentives list
                Expanded(
                  child: _incentives.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.card_giftcard, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No incentives for $_selectedMonth',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _incentives.length,
                          itemBuilder: (ctx, i) => _buildIncentiveTile(_incentives[i]),
                        ),
                ),
              ],
            );
  }

  Widget _buildThisMonthTab() {
    final paid = _thisMonthIncentives
        .where((i) => _salaryPaidStatus[i['staffId']] == true)
        .toList();
    final unpaid = _thisMonthIncentives
        .where((i) => _salaryPaidStatus[i['staffId']] != true)
        .toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.green.shade50,
            child: Row(
              children: [
                Icon(Icons.calendar_month, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  'Incentives for $_currentMonth',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                ),
              ],
            ),
          ),
          TabBar(
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Paid (${paid.length})'),
              Tab(text: 'Unpaid (${unpaid.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildIncentiveList(paid, 'No paid incentives for $_currentMonth'),
                _buildIncentiveList(unpaid, 'No unpaid incentives for $_currentMonth'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncentiveList(List<Map<String, dynamic>> incentives, String emptyMessage) {
    if (incentives.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.card_giftcard, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: incentives.length,
      itemBuilder: (ctx, i) => _buildIncentiveTile(incentives[i]),
    );
  }

  Widget _buildIncentiveTile(Map<String, dynamic> inc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: const Icon(Icons.card_giftcard, color: Colors.green),
        ),
        title: Text(
          inc['staffName'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(inc['description'] ?? ''),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currencyFormat.format(inc['amount']),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
                fontSize: 16,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showEditIncentiveDialog(inc),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteIncentive(inc['id']),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}
