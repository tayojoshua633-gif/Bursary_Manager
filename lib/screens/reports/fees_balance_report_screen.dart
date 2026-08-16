// lib/screens/reports/fees_balance_report_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';

class FeesBalanceReportScreen extends StatefulWidget {
  const FeesBalanceReportScreen({super.key});

  @override
  State<FeesBalanceReportScreen> createState() => _FeesBalanceReportScreenState();
}

class _FeesBalanceReportScreenState extends State<FeesBalanceReportScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final NumberFormat _money = NumberFormat('#,##0.00');

  bool _loading = true;
  bool _generating = false;
  String? _term;
  String? _session;

  List<Map<String, dynamic>> _classes = [];
  int _selectedClassId = 0; // 0 = All Classes

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _balancedStudents = [];

  Map<String, dynamic>? _prevTermSummary;
  String? _prevTermLabel;

  Map<String, dynamic>? _prevSessionSummary;
  String? _prevSessionLabel;

  // Collapsible sections — folded by default, expand on tap.
  bool _statsExpanded = false;
  bool _termCompExpanded = false;
  bool _sessionCompExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);

    _term = await _db.getActiveTerm();
    final sessionData = await _db.getActiveSession();
    _session = sessionData?['sessionName'] ?? '';

    _classes = await _db.getClasses();

    setState(() => _loading = false);

    await _generateReport();
  }

  Future<void> _generateReport() async {
    if (_term == null || _session == null || _session!.isEmpty) return;

    setState(() => _generating = true);

    try {
      _summary = await _db.getFeesBalanceSummary(
        term: _term!,
        session: _session!,
        classId: _selectedClassId,
      );
      _balancedStudents = await _db.getBalancedStudentsList(
        classId: _selectedClassId,
        term: _term!,
        session: _session!,
      );

      // Term-over-term comparison (e.g. 2nd Term vs 1st Term of the same session,
      // or 1st Term vs 3rd Term of the prior session)
      final prevTerm = DatabaseHelperWrapper.previousTermSession(
        term: _term!,
        session: _session!,
      );
      if (prevTerm != null) {
        _prevTermSummary = await _db.getFeesBalanceSummary(
          term: prevTerm['term']!,
          session: prevTerm['session']!,
          classId: _selectedClassId,
        );
        _prevTermLabel = '${prevTerm['term']} · ${prevTerm['session']}';
      } else {
        _prevTermSummary = null;
        _prevTermLabel = null;
      }

      // Session-over-session comparison (same term, previous session)
      final sessionParts = _session!.split('/');
      if (sessionParts.length == 2) {
        final startYear = int.tryParse(sessionParts[0].trim());
        if (startYear != null) {
          final prevSession = '${startYear - 1}/$startYear';
          _prevSessionSummary = await _db.getFeesBalanceSummary(
            term: _term!,
            session: prevSession,
            classId: _selectedClassId,
          );
          _prevSessionLabel = '$_term · $prevSession';
        } else {
          _prevSessionSummary = null;
          _prevSessionLabel = null;
        }
      }

      setState(() => _generating = false);
    } catch (e) {
      setState(() => _generating = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String _getSelectedClassName() {
    if (_selectedClassId == 0) return 'All Classes';
    final classData = _classes.firstWhere(
      (c) => c['id'] == _selectedClassId,
      orElse: () => {'name': ''},
    );
    return classData['name'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Fees Balance Report'),
        actions: [
          if (_generating)
            Padding(
              padding: EdgeInsets.all(ds.cardPadding),
              child: SizedBox(
                width: ds.iconSize,
                height: ds.iconSize,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
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
                  SizedBox(height: ds.cardPadding),
                  if (_summary != null) ...[
                    _buildStatisticsCard(ds),
                    SizedBox(height: ds.cardPadding),
                    if (_prevTermSummary != null) ...[
                      _buildComparisonCard(
                        ds,
                        title: 'This Term vs Last Term',
                        currentLabel: '$_term · $_session',
                        previousLabel: _prevTermLabel!,
                        current: _summary!,
                        previous: _prevTermSummary!,
                        expanded: _termCompExpanded,
                        onExpansionChanged: (v) => setState(() => _termCompExpanded = v),
                      ),
                      SizedBox(height: ds.cardPadding),
                    ],
                    if (_prevSessionSummary != null) ...[
                      _buildComparisonCard(
                        ds,
                        title: 'This Session vs Last Session',
                        currentLabel: '$_term · $_session',
                        previousLabel: _prevSessionLabel!,
                        current: _summary!,
                        previous: _prevSessionSummary!,
                        expanded: _sessionCompExpanded,
                        onExpansionChanged: (v) => setState(() => _sessionCompExpanded = v),
                      ),
                      SizedBox(height: ds.cardPadding),
                    ],
                    _buildBalancedTable(ds),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPeriodCard(DisplaySettings ds) {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.blue[700], size: ds.iconSize),
                SizedBox(width: ds.cardPadding * 0.5),
                Text(
                  'Current Period',
                  style: TextStyle(fontSize: ds.titleFontSize, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: ds.cardPadding * 0.5),
            Text('Term: $_term', style: TextStyle(fontSize: ds.bodyFontSize)),
            Text('Session: $_session', style: TextStyle(fontSize: ds.bodyFontSize)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCard(DisplaySettings ds) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filter Options',
              style: TextStyle(fontSize: ds.titleFontSize, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ds.cardPadding),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Select Class',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.school),
              ),
              initialValue: _selectedClassId,
              items: [
                const DropdownMenuItem<int>(value: 0, child: Text('All Classes')),
                ..._classes.map((c) => DropdownMenuItem<int>(
                      value: c['id'],
                      child: Text(c['name']),
                    )),
              ],
              onChanged: (v) {
                setState(() => _selectedClassId = v ?? 0);
              },
            ),
            SizedBox(height: ds.cardPadding),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generating ? null : _generateReport,
                icon: const Icon(Icons.search),
                label: const Text('Generate Report'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard(DisplaySettings ds) {
    final summary = _summary!;
    final totalBilled = summary['totalBilledStudents'] as int;
    final balanced = summary['totalBalanced'] as int;
    final owing = summary['totalOwing'] as int;
    final percentBalanced = (summary['percentBalanced'] as num).toDouble();
    final totalBills = (summary['totalBills'] as num).toDouble();
    final totalPaid = (summary['totalPaid'] as num).toDouble();
    final totalOutstanding = (summary['totalOutstanding'] as num).toDouble();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _statsExpanded,
        onExpansionChanged: (v) => setState(() => _statsExpanded = v),
        title: Text(
          'Statistics — ${_getSelectedClassName()}',
          style: TextStyle(fontSize: ds.titleFontSize, fontWeight: FontWeight.bold),
        ),
        subtitle: Text('$totalBilled billed', style: TextStyle(color: Colors.grey[600])),
        childrenPadding: EdgeInsets.fromLTRB(
          ds.cardPadding, 0, ds.cardPadding, ds.cardPadding,
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statTile('Balanced', '$balanced', Icons.check_circle, Colors.green),
              _statTile('Owing', '$owing', Icons.warning_amber, Colors.red),
              _statTile('% Balanced', '${percentBalanced.toStringAsFixed(1)}%', Icons.pie_chart, Colors.blue),
            ],
          ),
          SizedBox(height: ds.cardPadding),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: totalBilled > 0 ? balanced / totalBilled : 0,
              minHeight: 10,
              backgroundColor: Colors.red[100],
              valueColor: const AlwaysStoppedAnimation(Colors.green),
            ),
          ),
          SizedBox(height: ds.cardPadding),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryAmount('Total Bills', totalBills, Colors.blue),
              _summaryAmount('Total Paid', totalPaid, Colors.green),
              _summaryAmount('Outstanding', totalOutstanding, Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  Widget _summaryAmount(String label, double amount, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        const SizedBox(height: 4),
        Text(
          _money.format(amount),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildComparisonCard(
    DisplaySettings ds, {
    required String title,
    required String currentLabel,
    required String previousLabel,
    required Map<String, dynamic> current,
    required Map<String, dynamic> previous,
    required bool expanded,
    required ValueChanged<bool> onExpansionChanged,
  }) {
    final curPercent = (current['percentBalanced'] as num).toDouble();
    final prevPercent = (previous['percentBalanced'] as num).toDouble();
    final deltaPoints = curPercent - prevPercent;
    final improved = deltaPoints >= 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        title: Text(title, style: TextStyle(fontSize: ds.titleFontSize, fontWeight: FontWeight.bold)),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (improved ? Colors.green : Colors.red).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    improved ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    color: improved ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${deltaPoints.abs().toStringAsFixed(1)} pts',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: improved ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        childrenPadding: EdgeInsets.fromLTRB(
          ds.cardPadding, 0, ds.cardPadding, ds.cardPadding,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: _periodColumn(
                  label: currentLabel,
                  summary: current,
                  highlight: true,
                ),
              ),
              Container(width: 1, height: 60, color: Colors.grey[300]),
              Expanded(
                child: _periodColumn(
                  label: previousLabel,
                  summary: previous,
                  highlight: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _periodColumn({
    required String label,
    required Map<String, dynamic> summary,
    required bool highlight,
  }) {
    final balanced = summary['totalBalanced'] as int;
    final owing = summary['totalOwing'] as int;
    final percent = (summary['percentBalanced'] as num).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${percent.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: highlight ? Theme.of(context).primaryColor : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Balanced: $balanced  ·  Owing: $owing',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildBalancedTable(DisplaySettings ds) {
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
                  'Balanced Students (${_balancedStudents.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(_getSelectedClassName(), style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              ],
            ),
            SizedBox(height: ds.cardPadding),
            if (_balancedStudents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No students have fully balanced their fees for this period yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
                  columns: const [
                    DataColumn(label: Text('S/N', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Class/Arm', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Total Bill', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Amount Paid', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Credit', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _balancedStudents.asMap().entries.map((entry) {
                    final index = entry.key;
                    final s = entry.value;
                    final totalBill = (s['totalBill'] as num).toDouble();
                    final totalPaid = (s['totalPaid'] as num).toDouble();
                    final credit = (s['credit'] as num).toDouble();

                    return DataRow(
                      cells: [
                        DataCell(Text('${index + 1}')),
                        DataCell(Text(
                          '${s['surname']} ${s['firstName']}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        )),
                        DataCell(Text(
                          '${s['className'] ?? ''}${s['armName'] != null && s['armName'] != '' ? ' - ${s['armName']}' : ''}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        )),
                        DataCell(Text(_money.format(totalBill))),
                        DataCell(Text(_money.format(totalPaid), style: const TextStyle(color: Colors.green))),
                        DataCell(Text(
                          credit > 0.005 ? _money.format(credit) : '-',
                          style: TextStyle(color: credit > 0.005 ? Colors.blue : Colors.grey),
                        )),
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
