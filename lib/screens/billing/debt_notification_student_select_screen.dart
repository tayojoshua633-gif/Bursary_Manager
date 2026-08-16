// lib/screens/billing/debt_notification_student_select_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import 'debt_notification_screen.dart';

class DebtNotificationStudentSelectScreen extends StatefulWidget {
  const DebtNotificationStudentSelectScreen({super.key});

  @override
  State<DebtNotificationStudentSelectScreen> createState() =>
      _DebtNotificationStudentSelectScreenState();
}

class _DebtNotificationStudentSelectScreenState
    extends State<DebtNotificationStudentSelectScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _currency = NumberFormat('#,##0.00');
  final _searchController = TextEditingController();

  bool _loading = true;
  String _term = '';
  String _session = '';
  Map<String, dynamic>? _school;

  List<Map<String, dynamic>> _classes = [];
  int? _selectedClassId; // null = all classes

  List<Map<String, dynamic>> _allDebtors = [];
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _term = await _db.getActiveTerm();
    final sessionData = await _db.getActiveSession();
    _session = sessionData?['sessionName'] ?? '';
    _school = await _db.getSchoolProfile();
    _classes = await _db.getClasses();

    await _fetchDebtors();
  }

  Future<void> _fetchDebtors() async {
    setState(() => _loading = true);

    final List<Map<String, dynamic>> debtors = [];

    final classesToQuery = _selectedClassId == null
        ? _classes
        : _classes.where((c) => c['id'] == _selectedClassId).toList();

    for (final cls in classesToQuery) {
      final rows = await _db.getDebtorsList(
        classId: cls['id'] as int,
        term: _term,
        session: _session,
        minPercentagePaid: 0,
      );
      debtors.addAll(rows);
    }

    // Sort by class then name
    debtors.sort((a, b) {
      final classCompare =
          (a['className'] ?? '').toString().compareTo((b['className'] ?? '').toString());
      if (classCompare != 0) return classCompare;
      return '${a['surname']} ${a['firstName']}'
          .compareTo('${b['surname']} ${b['firstName']}');
    });

    _allDebtors = debtors;
    _applySearch();

    if (mounted) setState(() => _loading = false);
  }

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filtered = List.of(_allDebtors);
    } else {
      _filtered = _allDebtors.where((d) {
        final name =
            '${d['surname']} ${d['firstName']} ${d['otherName'] ?? ''}'
                .toLowerCase();
        final admNo = (d['admissionNo'] ?? '').toString().toLowerCase();
        final cls = '${d['className']} ${d['armName'] ?? ''}'.toLowerCase();
        return name.contains(query) ||
            admNo.contains(query) ||
            cls.contains(query);
      }).toList();
    }
  }

  void _openNotificationScreen(Map<String, dynamic> debtor) {
    final firstName = debtor['firstName']?.toString() ?? '';
    final surname = debtor['surname']?.toString() ?? '';
    final otherName = debtor['otherName']?.toString() ?? '';
    final fullName =
        [surname, firstName, if (otherName.isNotEmpty) otherName].join(' ');
    final className =
        '${debtor['className'] ?? ''} ${debtor['armName'] ?? ''}'.trim();

    final currentTermFee = (debtor['currentTermFee'] as num).toDouble();
    final prevBal = (debtor['freshPreviousBalance'] as num).toDouble();
    final totalBills = currentTermFee + prevBal;
    final totalPaid = (debtor['totalPaid'] as num).toDouble();
    final outstanding = totalBills - totalPaid;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DebtNotificationScreen(
          schoolProfile: _school ?? {},
          studentName: fullName,
          admissionNo: debtor['admissionNo']?.toString() ?? '',
          className: className,
          term: _term,
          session: _session,
          totalBills: totalBills,
          totalPaid: totalPaid,
          outstanding: outstanding,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debt Notification'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Header bar ───────────────────────────────────────────
          Container(
            color: Colors.red.shade50,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                // Term / session chip
                Row(
                  children: [
                    const Icon(Icons.calendar_month,
                        size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Text(
                      '$_term  •  $_session',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Class filter
                DropdownButtonFormField<int?>(
                  key: ValueKey(_selectedClassId),
                  initialValue: _selectedClassId,
                  decoration: InputDecoration(
                    labelText: 'Filter by Class',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Classes')),
                    ..._classes.map((c) => DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text(c['name'] as String),
                        )),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedClassId = val);
                    _fetchDebtors();
                  },
                ),
                const SizedBox(height: 8),

                // Search box
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, admission no. or class…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(_applySearch);
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(_applySearch),
                ),
              ],
            ),
          ),

          // ── Student list ─────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 64,
                                color: Colors.green.shade300),
                            const SizedBox(height: 12),
                            Text(
                              _allDebtors.isEmpty
                                  ? 'No outstanding balances found'
                                  : 'No students match your search',
                              style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // Count banner
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                16, 10, 16, 4),
                            child: Row(
                              children: [
                                Text(
                                  '${_filtered.length} student${_filtered.length == 1 ? '' : 's'} with outstanding balance',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, i) =>
                                  _debtorCard(_filtered[i]),
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _debtorCard(Map<String, dynamic> debtor) {
    final firstName = debtor['firstName']?.toString() ?? '';
    final surname = debtor['surname']?.toString() ?? '';
    final className =
        '${debtor['className'] ?? ''} ${debtor['armName'] ?? ''}'.trim();
    final admNo = debtor['admissionNo']?.toString() ?? '';

    final currentTermFee = (debtor['currentTermFee'] as num).toDouble();
    final prevBal = (debtor['freshPreviousBalance'] as num).toDouble();
    final totalBills = currentTermFee + prevBal;
    final totalPaid = (debtor['totalPaid'] as num).toDouble();
    final outstanding = totalBills - totalPaid;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openNotificationScreen(debtor),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.red.shade100,
                child: Text(
                  surname.isNotEmpty ? surname[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),

              // Name + class
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$surname $firstName',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$className  ·  $admNo',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),

              // Outstanding amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'N${_currency.format(outstanding)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  Text(
                    'outstanding',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),

              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios,
                  size: 14, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
