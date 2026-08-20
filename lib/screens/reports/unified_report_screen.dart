// lib/screens/reports/unified_report_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/school_sync_registry.dart';
import '../../utils/multi_school_report_coordinator.dart';
import '../../utils/report_data/daily_custom_report_loader.dart';
import '../../utils/report_data/termly_report_loader.dart';

/// Side-by-side Daily/Custom/Termly Report data for every linked school on
/// a Read-Only device. Viewing only (no PDF/print export in v1) — full
/// detail for a single school is still one tap away via the existing
/// single-school report screens after switching that school active.
class UnifiedReportScreen extends StatefulWidget {
  const UnifiedReportScreen({super.key});

  @override
  State<UnifiedReportScreen> createState() => _UnifiedReportScreenState();
}

class _UnifiedReportScreenState extends State<UnifiedReportScreen>
    with TickerProviderStateMixin {
  static const List<String> _reportTabLabels = [
    'Full Report',
    'Income & Expenses',
    'Expenses Only',
    'School Fees Only',
    'Fees + Income/Expenses',
    'Stock & Sales Only',
  ];

  bool _showIncome(int t) => t == 0 || t == 1 || t == 4;
  bool _showPayments(int t) => t == 0 || t == 3 || t == 4;
  bool _showExpenses(int t) => t == 0 || t == 1 || t == 2 || t == 4;
  bool _showStockSales(int t) => t == 0 || t == 5;

  late final TabController _outerTabController;
  List<LinkedSchool> _schools = [];

  // Daily
  DateTime _dailyDate = DateTime.now();
  int _dailyReportTab = 0;
  List<SchoolReportOutcome<DailyCustomReportData>>? _dailyResults;
  bool _dailyLoading = false;

  // Custom
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 6));
  DateTime _customEnd = DateTime.now();
  int _customReportTab = 0;
  List<SchoolReportOutcome<DailyCustomReportData>>? _customResults;
  bool _customLoading = false;
  bool _customEverLoaded = false;

  // Termly
  List<SchoolReportOutcome<TermlyReportData>>? _termlyResults;
  bool _termlyLoading = false;
  bool _termlyEverLoaded = false;

  bool get _currentTabLoading {
    switch (_outerTabController.index) {
      case 0:
        return _dailyLoading;
      case 1:
        return _customLoading;
      default:
        return _termlyLoading;
    }
  }

  @override
  void initState() {
    super.initState();
    _outerTabController = TabController(length: 3, vsync: this);
    _outerTabController.addListener(_onOuterTabChanged);
    _init();
  }

  @override
  void dispose() {
    _outerTabController.removeListener(_onOuterTabChanged);
    _outerTabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final schools = await SchoolSyncRegistry.getAll();
    if (!mounted) return;
    setState(() => _schools = schools);
    await _loadDaily();
  }

  void _onOuterTabChanged() {
    if (_outerTabController.indexIsChanging) return;
    // Lazy-load Custom/Termly the first time their tab is actually visited —
    // avoids paying for 3x the sequential per-school cost up front.
    if (_outerTabController.index == 1 && !_customEverLoaded) {
      _loadCustom();
    } else if (_outerTabController.index == 2 && !_termlyEverLoaded) {
      _loadTermly();
    }
  }

  Future<void> _loadDaily() async {
    setState(() => _dailyLoading = true);
    final results = await loadAcrossLinkedSchools(
      () => loadDailyCustomReportData(startDate: _dailyDate, endDate: _dailyDate),
      schoolsOverride: _schools,
    );
    if (!mounted) return;
    setState(() {
      _dailyResults = results;
      _dailyLoading = false;
    });
  }

  Future<void> _loadCustom() async {
    _customEverLoaded = true;
    setState(() => _customLoading = true);
    final results = await loadAcrossLinkedSchools(
      () => loadDailyCustomReportData(startDate: _customStart, endDate: _customEnd),
      schoolsOverride: _schools,
    );
    if (!mounted) return;
    setState(() {
      _customResults = results;
      _customLoading = false;
    });
  }

  Future<void> _loadTermly() async {
    _termlyEverLoaded = true;
    setState(() => _termlyLoading = true);
    final results = await loadAcrossLinkedSchools(
      () => loadTermlyReportData(),
      schoolsOverride: _schools,
    );
    if (!mounted) return;
    setState(() {
      _termlyResults = results;
      _termlyLoading = false;
    });
  }

  Future<void> _refreshCurrentTab() async {
    switch (_outerTabController.index) {
      case 0:
        await _loadDaily();
        break;
      case 1:
        await _loadCustom();
        break;
      default:
        await _loadTermly();
    }
  }

  Future<void> _pickDailyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dailyDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dailyDate = picked);
      _loadDaily();
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _customStart, end: _customEnd),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
      });
      _loadCustom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unified Report'),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _outerTabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Custom'),
            Tab(text: 'Termly'),
          ],
        ),
        actions: [
          _currentTabLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: _refreshCurrentTab,
                ),
        ],
      ),
      body: _schools.length <= 1
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Link more than one school to use Unified Report.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : TabBarView(
              controller: _outerTabController,
              children: [
                _buildDailyOrCustomPage(
                  isDaily: true,
                  results: _dailyResults,
                  loading: _dailyLoading,
                  reportTab: _dailyReportTab,
                  onReportTabChanged: (t) => setState(() => _dailyReportTab = t),
                  dateLabel: DateFormat('EEE, MMM d, yyyy').format(_dailyDate),
                  onPickDate: _pickDailyDate,
                ),
                _buildDailyOrCustomPage(
                  isDaily: false,
                  results: _customResults,
                  loading: _customLoading,
                  reportTab: _customReportTab,
                  onReportTabChanged: (t) => setState(() => _customReportTab = t),
                  dateLabel:
                      '${DateFormat('MMM d, yyyy').format(_customStart)} – ${DateFormat('MMM d, yyyy').format(_customEnd)}',
                  onPickDate: _pickCustomRange,
                ),
                _buildTermlyPage(),
              ],
            ),
    );
  }

  Widget _buildDailyOrCustomPage({
    required bool isDaily,
    required List<SchoolReportOutcome<DailyCustomReportData>>? results,
    required bool loading,
    required int reportTab,
    required ValueChanged<int> onReportTabChanged,
    required String dateLabel,
    required VoidCallback onPickDate,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(dateLabel),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _reportTabLabels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => ChoiceChip(
                label: Text(_reportTabLabels[i], style: const TextStyle(fontSize: 12)),
                selected: reportTab == i,
                onSelected: (_) => onReportTabChanged(i),
              ),
            ),
          ),
        ),
        Expanded(
          child: results == null && loading
              ? const Center(child: CircularProgressIndicator())
              : results == null
                  ? const SizedBox.shrink()
                  : Stack(
                      children: [
                        ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final outcome = results[i];
                            return outcome.success
                                ? _buildDailyCustomCard(outcome.school, outcome.data!, reportTab)
                                : _buildErrorCard(outcome.school, outcome.error!);
                          },
                        ),
                        if (loading)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildTermlyPage() {
    return _termlyResults == null && _termlyLoading
        ? const Center(child: CircularProgressIndicator())
        : _termlyResults == null
            ? const SizedBox.shrink()
            : Stack(
                children: [
                  ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _termlyResults!.length,
                    itemBuilder: (context, i) {
                      final outcome = _termlyResults![i];
                      return outcome.success
                          ? _buildTermlyCard(outcome.school, outcome.data!)
                          : _buildErrorCard(outcome.school, outcome.error!);
                    },
                  ),
                  if (_termlyLoading)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              );
  }

  Widget _cardHeader(LinkedSchool school, {String? term, String? session}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            school.displayLabel,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        if (term != null && term.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              session != null && session.isNotEmpty ? '$term · $session' : term,
              style: TextStyle(fontSize: 11, color: Colors.indigo.shade700),
            ),
          ),
      ],
    );
  }

  Widget _lastSyncedLine(String? lastSyncedAt) {
    if (lastSyncedAt == null) return const SizedBox.shrink();
    final dt = DateTime.tryParse(lastSyncedAt);
    final label = dt == null ? lastSyncedAt : DateFormat('MMM d, h:mm a').format(dt);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text('Last synced: $label', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
    );
  }

  /// Top-3 buckets by amount — the density lever for showing several
  /// schools' worth of detail on one page instead of full transaction
  /// tables. Full detail is still one tap away via the single-school
  /// report screens after switching that school active.
  List<MapEntry<String, double>> _topN(Map<String, double> totals, int n) {
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }

  Map<String, double> _paymentForTotals(List<Map<String, dynamic>> paymentDetails) {
    final totals = <String, double>{};
    for (final p in paymentDetails) {
      final key = p['paymentFor']?.toString() ?? 'School Fees';
      final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
      totals[key] = (totals[key] ?? 0) + amount;
    }
    return totals;
  }

  String _naira(double v) => '₦${v.toStringAsFixed(2)}';

  Widget _buildDailyCustomCard(LinkedSchool school, DailyCustomReportData d, int reportTab) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(school, term: d.activeTerm, session: d.activeSession),
            const SizedBox(height: 8),
            if (_showIncome(reportTab)) ...[
              Text(
                'Income: Cash ${_naira(d.cashTotal)}  ·  POS ${_naira(d.posTotal)}  ·  '
                'Transfer ${_naira(d.transferTotal)}  ·  Total ${_naira(d.totalIncome)}',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 4),
            ],
            if (_showPayments(reportTab)) ...[
              Text('${d.paymentDetails.length} payment(s)', style: const TextStyle(fontSize: 12.5)),
              for (final e in _topN(_paymentForTotals(d.paymentDetails), 3))
                Text('  • ${e.key}: ${_naira(e.value)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
            ],
            if (_showExpenses(reportTab)) ...[
              Text(
                'Expenses: Cash ${_naira(d.expenseCashTotal)}  ·  POS ${_naira(d.expensePosTotal)}  ·  '
                'Transfer ${_naira(d.expenseTransferTotal)}  ·  Total ${_naira(d.totalExpenses)}',
                style: const TextStyle(fontSize: 12.5),
              ),
              for (final e in _topN(d.expenseCategoryTotals, 3))
                Text('  • ${e.key}: ${_naira(e.value)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
            ],
            if (_showStockSales(reportTab)) ...[
              Text(
                'Stock & Sales: Total Sales ${_naira(d.totalSales)}  ·  '
                '${d.salesDebtors.length} debtor(s)  ·  ${_naira(d.totalSalesDebt)} owed',
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
            _lastSyncedLine(school.lastSyncedAt),
          ],
        ),
      ),
    );
  }

  Widget _buildTermlyCard(LinkedSchool school, TermlyReportData d) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(school, term: d.activeTerm, session: d.activeSession),
            const SizedBox(height: 8),
            Text(
              'Net Income: ${_naira(d.netIncome)}  (Income ${_naira(d.totalIncome)} − '
              'Expenses ${_naira(d.totalExpenses)})',
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Debtors: ${d.totalDebtors} of ${d.totalStudents} students, '
              '${_naira(d.totalOutstanding)} outstanding',
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            Text('New Intake: ${d.totalNewIntake} student(s)', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(
              'Printing (all-time, not term-scoped): ${d.totalPrints} total prints',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 4),
            Text(
              'Stock & Sales: ${_naira(d.totalSales)} sales  ·  ${_naira(d.totalSalesDebt)} debt',
              style: const TextStyle(fontSize: 12.5),
            ),
            _lastSyncedLine(school.lastSyncedAt),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(LinkedSchool school, Object error) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(school.displayLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Could not load: $error',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
