import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import 'expense_form_screen.dart';

enum DateFilter { all, today, thisWeek, thisMonth, custom }

class ExpenseListScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const ExpenseListScreen({super.key, required this.currentUser});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> with SingleTickerProviderStateMixin {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00');

  List<Map<String, dynamic>> _expenses = [];
  final Map<int, Map<String, dynamic>> _lastEditByExpenseId = {};
  String? _activeTerm;
  String? _activeSession;
  bool _loading = true;
  final Map<String, double> _categoryTotals = {};
  double _totalExpenses = 0;

  DateFilter _selectedFilter = DateFilter.today;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  TabController? _tabController;
  List<String> _categoryTabs = const ['All'];

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  String get _selectedCategoryTab {
    if (_tabController == null || _categoryTabs.isEmpty) return 'All';
    return _categoryTabs[_tabController!.index];
  }

  List<Map<String, dynamic>> get _filteredExpenses {
    if (_selectedCategoryTab == 'All') return _expenses;
    return _expenses.where((expense) {
      final category = expense['category'] ?? 'Uncategorized';
      final customCategory = expense['customCategory'];
      final displayCategory = category == 'Other' && customCategory != null
          ? 'Other: $customCategory'
          : category;
      return displayCategory == _selectedCategoryTab;
    }).toList();
  }

  double get _summaryTotal {
    if (_selectedCategoryTab == 'All') return _totalExpenses;
    return _categoryTotals[_selectedCategoryTab] ?? 0;
  }

  void _updateCategoryTabs() {
    final newTabs = ['All', ...(_categoryTotals.keys.toList()..sort())];

    if (listEquals(newTabs, _categoryTabs) && _tabController != null) {
      return;
    }

    final previousSelection = _selectedCategoryTab;
    _categoryTabs = newTabs;
    final newIndex = _categoryTabs.contains(previousSelection)
        ? _categoryTabs.indexOf(previousSelection)
        : 0;

    _tabController?.dispose();
    _tabController = TabController(
      length: _categoryTabs.length,
      vsync: this,
      initialIndex: newIndex,
    );
  }

  (String?, String?) _getDateRange() {
    final now = DateTime.now();
    String? startDate;
    String? endDate;

    switch (_selectedFilter) {
      case DateFilter.today:
        final todayStart = DateTime(now.year, now.month, now.day);
        final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
        startDate = todayStart.toIso8601String();
        endDate = todayEnd.toIso8601String();
        break;
      case DateFilter.thisWeek:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final weekStartDay = DateTime(weekStart.year, weekStart.month, weekStart.day);
        startDate = weekStartDay.toIso8601String();
        endDate = now.toIso8601String();
        break;
      case DateFilter.thisMonth:
        final monthStart = DateTime(now.year, now.month, 1);
        startDate = monthStart.toIso8601String();
        endDate = now.toIso8601String();
        break;
      case DateFilter.custom:
        if (_customStartDate != null) {
          final customStart = DateTime(_customStartDate!.year, _customStartDate!.month, _customStartDate!.day);
          startDate = customStart.toIso8601String();
        }
        if (_customEndDate != null) {
          final customEnd = DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day, 23, 59, 59);
          endDate = customEnd.toIso8601String();
        }
        break;
      case DateFilter.all:
        break;
    }

