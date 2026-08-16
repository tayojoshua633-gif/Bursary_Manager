import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/student.dart';
import '../students/student_details_screen.dart';
import '../../utils/overpayment_tracker_pdf_generator.dart';

class OverpaymentTrackerScreen extends StatefulWidget {
  const OverpaymentTrackerScreen({super.key});

  @override
  State<OverpaymentTrackerScreen> createState() => _OverpaymentTrackerScreenState();
}

class _OverpaymentTrackerScreenState extends State<OverpaymentTrackerScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _overpayments = [];
  List<Map<String, dynamic>> _allOverpayments = [];
  List<Map<String, dynamic>> _classes = [];

  bool _loading = true;
  int? _selectedClassFilter; // null means "All Classes"

  String? activeTerm;
  String? activeSession;
  Map<String, dynamic>? school;

  @override
  void initState() {
    super.initState();
    _loadOverpayments();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOverpayments() async {
    if (mounted) setState(() => _loading = true);

    try {
      // Get current term and session
      activeTerm = await _db.getActiveTerm();
      final sessionData = await _db.getActiveSession();
      activeSession = sessionData?['sessionName'] ?? '';

      // Get school profile
      school = await _db.getSchoolProfile();

      // Get all classes for filter
      _classes = await _db.getClasses();

      // Validate term and session
      if (activeTerm == null || activeTerm!.isEmpty || activeSession == null || activeSession!.isEmpty) {
        debugPrint("No active term or session set");
        _allOverpayments = [];
        _overpayments = [];
        return;
      }

      // Query students with overpayments using fresh grand total
      // freshPrevBal = SUM(ALL chronologically prior fee charges) - SUM(ALL prior payments)
      final database = await _db.database;
      final targetKey = DatabaseHelperWrapper.termSortKey(activeTerm ?? '', activeSession ?? '');
      final b2Key = DatabaseHelperWrapper.sqlTermKeyExpr('b2');
      final p2Key = DatabaseHelperWrapper.sqlTermKeyExpr('p2');
      final overpaymentData = await database.rawQuery('''
        SELECT
          s.*,
          c.name AS className,
          a.name AS armName,
          (
            (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0))
            + (
                COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                          WHERE b2.studentId = s.id AND $b2Key < ?), 0)
                -
                COALESCE((SELECT SUM(p2.amount) FROM payments p2
                          WHERE p2.studentId = s.id AND $p2Key < ?), 0)
              )
          ) as billAmount,
          COALESCE(p.totalPaid, 0) as paidAmount,
          (
            COALESCE(p.totalPaid, 0)
            - (
                (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0))
                + (
                    COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                              WHERE b2.studentId = s.id AND $b2Key < ?), 0)
                    -
                    COALESCE((SELECT SUM(p2.amount) FROM payments p2
                              WHERE p2.studentId = s.id AND $p2Key < ?), 0)
                  )
              )
          ) as overpaid
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        LEFT JOIN student_bills b ON s.id = b.studentId
          AND b.term = ?
          AND b.session = ?
        LEFT JOIN (
          SELECT studentId, SUM(amount) as totalPaid
          FROM payments
          WHERE term = ? AND session = ?
          GROUP BY studentId
        ) p ON s.id = p.studentId
        WHERE s.isActive = 1
          AND (
            COALESCE(p.totalPaid, 0)
            - (
                (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0))
                + (
                    COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                              WHERE b2.studentId = s.id AND $b2Key < ?), 0)
                    -
                    COALESCE((SELECT SUM(p2.amount) FROM payments p2
                              WHERE p2.studentId = s.id AND $p2Key < ?), 0)
                  )
              )
          ) > 0
        ORDER BY overpaid DESC
      ''', [
        targetKey, targetKey,                                 // billAmount sort key filter
        targetKey, targetKey,                                 // overpaid SELECT sort key filter
        activeTerm, activeSession,                            // LEFT JOIN student_bills
        activeTerm, activeSession,                            // payments LEFT JOIN
        targetKey, targetKey,                                 // WHERE sort key filter
      ]);

      debugPrint("Loaded ${overpaymentData.length} students with overpayments");
      _allOverpayments = overpaymentData;
      _overpayments = overpaymentData;
    } catch (e, st) {
      debugPrint("Overpayment tracker load error: $e\n$st");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
      _allOverpayments = [];
      _overpayments = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    final keyword = _searchCtrl.text.trim();

    setState(() {
      List<Map<String, dynamic>> filtered = _allOverpayments;

      // Apply class filter
      if (_selectedClassFilter != null) {
        filtered = filtered.where((o) => o['classId'] == _selectedClassFilter).toList();
      }

      // Apply search keyword
      if (keyword.isNotEmpty) {
        final kw = keyword.toLowerCase();
        filtered = filtered.where((o) {
          final surname = (o['surname'] ?? '').toString().toLowerCase();
          final firstName = (o['firstName'] ?? '').toString().toLowerCase();
          final admissionNo = (o['admissionNo'] ?? '').toString().toLowerCase();
          final className = (o['className'] ?? '').toString().toLowerCase();
          final armName = (o['armName'] ?? '').toString().toLowerCase();

          return surname.contains(kw) ||
                 firstName.contains(kw) ||
                 admissionNo.contains(kw) ||
                 className.contains(kw) ||
                 armName.contains(kw);
        }).toList();
      }

      _overpayments = filtered;
    });
  }

  String _buildFilterInfoText() {
    if (_selectedClassFilter == null) {
      return "Showing ${_overpayments.length} of ${_allOverpayments.length} students with overpayments";
    }

    final selectedClass = _classes.firstWhere(
      (c) => c['id'] == _selectedClassFilter,
      orElse: () => {'name': 'Unknown'},
    );
    return "Showing ${_overpayments.length} students from ${selectedClass['name']}";
  }

  Future<void> _exportPDF() async {
    if (_overpayments.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No overpayments to export')),
      );
      return;
    }

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final filePath = await OverpaymentTrackerPDFGenerator.generateOverpaymentTrackerPDF(
        term: activeTerm ?? '',
        session: activeSession ?? '',
        schoolProfile: school ?? {},
        overpayments: _overpayments,
      );

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Overpayment Tracker - $activeTerm $activeSession',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Overpayment Tracker'),
            if (activeTerm != null && activeSession != null)
              Text(
                '$activeTerm - $activeSession',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOverpayments,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search students',
                      hintText: 'Name, Admission No, Class...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => _applyFilters(),
                  ),
                ),

                // Class filter
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              isExpanded: true,
                              value: _selectedClassFilter,
                              hint: const Text('Filter by Class'),
                              icon: const Icon(Icons.filter_list, size: 20),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text(
                                    'All Classes',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                ..._classes.map((c) => DropdownMenuItem<int?>(
                                      value: c['id'],
                                      child: Text(c['name']),
                                    )),
                              ],
                              onChanged: (val) {
                                setState(() => _selectedClassFilter = val);
                                _applyFilters();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Filter info text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    _buildFilterInfoText(),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

                // List of students with overpayments
                Expanded(
                  child: _overpayments.isEmpty
                      ? const Center(
                          child: Text(
                            'No students with overpayments found',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _overpayments.length,
                          itemBuilder: (context, index) {
                            try {
                              final item = _overpayments[index];
                              final surname = item['surname'] ?? '';
                              final firstName = item['firstName'] ?? '';
                              final admissionNo = item['admissionNo'] ?? '';
                              final className = item['className'] ?? 'N/A';
                              final armName = item['armName'] ?? 'N/A';
                              final billAmount = (item['billAmount'] as num?)?.toDouble() ?? 0.0;
                              final paidAmount = (item['paidAmount'] as num?)?.toDouble() ?? 0.0;
                              final overpaid = (item['overpaid'] as num?)?.toDouble() ?? 0.0;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                title: Text(
                                  '$surname $firstName',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('Admission No: $admissionNo'),
                                    Text('Class: $className - $armName'),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Bill: N ${formatter.format(billAmount)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'Paid: N ${formatter.format(paidAmount)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Overpaid: N ${formatter.format(overpaid)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                ),
                                onTap: () async {
                                  // Convert to Student model for navigation using fromMap
                                  final student = Student.fromMap(item);

                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StudentDetailsScreen(student: student),
                                    ),
                                  );
                                  // Refresh after returning
                                  _loadOverpayments();
                                },
                              ),
                            );
                            } catch (e, st) {
                              debugPrint("Error rendering overpayment item at index $index: $e\n$st");
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  title: const Text('Error loading student data'),
                                  subtitle: Text('Error: $e'),
                                ),
                              );
                            }
                          },
                        ),
                ),

                // Export PDF button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _overpayments.isEmpty ? null : _exportPDF,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Export as PDF'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
