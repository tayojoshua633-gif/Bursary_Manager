// lib/screens/reports/activity_log_screen.dart
// Financial activity/audit trail — who created, edited, or deleted a
// payment, expense, staff financial record (loans, deductions, incentives,
// salary payments, salary increments), stock item, supplier, or sale, and
// when. Stock quantity changes themselves (adjust/restock/sale/return) are
// tracked separately in stock_movements, not duplicated here.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final NumberFormat _fmt = NumberFormat('#,##0.00');

  bool _loading = true;
  List<Map<String, dynamic>> _entries = [];
  final Map<int, String> _studentNameCache = {};
  final Map<int, String> _expenseLabelCache = {};
  final Map<int, String> _staffNameCache = {};
  final Map<int, String> _stockItemLabelCache = {};
  final Map<int, String> _supplierLabelCache = {};
  final Map<int, String> _saleLabelCache = {};

  DateTime? _fromDate;
  DateTime? _toDate;
  String _actionFilter = 'all'; // all | create | update | delete
  String _userFilter = 'all';

  static const Set<String> _staffEntityTypes = {
    'staff_loan',
    'staff_deduction',
    'staff_incentive',
    'staff_salary_payment',
    'staff_salary_history',
  };

  static const Map<String, String> _staffEntityLabels = {
    'staff_loan': 'Loan',
    'staff_deduction': 'Deduction',
    'staff_incentive': 'Incentive',
    'staff_salary_payment': 'Salary Payment',
    'staff_salary_history': 'Salary Increment',
  };

  // Tabs group entries by record type — `types: null` means "no filter" (All).
  static const List<({String label, Set<String>? types})> _tabs = [
    (label: 'All', types: null),
    (label: 'Payments', types: {'payment'}),
    (label: 'Expenses', types: {'expense'}),
    (label: 'Staff Financial', types: _staffEntityTypes),
    (label: 'Stock & Sales', types: {'stock_item', 'supplier', 'sale'}),
  ];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
    // Default to today's activity rather than the full history.
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final entries = await _db.getAuditLog(
      from: _fromDate,
      // include the whole "to" day
      to: _toDate?.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
    );

    for (final entry in entries) {
      final entityType = entry['entityType']?.toString();
      final entityId = entry['entityId'] as int?;
      if (entityId == null) continue;

      if (entityType == 'payment') {
        final studentId = entry['studentId'] as int?;
        if (studentId == null || _studentNameCache.containsKey(studentId)) continue;
        final student = await _db.getStudentById(studentId);
        if (student != null) {
          final name =
              '${student['surname'] ?? ''} ${student['firstName'] ?? ''}'.trim();
          _studentNameCache[studentId] = name.isEmpty ? 'Unknown Student' : name;
        } else {
          _studentNameCache[studentId] = 'Unknown Student';
        }
      } else if (entityType == 'expense') {
        if (_expenseLabelCache.containsKey(entityId)) continue;
        // The expense may still exist (create/update) or may have been
        // deleted — fall back to the snapshot stored in the audit entry.
        final expense = await _db.getExpenseById(entityId);
        String? label = expense != null
            ? '${expense['description'] ?? ''}'.trim()
            : null;
        if (label == null || label.isEmpty) {
          final changesRaw = entry['changes'] as String?;
          if (changesRaw != null && changesRaw.isNotEmpty) {
            try {
              final snapshot = Map<String, dynamic>.from(jsonDecode(changesRaw) as Map);
              label = snapshot['description']?.toString();
            } catch (_) {}
          }
        }
        _expenseLabelCache[entityId] = (label == null || label.isEmpty)
            ? 'Expense #$entityId'
            : label;
      } else if (entityType != null && _staffEntityTypes.contains(entityType)) {
        final staffId = entry['staffId'] as int?;
        if (staffId == null || _staffNameCache.containsKey(staffId)) continue;
        final staff = await _db.getStaffById(staffId);
        if (staff != null) {
          final name = '${staff['surname'] ?? ''} ${staff['firstName'] ?? ''}'.trim();
          _staffNameCache[staffId] = name.isEmpty ? 'Unknown Staff' : name;
        } else {
          _staffNameCache[staffId] = 'Unknown Staff';
        }
      } else if (entityType == 'stock_item') {
        if (_stockItemLabelCache.containsKey(entityId)) continue;
        final item = await _db.getStockItemById(entityId);
        String? label = item?['itemName']?.toString();
        label ??= _labelFromSnapshot(entry, 'itemName');
        _stockItemLabelCache[entityId] =
            (label == null || label.isEmpty) ? 'Stock Item #$entityId' : label;
      } else if (entityType == 'supplier') {
        if (_supplierLabelCache.containsKey(entityId)) continue;
        final supplier = await _db.getSupplierById(entityId);
        String? label = supplier?['supplierName']?.toString();
        label ??= _labelFromSnapshot(entry, 'supplierName');
        _supplierLabelCache[entityId] =
            (label == null || label.isEmpty) ? 'Supplier #$entityId' : label;
      } else if (entityType == 'sale') {
        if (_saleLabelCache.containsKey(entityId)) continue;
        final sale = await _db.getSaleById(entityId);
        String? label = sale != null
            ? '${sale['itemName'] ?? ''} — ${sale['buyerName'] ?? ''}'.trim()
            : null;
        if (label == null || label == '—') {
          final itemName = _labelFromSnapshot(entry, 'itemName');
          final buyerName = _labelFromSnapshot(entry, 'buyerName');
          if (itemName != null || buyerName != null) {
            label = '${itemName ?? ''} — ${buyerName ?? ''}'.trim();
          }
        }
        _saleLabelCache[entityId] =
            (label == null || label.isEmpty || label == '—') ? 'Sale #$entityId' : label;
      }
    }

    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  /// Falls back to the `changes` snapshot stored on the audit entry for a
  /// given field — needed once the underlying record has been deleted and
  /// a live lookup no longer resolves.
  String? _labelFromSnapshot(Map<String, dynamic> entry, String field) {
    final changesRaw = entry['changes'] as String?;
    if (changesRaw == null || changesRaw.isEmpty) return null;
    try {
      final snapshot = Map<String, dynamic>.from(jsonDecode(changesRaw) as Map);
      return snapshot[field]?.toString();
    } catch (_) {
      return null;
    }
  }

  List<String> get _availableUsers {
    final names = _entries
        .map((e) => e['username']?.toString() ?? 'Unknown')
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  List<Map<String, dynamic>> get _filteredEntries {
    final tabTypes = _tabs[_tabController.index].types;
    return _entries.where((e) {
      if (_actionFilter != 'all' && e['action'] != _actionFilter) return false;
      if (tabTypes != null && !tabTypes.contains(e['entityType'])) return false;
      if (_userFilter != 'all' && (e['username']?.toString() ?? 'Unknown') != _userFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      await _load();
    }
  }

  void _clearDateRange() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _load();
  }

  void _selectToday() {
    final now = DateTime.now();
    setState(() {
      _fromDate = DateTime(now.year, now.month, now.day);
      _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    });
    _load();
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _isTodaySelected {
    if (_fromDate == null || _toDate == null) return false;
    final now = DateTime.now();
    return _isSameDate(_fromDate!, now) && _isSameDate(_toDate!, now);
  }

  bool get _isAllDatesSelected => _fromDate == null && _toDate == null;

  ({IconData icon, Color color, String label}) _actionStyle(String action) {
    switch (action) {
      case 'create':
        return (icon: Icons.add_circle, color: Colors.green.shade700, label: 'Created');
      case 'delete':
        return (icon: Icons.delete, color: Colors.red.shade700, label: 'Deleted');
      case 'update':
      default:
        return (icon: Icons.edit_note, color: Colors.orange.shade700, label: 'Edited');
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Log'),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? Center(
                        child: Text(
                          'No activity recorded yet',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _buildEntryCard(entries[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey.shade100,
      child: Column(
        children: [
          Row(
            children: [
              ChoiceChip(
                label: const Text('Today'),
                selected: _isTodaySelected,
                onSelected: (_) => _selectToday(),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('All dates'),
                selected: _isAllDatesSelected,
                onSelected: (_) => _clearDateRange(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    !_isTodaySelected &&
                            !_isAllDatesSelected &&
                            _fromDate != null &&
                            _toDate != null
                        ? '${DateFormat('dd/MM/yy').format(_fromDate!)} - ${DateFormat('dd/MM/yy').format(_toDate!)}'
                        : 'Custom',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _actionFilter,
                  decoration: const InputDecoration(
                    labelText: 'Action',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Actions')),
                    DropdownMenuItem(value: 'create', child: Text('Created')),
                    DropdownMenuItem(value: 'update', child: Text('Edited')),
                    DropdownMenuItem(value: 'delete', child: Text('Deleted')),
                  ],
                  onChanged: (v) => setState(() => _actionFilter = v ?? 'all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _userFilter,
                  decoration: const InputDecoration(
                    labelText: 'User',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Users')),
                    ..._availableUsers.map(
                      (u) => DropdownMenuItem(value: u, child: Text(u)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _userFilter = v ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Colors.indigo,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.indigo,
              tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry) {
    final action = entry['action']?.toString() ?? 'update';
    final style = _actionStyle(action);
    final entityType = entry['entityType']?.toString();
    final entityId = entry['entityId'] as int?;

    final String recordLabel;
    if (entityType == 'expense') {
      recordLabel = entityId != null
          ? (_expenseLabelCache[entityId] ?? 'Expense #$entityId')
          : 'Expense';
    } else if (entityType != null && _staffEntityTypes.contains(entityType)) {
      final staffId = entry['staffId'] as int?;
      final staffName =
          staffId != null ? (_staffNameCache[staffId] ?? '...') : 'Unknown Staff';
      recordLabel = '${_staffEntityLabels[entityType] ?? 'Staff Record'} — $staffName';
    } else if (entityType == 'stock_item') {
      recordLabel = entityId != null
          ? (_stockItemLabelCache[entityId] ?? 'Stock Item #$entityId')
          : 'Stock Item';
    } else if (entityType == 'supplier') {
      recordLabel = entityId != null
          ? (_supplierLabelCache[entityId] ?? 'Supplier #$entityId')
          : 'Supplier';
    } else if (entityType == 'sale') {
      recordLabel =
          entityId != null ? (_saleLabelCache[entityId] ?? 'Sale #$entityId') : 'Sale';
    } else {
      final studentId = entry['studentId'] as int?;
      recordLabel =
          studentId != null ? (_studentNameCache[studentId] ?? '...') : 'Unknown Student';
    }

    final amount = (entry['amount'] as num?)?.toDouble();
    final username = entry['username']?.toString() ?? 'Unknown';
    final timestamp = DateTime.tryParse(entry['timestamp']?.toString() ?? '');
    final formattedWhen =
        timestamp != null ? DateFormat('dd/MM/yyyy, h:mm a').format(timestamp) : '';

    Map<String, dynamic> changes = {};
    final changesRaw = entry['changes'] as String?;
    if (changesRaw != null && changesRaw.isNotEmpty) {
      try {
        changes = Map<String, dynamic>.from(jsonDecode(changesRaw) as Map);
      } catch (_) {}
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(style.icon, color: style.color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${style.label} — $recordLabel',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (amount != null)
                  Text(
                    'N${_fmt.format(amount)}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: style.color),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'by $username · $formattedWhen',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (action == 'update' && changes.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.entries.map((e) {
                final change = e.value as Map;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${e.key}: ${change['old']} → ${change['new']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