    return (startDate, endDate);
  }

  String _getFilterDisplayText() {
    switch (_selectedFilter) {
      case DateFilter.today:
        return 'Today';
      case DateFilter.thisWeek:
        return 'This Week';
      case DateFilter.thisMonth:
        return 'This Month';
      case DateFilter.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('MMM dd').format(_customStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}';
        } else if (_customStartDate != null) {
          return 'From ${DateFormat('MMM dd, yyyy').format(_customStartDate!)}';
        } else if (_customEndDate != null) {
          return 'Until ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}';
        }
        return 'Custom Range';
      case DateFilter.all:
        return 'All Expenses';
    }
  }

  Future<void> _loadExpenses() async {
    setState(() => _loading = true);

    try {
      _activeTerm = await _db.getActiveTerm();
      final sessionData = await _db.getActiveSession();
      _activeSession = sessionData?['sessionName'];

      final (startDate, endDate) = _getDateRange();

      _expenses = await _db.getAllExpenses(
        term: _activeTerm,
        session: _activeSession,
        startDate: startDate,
        endDate: endDate,
      );

      _lastEditByExpenseId.clear();
      for (final expense in _expenses) {
        final expenseId = expense['id'] as int?;
        if (expenseId == null) continue;
        final entries = await _db.getAuditLog(entityType: 'expense', entityId: expenseId);
        final lastUpdate = entries.firstWhere(
          (e) => e['action'] == 'update',
          orElse: () => const {},
        );
        if (lastUpdate.isNotEmpty) {
          _lastEditByExpenseId[expenseId] = lastUpdate;
        }
      }

      _calculateTotals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading expenses: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _calculateTotals() {
    _categoryTotals.clear();
    _totalExpenses = 0;

    for (var expense in _expenses) {
      final amount = (expense['amount'] as num?)?.toDouble() ?? 0.0;
      final category = expense['category'] ?? 'Uncategorized';
      final customCategory = expense['customCategory'];

      final displayCategory = category == 'Other' && customCategory != null
          ? 'Other: $customCategory'
          : category;

      _categoryTotals[displayCategory] = (_categoryTotals[displayCategory] ?? 0) + amount;
      _totalExpenses += amount;
    }

    _updateCategoryTabs();
  }

  void _setFilter(DateFilter filter) {
    setState(() {
      _selectedFilter = filter;
      if (filter != DateFilter.custom) {
        _customStartDate = null;
        _customEndDate = null;
      }
    });
    _loadExpenses();
  }

  Future<void> _showCustomDatePicker() async {
    final now = DateTime.now();

    final startDate = await showDatePicker(
      context: context,
      initialDate: _customStartDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Select Start Date',
    );

    if (startDate == null) return;

    if (!mounted) return;

    final endDate = await showDatePicker(
      context: context,
      initialDate: _customEndDate ?? now,
      firstDate: startDate,
      lastDate: now,
      helpText: 'Select End Date',
    );

    if (endDate == null) return;

    setState(() {
      _customStartDate = startDate;
      _customEndDate = endDate;
      _selectedFilter = DateFilter.custom;
    });
    _loadExpenses();
  }

  Future<void> _navigateToAddExpense() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(currentUser: widget.currentUser),
      ),
    );

    if (result == true) {
      _loadExpenses();
    }
  }

  Future<void> _editExpense(Map<String, dynamic> expense) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          currentUser: widget.currentUser,
          expense: expense,
        ),
      ),
    );

    if (result == true) {
      _loadExpenses();
    }
  }

  void _showAuditDiffDialog(Map<String, dynamic> auditEntry) {
    final changesRaw = auditEntry['changes'] as String?;
    Map<String, dynamic> diff = {};
    if (changesRaw != null && changesRaw.isNotEmpty) {
      try {
        diff = Map<String, dynamic>.from(jsonDecode(changesRaw) as Map);
      } catch (_) {}
    }
    final username = auditEntry['username']?.toString() ?? 'Unknown';
    final timestamp = DateTime.tryParse(auditEntry['timestamp']?.toString() ?? '');
    final formattedWhen = timestamp != null
        ? DateFormat('dd/MM/yyyy, h:mm a').format(timestamp)
        : '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, color: Colors.orange),
            SizedBox(width: 8),
            Text('Edit History'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edited by $username',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (formattedWhen.isNotEmpty)
                Text(formattedWhen,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              ...diff.entries.map((e) {
                final change = e.value as Map;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${e.key}: ${change['old']} → ${change['new']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteExpense(int id, String description) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content: Text('Are you sure you want to delete this expense?\n\n"$description"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _db.deleteExpense(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense deleted successfully')),
          );
        }
        _loadExpenses();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting expense: $e')),
          );
        }
      }
    }
  }

  Color _getCategoryColor(String category) {
    if (category.startsWith('Other:')) return Colors.grey;

    switch (category) {
      case 'Staff Loan':
        return Colors.blue;
      case 'Utilities':
        return Colors.orange;
      case 'Maintenance & Repairs':
        return Colors.green;
      case 'Office Supplies':
        return Colors.purple;
      case 'Other':
        return Colors.grey;
      default:
        return Colors.brown;
    }
  }

  IconData _getCategoryIcon(String category) {
    if (category.startsWith('Other:')) return Icons.more_horiz;

    switch (category) {
      case 'Staff Loan':
        return Icons.people;
      case 'Utilities':
        return Icons.bolt;
      case 'Maintenance & Repairs':
        return Icons.build;
      case 'Office Supplies':
        return Icons.inventory;
      case 'Other':
        return Icons.more_horiz;
      default:
        return Icons.receipt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadExpenses,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Active Term/Session Info Card
                  Card(
                    elevation: 2,
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.info_outline, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Showing expenses for $_activeTerm, $_activeSession',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Date Filter Section
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.filter_list, size: 20, color: Colors.brown.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Date Filter',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _getFilterDisplayText(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.brown.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('All', style: TextStyle(fontSize: 13)),
                                selected: _selectedFilter == DateFilter.all,
                                onSelected: (_) => _setFilter(DateFilter.all),
                                selectedColor: Colors.brown.shade200,
                                checkmarkColor: Colors.brown.shade900,
                                backgroundColor: Colors.grey.shade100,
                                elevation: 2,
                                pressElevation: 4,
                              ),
                              FilterChip(
                                label: const Text('Today', style: TextStyle(fontSize: 13)),
                                selected: _selectedFilter == DateFilter.today,
                                onSelected: (_) => _setFilter(DateFilter.today),
                                selectedColor: Colors.brown.shade200,
                                checkmarkColor: Colors.brown.shade900,
                                backgroundColor: Colors.grey.shade100,
                                elevation: 2,
                                pressElevation: 4,
                              ),
                              FilterChip(
                                label: const Text('This Week', style: TextStyle(fontSize: 13)),
                                selected: _selectedFilter == DateFilter.thisWeek,
                                onSelected: (_) => _setFilter(DateFilter.thisWeek),
                                selectedColor: Colors.brown.shade200,
                                checkmarkColor: Colors.brown.shade900,
                                backgroundColor: Colors.grey.shade100,
                                elevation: 2,
                                pressElevation: 4,
                              ),
                              FilterChip(
                                label: const Text('This Month', style: TextStyle(fontSize: 13)),
                                selected: _selectedFilter == DateFilter.thisMonth,
                                onSelected: (_) => _setFilter(DateFilter.thisMonth),
                                selectedColor: Colors.brown.shade200,
                                checkmarkColor: Colors.brown.shade900,
                                backgroundColor: Colors.grey.shade100,
                                elevation: 2,
                                pressElevation: 4,
                              ),
                              ActionChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.date_range, size: 16, color: Colors.brown.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      _selectedFilter == DateFilter.custom ? 'Change Range' : 'Custom Range',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                                onPressed: _showCustomDatePicker,
                                backgroundColor: _selectedFilter == DateFilter.custom
                                    ? Colors.brown.shade200
                                    : Colors.grey.shade100,
                                elevation: 2,
                                pressElevation: 4,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Category Tabs
                  if (_categoryTabs.length > 1 && _tabController != null)
                    Card(
                      elevation: 2,
                      margin: EdgeInsets.zero,
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        labelColor: Colors.brown.shade900,
                        unselectedLabelColor: Colors.grey.shade600,
                        indicatorColor: Colors.brown,
                        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(fontSize: 13),
                        onTap: (_) => setState(() {}),
                        tabs: _categoryTabs.map((c) => Tab(text: c)).toList(),
                      ),
                    ),

                  if (_categoryTabs.length > 1 && _tabController != null)
                    const SizedBox(height: 16),

                  // Summary Card
                  Card(
                    elevation: 3,
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.receipt_outlined, color: Colors.brown.shade700, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                _selectedCategoryTab == 'All'
                                    ? 'EXPENSE SUMMARY'
                                    : 'SUMMARY - ${_selectedCategoryTab.toUpperCase()}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),

                          // Category breakdown (only when viewing all categories)
                          if (_selectedCategoryTab == 'All' && _categoryTotals.isNotEmpty) ...[
                            ..._categoryTotals.entries.map((entry) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(entry.key),
                                  Text(
                                    'N ${_currencyFormat.format(entry.value)}',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            )),
                            const Divider(height: 20),
                          ],

                          // Total
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _selectedCategoryTab == 'All' ? 'TOTAL EXPENSES' : 'CATEGORY TOTAL',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'N ${_currencyFormat.format(_summaryTotal)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Expense List
                  if (_filteredExpenses.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.receipt_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _expenses.isEmpty
                                  ? 'No expenses recorded'
                                  : 'No expenses in "$_selectedCategoryTab"',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_expenses.isEmpty)
                              Text(
                                'Tap the + button to add an expense',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._filteredExpenses.map((expense) {
                      final amount = (expense['amount'] as num?)?.toDouble() ?? 0.0;
                      final category = expense['category'] ?? 'Uncategorized';
                      final customCategory = expense['customCategory'];
                      final displayCategory = category == 'Other' && customCategory != null
                          ? 'Other: $customCategory'
                          : category;
                      final description = expense['description'] ?? '';
                      final recipient = expense['recipient'] ?? '';
                      final method = expense['paymentMethod'] ?? '';
                      final date = expense['expenseDate'] ?? '';
                      final dateDisplay = date.length >= 10 ? date.substring(0, 10) : date;
                      final lastEdit = _lastEditByExpenseId[expense['id'] as int?];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getCategoryColor(displayCategory),
                            child: Icon(
                              _getCategoryIcon(displayCategory),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            description,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('$displayCategory • $recipient'),
                              Text(
                                '$method • $dateDisplay',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              Text(
                                'N ${_currencyFormat.format(amount)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                              if (lastEdit != null)
                                InkWell(
                                  onTap: () => _showAuditDiffDialog(lastEdit),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_note,
                                          size: 13, color: Colors.orange.shade700),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Edited by ${lastEdit['username'] ?? 'Unknown'}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange.shade700,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _editExpense(expense),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteExpense(
                                  expense['id'] as int,
                                  description,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddExpense,
        backgroundColor: Colors.brown,
        child: const Icon(Icons.add),
      ),
    );
  }
}
