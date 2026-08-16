// lib/screens/billing/last_term_debtors_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';

class LastTermDebtorsScreen extends StatefulWidget {
  const LastTermDebtorsScreen({super.key});

  @override
  State<LastTermDebtorsScreen> createState() => _LastTermDebtorsScreenState();
}

class _LastTermDebtorsScreenState extends State<LastTermDebtorsScreen> {
  final _db = DatabaseHelperWrapper();
  final _fmt = NumberFormat('#,##0.00');

  bool _loading = true;
  String? _term;
  String? _session;

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];

  int _selectedClassId = 0; // 0 = All Classes
  int _selectedArmId = 0;   // 0 = All Arms

  // 'all' | 'fully_covered' | 'partially_covered' | 'not_covered'
  String _statusFilter = 'all';

  List<Map<String, dynamic>> _students = [];
  bool _generated = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    _term = await _db.getActiveTerm();
    final sessionData = await _db.getActiveSession();
    _session = sessionData?['sessionName'] ?? '';
    _classes = await _db.getClasses();
    setState(() => _loading = false);
  }

  Future<void> _onClassChanged(int classId) async {
    setState(() {
      _selectedClassId = classId;
      _selectedArmId = 0;
      _arms = [];
      _students = [];
      _generated = false;
    });

    if (classId > 0) {
      final arms = await _db.getArmsByClass(classId);
      setState(() => _arms = arms);
    }
  }

  Future<void> _generate() async {
    setState(() => _loading = true);

    try {
      final results = await _db.getLastTermDebtors(
        term: _term!,
        session: _session!,
        classId: _selectedClassId,
        armId: _selectedArmId,
      );
      setState(() {
        _students = results;
        _generated = true;
        _loading = false;
      });

      if (results.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No students with previous balance found for the selected filter'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'all') return _students;
    return _students.where((s) => s['debtStatus'] == _statusFilter).toList();
  }

  String _className(int classId) {
    if (classId == 0) return 'All Classes';
    return _classes.firstWhere(
      (c) => c['id'] == classId,
      orElse: () => {'name': ''},
    )['name'] as String;
  }

  String _armName(int armId) {
    if (armId == 0) return 'All Arms';
    return _arms.firstWhere(
      (a) => a['id'] == armId,
      orElse: () => {'name': ''},
    )['name'] as String;
  }

  // ── Summary totals ──────────────────────────────────────────────
  Map<String, double> _totals(List<Map<String, dynamic>> rows) {
    double prevBal = 0, paid = 0, applied = 0, remaining = 0;
    for (final r in rows) {
      prevBal += (r['previousBalance'] as num).toDouble();
      paid += (r['totalPaidThisTerm'] as num).toDouble();
      applied += (r['appliedToDebt'] as num).toDouble();
      remaining += (r['remainingDebt'] as num).toDouble();
    }
    return {
      'previousBalance': prevBal,
      'totalPaidThisTerm': paid,
      'appliedToDebt': applied,
      'remainingDebt': remaining,
    };
  }

  // ── Status helpers ───────────────────────────────────────────────
  Color _statusColor(String status) {
    switch (status) {
      case 'fully_covered':
        return Colors.green;
      case 'partially_covered':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'fully_covered':
        return 'Covered';
      case 'partially_covered':
        return 'Partial';
      default:
        return 'Unpaid';
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'fully_covered':
        return Icons.check_circle_outline;
      case 'partially_covered':
        return Icons.timelapse_outlined;
      default:
        return Icons.cancel_outlined;
    }
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Last Term Debtors'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(ds.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPeriodCard(ds),
                  SizedBox(height: ds.cardPadding),
                  _buildFilterCard(ds),
                  if (_generated && _students.isNotEmpty) ...[
                    SizedBox(height: ds.cardPadding),
                    _buildStatusFilterChips(ds),
                    SizedBox(height: ds.cardPadding),
                    _buildSummaryCard(ds),
                    SizedBox(height: ds.cardPadding),
                    _buildResultsTable(ds),
                  ],
                ],
              ),
            ),
    );
  }

  // ── Period card ──────────────────────────────────────────────────
  Widget _buildPeriodCard(DisplaySettings ds) {
    return Card(
      color: Colors.deepOrange[50],
      child: Padding(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Row(
          children: [
            Icon(Icons.history_edu_outlined,
                color: Colors.deepOrange[700], size: ds.iconSize * 1.2),
            SizedBox(width: ds.cardPadding * 0.75),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Showing previous balance for',
                  style: TextStyle(
                      fontSize: ds.subtitleFontSize,
                      color: Colors.grey[700]),
                ),
                Text(
                  '$_term  •  $_session',
                  style: TextStyle(
                      fontSize: ds.titleFontSize,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter card ──────────────────────────────────────────────────
  Widget _buildFilterCard(DisplaySettings ds) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter Options',
                style: TextStyle(
                    fontSize: ds.titleFontSize,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: ds.cardPadding),

            // Class dropdown
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.school_outlined),
              ),
              initialValue: _selectedClassId,
              items: [
                const DropdownMenuItem(value: 0, child: Text('All Classes')),
                ..._classes.map((c) => DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text(c['name'] as String),
                    )),
              ],
              onChanged: (v) => _onClassChanged(v ?? 0),
            ),

            // Arm dropdown (only when a specific class is chosen)
            if (_selectedClassId > 0 && _arms.isNotEmpty) ...[
              SizedBox(height: ds.cardPadding * 0.75),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Arm',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.groups_outlined),
                ),
                initialValue: _selectedArmId,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('All Arms')),
                  ..._arms.map((a) => DropdownMenuItem<int>(
                        value: a['id'] as int,
                        child: Text(a['name'] as String),
                      )),
                ],
                onChanged: (v) => setState(() {
                  _selectedArmId = v ?? 0;
                  _students = [];
                  _generated = false;
                }),
              ),
            ],

            SizedBox(height: ds.cardPadding),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.search),
                label: const Text('Generate List'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.all(ds.cardPadding),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status filter chips ──────────────────────────────────────────
  Widget _buildStatusFilterChips(DisplaySettings ds) {
    final counts = <String, int>{
      'all': _students.length,
      'not_covered': _students.where((s) => s['debtStatus'] == 'not_covered').length,
      'partially_covered': _students.where((s) => s['debtStatus'] == 'partially_covered').length,
      'fully_covered': _students.where((s) => s['debtStatus'] == 'fully_covered').length,
    };

    final options = [
      ('all', 'All', Colors.blueGrey),
      ('not_covered', 'Unpaid', Colors.red),
      ('partially_covered', 'Partial', Colors.orange),
      ('fully_covered', 'Covered', Colors.green),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options.map((opt) {
        final (value, label, color) = opt;
        final selected = _statusFilter == value;
        final count = counts[value] ?? 0;
        return FilterChip(
          label: Text('$label ($count)'),
          selected: selected,
          selectedColor: color.withValues(alpha: 0.2),
          checkmarkColor: color,
          labelStyle: TextStyle(
            color: selected ? color : Colors.grey[700],
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
          side: BorderSide(color: selected ? color : Colors.grey[300]!),
          onSelected: (_) => setState(() => _statusFilter = value),
        );
      }).toList(),
    );
  }

  // ── Summary card ─────────────────────────────────────────────────
  Widget _buildSummaryCard(DisplaySettings ds) {
    final rows = _filtered;
    final t = _totals(rows);
    final coverageRate = t['previousBalance']! > 0
        ? (t['appliedToDebt']! / t['previousBalance']! * 100)
        : 0.0;

    return Container(
      padding: EdgeInsets.all(ds.cardPadding),
      decoration: BoxDecoration(
        color: Colors.deepOrange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepOrange[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_outlined,
                  color: Colors.deepOrange[700], size: ds.iconSize),
              SizedBox(width: 8),
              Text(
                'Summary — ${rows.length} student${rows.length == 1 ? '' : 's'}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: ds.titleFontSize),
              ),
            ],
          ),
          SizedBox(height: ds.cardPadding),
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                    'Previous Debt', t['previousBalance']!, Colors.red, ds),
              ),
              Expanded(
                child: _summaryTile(
                    'Paid This Term', t['totalPaidThisTerm']!, Colors.blue, ds),
              ),
            ],
          ),
          SizedBox(height: ds.cardPadding * 0.5),
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                    'Applied to Debt', t['appliedToDebt']!, Colors.green, ds),
              ),
              Expanded(
                child: _summaryTile(
                    'Remaining Debt', t['remainingDebt']!, Colors.deepOrange, ds),
              ),
            ],
          ),
          SizedBox(height: ds.cardPadding * 0.75),
          // Coverage progress bar
          Row(
            children: [
              Text('Debt Coverage: ',
                  style: TextStyle(fontSize: ds.subtitleFontSize)),
              Text(
                '${coverageRate.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: ds.subtitleFontSize,
                    color: coverageRate >= 80
                        ? Colors.green
                        : coverageRate >= 50
                            ? Colors.orange
                            : Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (coverageRate / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(
                coverageRate >= 80
                    ? Colors.green
                    : coverageRate >= 50
                        ? Colors.orange
                        : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(
      String label, double amount, Color color, DisplaySettings ds) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: EdgeInsets.all(ds.cardPadding * 0.6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: ds.subtitleFontSize * 0.9,
                    color: Colors.grey[700])),
            const SizedBox(height: 4),
            Text(
              _fmt.format(amount),
              style: TextStyle(
                  fontSize: ds.bodyFontSize,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ── Results table ────────────────────────────────────────────────
  Widget _buildResultsTable(DisplaySettings ds) {
    final rows = _filtered;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Students (${rows.length})',
                  style: TextStyle(
                      fontSize: ds.titleFontSize,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_className(_selectedClassId)}'
                  '${_selectedArmId > 0 ? ' › ${_armName(_selectedArmId)}' : ''}',
                  style: TextStyle(
                      fontSize: ds.subtitleFontSize, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No students match the selected status filter',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(Colors.grey[100]),
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(
                        label: Text('S/N',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Adm. No',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Student Name',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Class/Arm',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Prev. Debt',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        numeric: true),
                    DataColumn(
                        label: Text('Paid This Term',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        numeric: true),
                    DataColumn(
                        label: Text('Applied to Debt',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        numeric: true),
                    DataColumn(
                        label: Text('Remaining Debt',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        numeric: true),
                    DataColumn(
                        label: Text('Status',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: rows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final s = entry.value;

                    final prevBal = (s['previousBalance'] as num).toDouble();
                    final paid = (s['totalPaidThisTerm'] as num).toDouble();
                    final applied = (s['appliedToDebt'] as num).toDouble();
                    final remaining = (s['remainingDebt'] as num).toDouble();
                    final status = s['debtStatus'] as String;
                    final statusColor = _statusColor(status);

                    final className = s['className'] ?? '';
                    final armName = s['armName'] ?? '';
                    final classArm = armName.isNotEmpty
                        ? '$className - $armName'
                        : className;

                    return DataRow(
                      cells: [
                        DataCell(Text('${i + 1}')),
                        DataCell(Text(s['admissionNo'] ?? '')),
                        DataCell(
                          Text(
                            '${s['surname']} ${s['firstName']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        DataCell(
                          Text(classArm,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[700])),
                        ),
                        DataCell(
                          Text(
                            _fmt.format(prevBal),
                            style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(
                          Text(
                            _fmt.format(paid),
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ),
                        DataCell(
                          Text(
                            _fmt.format(applied),
                            style: const TextStyle(color: Colors.green),
                          ),
                        ),
                        DataCell(
                          Text(
                            _fmt.format(remaining),
                            style: TextStyle(
                              color: remaining > 0
                                  ? Colors.deepOrange
                                  : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_statusIcon(status),
                                    size: 14, color: statusColor),
                                const SizedBox(width: 4),
                                Text(
                                  _statusLabel(status),
                                  style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
