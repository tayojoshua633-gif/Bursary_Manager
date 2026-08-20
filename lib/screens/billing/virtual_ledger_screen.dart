// lib/screens/billing/virtual_ledger_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../utils/virtual_ledger_pdf_generator.dart';
import '../../widgets/sibling_mark.dart';
import 'package:share_plus/share_plus.dart';

class VirtualLedgerScreen extends StatefulWidget {
  const VirtualLedgerScreen({super.key});

  @override
  State<VirtualLedgerScreen> createState() => _VirtualLedgerScreenState();
}

class _VirtualLedgerScreenState extends State<VirtualLedgerScreen> {
  static const List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];

  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  bool _loading = true;
  bool _generating = false;
  bool _exporting = false;

  String? _term;
  String? _session;
  List<Map<String, dynamic>> _sessions = [];

  List<Map<String, dynamic>> _classes = [];
  int _selectedClassId = 0; // 0 = All Classes

  List<Map<String, dynamic>> _ledger = [];
  int _maxInstalments = 0;
  Map<int, String?> _parentPhoneByStudentId = {};
  Set<String> _siblingPhones = {};

  static final _amountFormat = NumberFormat('#,##0.00');
  static final _dateFormat = DateFormat('dd/MM/yy');

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
    _sessions = await _db.getAllSessions();
    _classes = await _db.getClasses();

    setState(() => _loading = false);
  }

  void _onTermChanged(String? term) {
    setState(() {
      _term = term;
      _ledger = [];
    });
  }

  void _onSessionChanged(String? session) {
    setState(() {
      _session = session;
      _ledger = [];
    });
  }

  Future<void> _generateLedger() async {
    if (_term == null || _session == null || _term!.isEmpty || _session!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active term/session found')),
      );
      return;
    }

    setState(() => _generating = true);

    try {
      final db = await _db.database;

      final targetKey = DatabaseHelperWrapper.termSortKey(_term!, _session!);
      final b2Key = DatabaseHelperWrapper.sqlTermKeyExpr('b2');
      final p2Key = DatabaseHelperWrapper.sqlTermKeyExpr('p2');

      final String classFilter = _selectedClassId > 0 ? 'AND s.classId = ?' : '';
      final List<dynamic> studentParams = [
        targetKey, targetKey, // b2/p2 sort key for freshPreviousBalance
        _term, _session, // LEFT JOIN student_bills
      ];
      if (_selectedClassId > 0) studentParams.add(_selectedClassId);

      final studentRows = await db.rawQuery('''
        SELECT
          s.id as studentId,
          s.admissionNo,
          s.surname,
          s.firstName,
          s.otherName,
          s.classId,
          c.name as className,
          a.name as armName,
          (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0)) as currentTermFee,
          (
            COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                      WHERE b2.studentId = s.id AND $b2Key < ?), 0)
            -
            COALESCE((SELECT SUM(p2.amount) FROM payments p2
                      WHERE p2.studentId = s.id AND $p2Key < ?), 0)
          ) as freshPreviousBalance
        FROM students s
        INNER JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        LEFT JOIN student_bills b ON s.id = b.studentId
          AND b.term = ? AND b.session = ?
        WHERE s.isActive = 1
          $classFilter
        ORDER BY c.name, a.name, s.surname, s.firstName
      ''', studentParams);

      final paymentRows = await db.rawQuery('''
        SELECT studentId, amount, paymentDate
        FROM payments
        WHERE term = ? AND session = ?
        ORDER BY studentId, paymentDate ASC, id ASC
      ''', [_term, _session]);

      final Map<int, List<Map<String, dynamic>>> paymentsByStudent = {};
      for (final p in paymentRows) {
        final sid = p['studentId'] as int;
        paymentsByStudent.putIfAbsent(sid, () => []).add(p);
      }

      final ledger = <Map<String, dynamic>>[];
      int maxInstalments = 0;

      for (final row in studentRows) {
        final studentId = row['studentId'] as int;
        final currentTermFee = (row['currentTermFee'] as num).toDouble();
        final freshPreviousBalance = (row['freshPreviousBalance'] as num).toDouble();
        final totalBill = currentTermFee + freshPreviousBalance;

        final instalments = paymentsByStudent[studentId] ?? [];
        final totalPaid = instalments.fold<double>(
          0,
          (sum, p) => sum + (p['amount'] as num).toDouble(),
        );
        final outstanding = totalBill - totalPaid;

        if (instalments.length > maxInstalments) {
          maxInstalments = instalments.length;
        }

        ledger.add({
          'studentId': studentId,
          'admissionNo': row['admissionNo'],
          'surname': row['surname'],
          'firstName': row['firstName'],
          'otherName': row['otherName'],
          'className': row['className'],
          'armName': row['armName'],
          'totalBill': totalBill,
          'totalPaid': totalPaid,
          'outstanding': outstanding,
          'instalments': instalments,
          'remark': outstanding <= 0.005 ? 'Balanced' : 'Not Balanced',
        });
      }

      final activeStudents = await _db.getActiveStudents();
      _parentPhoneByStudentId = {
        for (final s in activeStudents) s['id'] as int: s['parentPhone'] as String?,
      };
      _siblingPhones = computeSiblingPhones(activeStudents);

      setState(() {
        _ledger = ledger;
        _maxInstalments = maxInstalments;
        _generating = false;
      });

      if (_ledger.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No students found for the selected class')),
        );
      }
    } catch (e) {
      setState(() => _generating = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _exportAsPDF() async {
    if (_ledger.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No ledger data to export')),
      );
      return;
    }

    setState(() => _exporting = true);

    try {
      final schoolProfile = await _db.getSchoolProfile();
      final className = _getSelectedClassName();

      final filePath = await VirtualLedgerPDFGenerator.generateVirtualLedgerPDF(
        ledger: _ledger,
        maxInstalments: _maxInstalments,
        className: className,
        term: _term ?? '',
        session: _session ?? '',
        schoolProfile: schoolProfile ?? {},
      );

      setState(() => _exporting = false);

      if (!mounted) return;
      _showShareDialog(filePath);
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showShareDialog(String filePath) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.red),
            SizedBox(width: 8),
            Text('PDF Exported'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Virtual Ledger exported successfully as PDF!',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'File saved to device',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final scaffoldContext = context;
              Navigator.pop(dialogContext);
              if (!mounted) return;
              try {
                await Share.shareXFiles(
                  [XFile(filePath)],
                  subject: 'Virtual Ledger - ${_getSelectedClassName()}',
                  text: 'Virtual Ledger for $_term $_session',
                );
              } catch (e) {
                if (!mounted) return;
                if (scaffoldContext.mounted) {
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    SnackBar(content: Text('Share failed: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ],
      ),
    );
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
        title: const Text('Virtual Ledger'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_ledger.isNotEmpty && !_exporting)
            IconButton(
              icon: Icon(Icons.download, size: ds.iconSize),
              tooltip: 'Export as PDF',
              onPressed: _exportAsPDF,
            ),
          if (_exporting)
            Padding(
              padding: EdgeInsets.all(ds.cardPadding),
              child: SizedBox(
                width: ds.iconSize,
                height: ds.iconSize,
                child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                  Card(
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
                                'Period',
                                style: TextStyle(
                                  fontSize: ds.titleFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: ds.cardPadding),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _session,
                                  decoration: const InputDecoration(
                                    labelText: 'Session',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _sessions
                                      .map((s) => s['sessionName'] as String)
                                      .toSet()
                                      .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                                      .toList(),
                                  onChanged: _onSessionChanged,
                                ),
                              ),
                              SizedBox(width: ds.cardPadding * 0.5),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _term,
                                  decoration: const InputDecoration(
                                    labelText: 'Term',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _terms
                                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                      .toList(),
                                  onChanged: _onTermChanged,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: ds.cardPadding),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(ds.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filter',
                            style: TextStyle(
                              fontSize: ds.titleFontSize,
                              fontWeight: FontWeight.bold,
                            ),
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
                              ..._classes.map(
                                (c) => DropdownMenuItem<int>(value: c['id'], child: Text(c['name'])),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _selectedClassId = v ?? 0;
                                _ledger = [];
                              });
                            },
                          ),
                          SizedBox(height: ds.cardPadding),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _generating ? null : _generateLedger,
                              icon: _generating
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.table_chart_outlined),
                              label: const Text('Generate Ledger'),
                              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_ledger.isNotEmpty) ...[
                    SizedBox(height: ds.cardPadding),
                    Card(
                      color: Colors.green[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _exporting ? null : _exportAsPDF,
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                            label: const Text('Export / Share as PDF'),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(12)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: ds.cardPadding),
                    _buildSummaryCard(),
                    SizedBox(height: ds.cardPadding),
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(ds.cardPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Ledger (${_ledger.length})',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _getSelectedClassName(),
                                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                            SizedBox(height: ds.cardPadding),
                            _buildLedgerTable(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard() {
    double totalBills = 0;
    double totalPaid = 0;
    int balancedCount = 0;

    for (final row in _ledger) {
      totalBills += (row['totalBill'] as num).toDouble();
      totalPaid += (row['totalPaid'] as num).toDouble();
      if (row['remark'] == 'Balanced') balancedCount++;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo[200]!),
      ),
      child: Column(
        children: [
          const Text('Ledger Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryItem('Total Bills', _amountFormat.format(totalBills), Colors.blue),
              _summaryItem('Total Paid', _amountFormat.format(totalPaid), Colors.green),
              _summaryItem('Balanced', '$balancedCount / ${_ledger.length}', Colors.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildLedgerTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
        columns: [
          const DataColumn(label: Text('S/N', style: TextStyle(fontWeight: FontWeight.bold))),
          const DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
          const DataColumn(label: Text('Class', style: TextStyle(fontWeight: FontWeight.bold))),
          const DataColumn(label: Text('Total Bills', style: TextStyle(fontWeight: FontWeight.bold))),
          for (int i = 1; i <= _maxInstalments; i++)
            DataColumn(label: Text('Payment $i', style: const TextStyle(fontWeight: FontWeight.bold))),
          const DataColumn(label: Text('Total Paid', style: TextStyle(fontWeight: FontWeight.bold))),
          const DataColumn(label: Text('Remark', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _ledger.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;

          final totalBill = (row['totalBill'] as num).toDouble();
          final totalPaid = (row['totalPaid'] as num).toDouble();
          final instalments = row['instalments'] as List<Map<String, dynamic>>;
          final remark = row['remark'] as String;
          final isBalanced = remark == 'Balanced';

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${row['surname']} ${row['firstName']}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    SiblingMark(
                      show: isSiblingPhone(
                        _parentPhoneByStudentId[row['studentId'] as int?],
                        _siblingPhones,
                      ),
                    ),
                  ],
                ),
              ),
              DataCell(
                Text(
                  '${row['className'] ?? ''}${row['armName'] != null && row['armName'] != '' ? ' - ${row['armName']}' : ''}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
              DataCell(Text(_amountFormat.format(totalBill))),
              for (int i = 0; i < _maxInstalments; i++)
                DataCell(
                  i < instalments.length
                      ? _buildInstalmentCell(instalments[i])
                      : Text('-', style: TextStyle(color: Colors.grey[400])),
                ),
              DataCell(
                Text(
                  _amountFormat.format(totalPaid),
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                ),
              ),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isBalanced ? Colors.green : Colors.red).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    remark,
                    style: TextStyle(
                      color: isBalanced ? Colors.green[700] : Colors.red[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInstalmentCell(Map<String, dynamic> payment) {
    final amount = (payment['amount'] as num).toDouble();
    final dateStr = payment['paymentDate'] as String?;
    String formattedDate = dateStr ?? '';
    if (dateStr != null) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) formattedDate = _dateFormat.format(parsed);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formattedDate,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        Text(_amountFormat.format(amount)),
      ],
    );
  }
}
