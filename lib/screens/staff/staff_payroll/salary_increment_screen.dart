// lib/screens/staff/staff_payroll/salary_increment_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/database_helper_wrapper.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';

class SalaryIncrementScreen extends StatefulWidget {
  const SalaryIncrementScreen({super.key});

  @override
  State<SalaryIncrementScreen> createState() => _SalaryIncrementScreenState();
}

class _SalaryIncrementScreenState extends State<SalaryIncrementScreen> with SingleTickerProviderStateMixin {
  final _dbHelper = DatabaseHelper();
  // Salary history/increments and salary payments are wired through the
  // repository layer; staff bio data stays on DatabaseHelper directly.
  final _repoDb = DatabaseHelperWrapper();
  final _currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);
  final _currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());

  late final TabController _tabController;

  List<Staff> _allStaff = [];
  List<Map<String, dynamic>> _thisMonthIncrements = [];
  Map<int, bool> _salaryPaidStatus = {}; // staffId -> isPaid for the current month
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();
  List<Staff> _filteredStaff = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStaff();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final maps = await _dbHelper.getStaff();
      final allHistory = await _repoDb.getAllSalaryHistory();
      final salaryPayments = await _repoDb.getSalaryPaymentsByMonth(_currentMonth);

      setState(() {
        _allStaff = maps.map((m) => Staff.fromMap(m)).toList();
        _filteredStaff = List.from(_allStaff);
        _thisMonthIncrements = allHistory
            .where((h) => h['effectiveMonth'] == _currentMonth)
            .toList();
        _salaryPaidStatus = {
          for (var p in salaryPayments) p['staffId'] as int: (p['isPaid'] as int) == 1,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterStaff(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredStaff = _allStaff.where((s) {
        return s.fullName.toLowerCase().contains(q) ||
            s.staffId.toLowerCase().contains(q);
      }).toList();
    });
  }

  /// Show history + add increment dialog for a specific staff
  Future<void> _openIncrementDialog(Staff staff) async {
    final history = await _repoDb.getSalaryHistory(staff.id!);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _IncrementBottomSheet(
        staff: staff,
        history: history,
        dbHelper: _repoDb,
        currencyFormat: _currencyFormat,
        onSaved: () {
          Navigator.pop(ctx);
          _loadStaff(); // refresh salaries
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salary Increment'),
        backgroundColor: Colors.amber.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.amber.shade100,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Staff'),
            Tab(text: 'This Month'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStaffTab(),
                _buildThisMonthTab(),
              ],
            ),
    );
  }

  Widget _buildStaffTab() {
    return Column(
              children: [
                // Info banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.amber.shade50,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Salary increments are recorded with an effective month. '
                          'Previous payroll records are not affected — the correct '
                          'salary for each past month is used when viewing old payroll data.',
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                // Search
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search staff...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: _filterStaff,
                  ),
                ),
                // Staff list
                Expanded(
                  child: _filteredStaff.isEmpty
                      ? Center(
                          child: Text(
                            'No staff found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _filteredStaff.length,
                          itemBuilder: (ctx, i) => _buildStaffCard(_filteredStaff[i]),
                        ),
                ),
              ],
            );
  }

  Widget _buildThisMonthTab() {
    final paid = _thisMonthIncrements
        .where((h) => _salaryPaidStatus[h['staffId']] == true)
        .toList();
    final unpaid = _thisMonthIncrements
        .where((h) => _salaryPaidStatus[h['staffId']] != true)
        .toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                Icon(Icons.calendar_month, size: 16, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Text(
                  'Increments effective $_currentMonth',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
              ],
            ),
          ),
          TabBar(
            labelColor: Colors.amber.shade800,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Paid (${paid.length})'),
              Tab(text: 'Unpaid (${unpaid.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildIncrementList(paid, 'No paid increments for $_currentMonth'),
                _buildIncrementList(unpaid, 'No unpaid increments for $_currentMonth'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncrementList(List<Map<String, dynamic>> increments, String emptyMessage) {
    if (increments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: increments.length,
      itemBuilder: (ctx, i) => _buildIncrementTile(increments[i]),
    );
  }

  Widget _buildIncrementTile(Map<String, dynamic> record) {
    final salary = (record['salary'] as num).toDouble();
    final reason = record['reason'] as String?;
    final staffId = record['staffId'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.trending_up, color: Colors.green.shade600),
        ),
        title: Text(
          record['staffName'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${record['staffCode'] ?? ''}'),
            if (reason != null && reason.isNotEmpty)
              Text(reason, style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: Text(
          _currencyFormat.format(salary),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Colors.green,
          ),
        ),
        isThreeLine: reason != null && reason.isNotEmpty,
        onTap: () {
          final matches = _allStaff.where((s) => s.id == staffId);
          if (matches.isNotEmpty) _openIncrementDialog(matches.first);
        },
      ),
    );
  }

  Widget _buildStaffCard(Staff staff) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.amber.shade100,
          child: Text(
            staff.surname.isNotEmpty ? staff.surname[0].toUpperCase() : '?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.amber.shade800,
            ),
          ),
        ),
        title: Text(
          staff.fullName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'ID: ${staff.staffId}  •  ${staff.staffType}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _currencyFormat.format(staff.salary),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.green,
              ),
            ),
            const Text(
              'Current Salary',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        onTap: () => _openIncrementDialog(staff),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom Sheet for increment input + history view
// ---------------------------------------------------------------------------
class _IncrementBottomSheet extends StatefulWidget {
  final Staff staff;
  final List<Map<String, dynamic>> history;
  final DatabaseHelperWrapper dbHelper;
  final NumberFormat currencyFormat;
  final VoidCallback onSaved;

  const _IncrementBottomSheet({
    required this.staff,
    required this.history,
    required this.dbHelper,
    required this.currencyFormat,
    required this.onSaved,
  });

  @override
  State<_IncrementBottomSheet> createState() => _IncrementBottomSheetState();
}

class _IncrementBottomSheetState extends State<_IncrementBottomSheet> {
  final _newSalaryCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String _selectedMonth = DateFormat('MMMM yyyy').format(DateTime.now());
  bool _isSaving = false;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _history = List.from(widget.history);
    _newSalaryCtrl.text = widget.staff.salary.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _newSalaryCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = DateFormat('MMMM yyyy').format(picked);
      });
    }
  }

  Future<void> _save() async {
    final newSalary = double.tryParse(_newSalaryCtrl.text.trim()) ?? 0;
    if (newSalary <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid salary amount')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Insert salary history record
      await widget.dbHelper.insertSalaryHistory(
        widget.staff.id!,
        newSalary,
        _selectedMonth,
        reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      );

      // Update staff's current salary
      await widget.dbHelper.updateStaffSalary(widget.staff.id!, newSalary);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Salary updated to ${widget.currencyFormat.format(newSalary)} '
              'effective $_selectedMonth',
            ),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteHistory(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Record'),
        content: const Text(
          'Delete this salary history record? This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.dbHelper.deleteSalaryHistory(id);
      final updated = await widget.dbHelper.getSalaryHistory(widget.staff.id!);
      setState(() => _history = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Staff header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.amber.shade100,
                  child: Text(
                    widget.staff.surname[0].toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.staff.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Current: ${widget.currencyFormat.format(widget.staff.salary)}',
                        style: const TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ─── NEW INCREMENT FORM ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Salary Increment',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.amber.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // New salary amount
                  TextField(
                    controller: _newSalaryCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'New Salary Amount (₦)',
                      prefixIcon: Icon(Icons.money),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Effective month picker
                  InkWell(
                    onTap: _pickMonth,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Effective From Month',
                        prefixIcon: Icon(Icons.calendar_month),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(_selectedMonth),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Reason
                  TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reason (Optional)',
                      hintText: 'e.g. Annual increment, Promotion...',
                      prefixIcon: Icon(Icons.note),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? 'Saving...' : 'Save Increment'),
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ─── SALARY HISTORY ─────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.history, size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  'Salary History (${_history.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_history.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No salary history yet. Add the first increment above.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...(_history.map((record) => _buildHistoryRow(record))),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryRow(Map<String, dynamic> record) {
    final salary = (record['salary'] as num).toDouble();
    final effectiveMonth = record['effectiveMonth'] as String;
    final reason = record['reason'] as String?;
    final createdAt = record['createdAt'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.trending_up, color: Colors.green.shade600, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.currencyFormat.format(salary),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.green,
                  ),
                ),
                Text(
                  'Effective: $effectiveMonth',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                if (reason != null && reason.isNotEmpty)
                  Text(
                    reason,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                if (createdAt != null)
                  Text(
                    'Recorded: ${_formatDate(createdAt)}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: () => _deleteHistory(record['id'] as int),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }
}
