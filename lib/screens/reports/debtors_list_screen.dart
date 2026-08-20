// lib/screens/reports/debtors_list_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/debtors_pdf_generator.dart';
import '../../utils/debtors_excel_generator.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';
import 'package:share_plus/share_plus.dart';

class DebtorsListScreen extends StatefulWidget {
  const DebtorsListScreen({super.key});

  @override
  State<DebtorsListScreen> createState() => _DebtorsListScreenState();
}

class _DebtorsListScreenState extends State<DebtorsListScreen> {
  static const List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];

  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  bool _loading = true;
  bool _exporting = false;
  String? _term;
  String? _session;
  List<Map<String, dynamic>> _sessions = [];

  List<Map<String, dynamic>> _classes = [];
  int? _selectedClassId;

  // Filter options
  String _filterType = 'all'; // 'all' or 'percentage'
  double _minPercentage = 50.0; // Default 50%

  List<Map<String, dynamic>> _debtors = [];
  Map<int, String?> _parentPhoneByStudentId = {};
  Set<String> _siblingPhones = {};

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
      _debtors = [];
    });
  }

  void _onSessionChanged(String? session) {
    setState(() {
      _session = session;
      _debtors = [];
    });
  }

  Future<void> _generateDebtorsList() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class first')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final minPercentage = _filterType == 'percentage' ? _minPercentage : 0.0;

      // If "All Classes" (classId = 0) is selected, fetch debtors for all classes
      if (_selectedClassId == 0) {
        _debtors = [];
        for (final classData in _classes) {
          final classDebtors = await _db.getDebtorsList(
            classId: classData['id'],
            term: _term!,
            session: _session!,
            minPercentagePaid: minPercentage,
          );
          _debtors.addAll(classDebtors);
        }

        // Sort by class name, then by student name
        _debtors.sort((a, b) {
          final classCompare = (a['className'] ?? '').toString().compareTo((b['className'] ?? '').toString());
          if (classCompare != 0) return classCompare;
          return (a['studentName'] ?? '').toString().compareTo((b['studentName'] ?? '').toString());
        });
      } else {
        _debtors = await _db.getDebtorsList(
          classId: _selectedClassId!,
          term: _term!,
          session: _session!,
          minPercentagePaid: minPercentage,
        );
      }

      final activeStudents = await _db.getActiveStudents();
      _parentPhoneByStudentId = {
        for (final s in activeStudents) s['id'] as int: s['parentPhone'] as String?,
      };
      _siblingPhones = computeSiblingPhones(activeStudents);

      setState(() => _loading = false);

      if (_debtors.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No debtors found for the selected criteria'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String _getSelectedClassName() {
    if (_selectedClassId == null) return '';
    if (_selectedClassId == 0) return 'All Classes';
    final classData = _classes.firstWhere(
      (c) => c['id'] == _selectedClassId,
      orElse: () => {'name': ''},
    );
    return classData['name'] ?? '';
  }

  // ================================
  // EXPORT FUNCTIONS
  // ================================

  Future<void> _exportAsPDF() async {
    if (_debtors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No debtors to export')),
      );
      return;
    }

    setState(() => _exporting = true);

    try {
      final schoolProfile = await _db.getSchoolProfile();
      final className = _getSelectedClassName();

      final filePath = await DebtorsPDFGenerator.generateDebtorsPDF(
        debtors: _debtors,
        className: className,
        term: _term ?? '',
        session: _session ?? '',
        schoolProfile: schoolProfile ?? {},
        filterType: _filterType,
        minPercentage: _minPercentage,
      );

      setState(() => _exporting = false);

      if (!mounted) return;

      // Show share dialog
      _showShareDialog(filePath, 'PDF');
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportAsExcel() async {
    if (_debtors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No debtors to export')),
      );
      return;
    }

    setState(() => _exporting = true);

    try {
      final schoolProfile = await _db.getSchoolProfile();
      final className = _getSelectedClassName();

      final filePath = await DebtorsExcelGenerator.generateDebtorsExcel(
        debtors: _debtors,
        className: className,
        term: _term ?? '',
        session: _session ?? '',
        schoolProfile: schoolProfile ?? {},
        filterType: _filterType,
        minPercentage: _minPercentage,
      );

      setState(() => _exporting = false);

      if (!mounted) return;

      // Show share dialog
      _showShareDialog(filePath, 'Excel');
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showShareDialog(String filePath, String fileType) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              fileType == 'PDF' ? Icons.picture_as_pdf : Icons.table_chart,
              color: fileType == 'PDF' ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Text('$fileType Exported'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Debtors list exported successfully as $fileType!',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'File saved to device',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
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
              final scaffoldContext = context; // Capture context before async
              Navigator.pop(dialogContext);
              if (!mounted) return;
              try {
                await Share.shareXFiles(
                  [XFile(filePath)],
                  subject: 'Debtors List - ${_getSelectedClassName()}',
                  text: 'Debtors list for $_term $_session',
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

  void _showExportMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Export Debtors List',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Export as PDF'),
              subtitle: const Text('Create PDF document'),
              onTap: () {
                Navigator.pop(context);
                _exportAsPDF();
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.green),
              title: const Text('Export as Excel'),
              subtitle: const Text('Create Excel spreadsheet'),
              onTap: () {
                Navigator.pop(context);
                _exportAsExcel();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debtors List'),
        actions: [
          if (_debtors.isNotEmpty && !_exporting)
            IconButton(
              icon: Icon(Icons.download, size: ds.iconSize),
              tooltip: 'Export',
              onPressed: _showExportMenu,
            ),
          if (_exporting)
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
                  // Term & Session Filter
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

                  // Filters Card
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(ds.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filter Options',
                            style: TextStyle(
                              fontSize: ds.titleFontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: ds.cardPadding),

                          // Class Selector
                          DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              labelText: 'Select Class',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.school),
                            ),
                            initialValue: _selectedClassId,
                            items: [
                              // Add "All Classes" option first
                              const DropdownMenuItem<int>(
                                value: 0,
                                child: Text('All Classes'),
                              ),
                              // Then add all individual classes
                              ..._classes
                                  .map((c) => DropdownMenuItem<int>(
                                        value: c['id'],
                                        child: Text(c['name']),
                                      )),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _selectedClassId = v;
                                _debtors = []; // Clear previous results
                              });
                            },
                          ),

                          const SizedBox(height: 16),

                          // Filter Type - Using custom radio buttons
                          const Text(
                            'Debtors Filter:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          
                          // Option 1: All debtors
                          _buildCustomRadioOption(
                            value: 'all',
                            title: 'All debtors (any unpaid amount)',
                            subtitle: 'Show students with any outstanding balance',
                          ),
                          
                          const SizedBox(height: 8),
                          
                          // Option 2: Below threshold
                          _buildCustomRadioOption(
                            value: 'percentage',
                            title: 'Debtors below payment threshold',
                            subtitle: 'Show students who paid less than $_minPercentage%',
                          ),

                          // Percentage Slider (only show if percentage filter is selected)
                          if (_filterType == 'percentage') ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange[200]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Minimum Payment Threshold: ${_minPercentage.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Slider(
                                    value: _minPercentage,
                                    min: 0,
                                    max: 100,
                                    divisions: 20,
                                    label: '${_minPercentage.toStringAsFixed(0)}%',
                                    onChanged: (v) {
                                      setState(() => _minPercentage = v);
                                    },
                                  ),
                                  Text(
                                    'Show students who have paid less than ${_minPercentage.toStringAsFixed(0)}% of their bill',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // Generate Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _generateDebtorsList,
                              icon: const Icon(Icons.search),
                              label: const Text('Generate Debtors List'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Results
                  if (_debtors.isNotEmpty) ...[
                    // Export Buttons
                    Card(
                      color: Colors.green[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _exporting ? null : _exportAsPDF,
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                                label: const Text('Export PDF'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _exporting ? null : _exportAsExcel,
                                icon: const Icon(Icons.table_chart, color: Colors.green),
                                label: const Text('Export Excel'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Summary Card
                    _buildSummaryCard(),

                    const SizedBox(height: 16),

                    // Debtors Table
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Debtors (${_debtors.length})',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _getSelectedClassName(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildDebtorsTable(),
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

  Widget _buildCustomRadioOption({
    required String value,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _filterType == value;
    
    return InkWell(
      onTap: () {
        setState(() => _filterType = value);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected 
              ? Theme.of(context).primaryColor.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            // Custom radio circle
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected 
                      ? Theme.of(context).primaryColor 
                      : Colors.grey[400]!,
                  width: 2,
                ),
                color: Colors.white,
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isSelected 
                          ? Theme.of(context).primaryColor 
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    double totalBills = 0;
    double totalPaid = 0;
    double totalOutstanding = 0;

    for (var debtor in _debtors) {
      totalBills += (debtor['totalBill'] as num).toDouble();
      totalPaid += (debtor['totalPaid'] as num).toDouble();
      totalOutstanding += (debtor['outstanding'] as num).toDouble();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        children: [
          const Text(
            'Financial Summary',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryItem('Total Bills', totalBills, Colors.blue),
              _summaryItem('Total Paid', totalPaid, Colors.green),
              _summaryItem('Outstanding', totalOutstanding, Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          NumberFormat('#,##0.00').format(amount),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDebtorsTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
        columns: const [
          DataColumn(label: Text('S/N', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Class/Arm', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Total Bill', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Amount Paid', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Outstanding', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('% Paid', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _debtors.asMap().entries.map((entry) {
          final index = entry.key;
          final debtor = entry.value;
          
          final totalBill = (debtor['totalBill'] as num).toDouble();
          final totalPaid = (debtor['totalPaid'] as num).toDouble();
          final outstanding = (debtor['outstanding'] as num).toDouble();
          final percentPaid = (debtor['percentPaid'] as num).toDouble();

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${debtor['surname']} ${debtor['firstName']}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    SiblingMark(
                      show: isSiblingPhone(
                        _parentPhoneByStudentId[debtor['studentId'] as int?],
                        _siblingPhones,
                      ),
                    ),
                  ],
                ),
              ),
              DataCell(
                Text(
                  '${debtor['className'] ?? ''}${debtor['armName'] != null && debtor['armName'] != '' ? ' - ${debtor['armName']}' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              DataCell(Text(NumberFormat('#,##0.00').format(totalBill))),
              DataCell(
                Text(
                  NumberFormat('#,##0.00').format(totalPaid),
                  style: const TextStyle(color: Colors.green),
                ),
              ),
              DataCell(
                Text(
                  NumberFormat('#,##0.00').format(outstanding),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPercentageColor(percentPaid).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${percentPaid.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: _getPercentageColor(percentPaid),
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

  Color _getPercentageColor(double percentage) {
    if (percentage >= 80) return Colors.green;
    if (percentage >= 50) return Colors.orange;
    return Colors.red;
  }
}