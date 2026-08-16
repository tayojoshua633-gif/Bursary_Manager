import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'dart:io';
import '../../data/database_helper_wrapper.dart';
import '../../models/student.dart';
import '../../utils/class_bills_pdf_generator.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';
import '../students/student_details_screen.dart';

class ClassBillsScreen extends StatefulWidget {
  const ClassBillsScreen({super.key});

  @override
  State<ClassBillsScreen> createState() => _ClassBillsScreenState();
}

class _ClassBillsScreenState extends State<ClassBillsScreen> {
  List<Map<String, dynamic>> _studentBills = [];
  List<Map<String, dynamic>> _filteredBills = [];
  List<Map<String, dynamic>> _classes = [];
  bool _isLoading = true;
  Set<String> _siblingPhones = {};

  String _searchQuery = '';
  int? _selectedClassId;
  String _currentTerm = '';
  String _currentSession = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Get current term and session from database (same as bill generation)
      final db = DatabaseHelperWrapper();
      _currentTerm = await db.getActiveTerm();
      _currentSession = (await db.getActiveSession())?['sessionName'] ?? DateTime.now().year.toString();

      // Load classes
      final classes = await db.getClasses();

      // Load all student bills for current term/session
      final bills = await _fetchStudentBills();

      if (mounted) {
        setState(() {
          _classes = classes;
          _studentBills = bills;
          _siblingPhones = computeSiblingPhones(bills);
          _isLoading = false;
        });

        // Re-apply filters (preserves selected class and search query)
        _filterBills();
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchStudentBills() async {
    final db = await DatabaseHelperWrapper().database;

    // DEBUG: Log current term and session
    debugPrint('🔍 Current Term: $_currentTerm');
    debugPrint('🔍 Current Session: $_currentSession');

    // DEBUG: Check if any bills exist in student_bills table
    final billsCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM student_bills WHERE term = ? AND session = ?',
      [_currentTerm, _currentSession],
    );
    debugPrint('🔍 Bills in database for this term/session: ${billsCount.first['count']}');

    // DEBUG: Check all bills in the table
    final allBills = await db.rawQuery(
      'SELECT term, session, COUNT(*) as count FROM student_bills GROUP BY term, session',
    );
    debugPrint('🔍 All bills in database:');
    for (var row in allBills) {
      debugPrint('   - Term: ${row['term']}, Session: ${row['session']}, Count: ${row['count']}');
    }

    final targetKey = DatabaseHelperWrapper.termSortKey(_currentTerm, _currentSession);
    final results = await db.rawQuery('''
      SELECT
        s.id as studentId,
        s.surname,
        s.firstName,
        s.otherName,
        s.parentPhone,
        c.name as className,
        a.name as armName,
        (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0)) as currentTermFee,
        (
          COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                    WHERE b2.studentId = s.id
                      AND ${DatabaseHelperWrapper.sqlTermKeyExpr('b2')} < ?), 0)
          -
          COALESCE((SELECT SUM(p2.amount) FROM payments p2
                    WHERE p2.studentId = s.id
                      AND ${DatabaseHelperWrapper.sqlTermKeyExpr('p2')} < ?), 0)
        ) as freshPreviousBalance,
        COALESCE(
          (SELECT SUM(amount)
           FROM payments
           WHERE studentId = s.id
             AND term = ?
             AND session = ?),
          0
        ) as totalPaid
      FROM students s
      INNER JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      LEFT JOIN student_bills b ON s.id = b.studentId
        AND b.term = ?
        AND b.session = ?
      WHERE s.isActive = 1
      ORDER BY c.name, COALESCE(a.name, ''), s.surname, s.firstName
    ''', [targetKey, targetKey, _currentTerm, _currentSession, _currentTerm, _currentSession]);

    // Merge currentTermFee + freshPreviousBalance into a single grandTotal field
    final enriched = results.map((row) {
      final currentTermFee = (row['currentTermFee'] as num).toDouble();
      final freshPrev = (row['freshPreviousBalance'] as num).toDouble();
      return Map<String, dynamic>.from(row)
        ..['totalBill'] = currentTermFee + freshPrev;
    }).toList();

    // DEBUG: Log sample results
    if (enriched.isNotEmpty) {
      debugPrint('🔍 Sample bill result: ${enriched.first}');
    } else {
      debugPrint('🔍 No results returned from query');
    }

    return enriched;
  }

  void _filterBills() {
    setState(() {
      _filteredBills = _studentBills.where((bill) {
        // Filter by class
        if (_selectedClassId != null) {
          // Need to match class name since we don't have classId in the query result
          final selectedClass = _classes.firstWhere(
            (c) => c['id'] == _selectedClassId,
            orElse: () => {'name': ''},
          );
          if (bill['className'] != selectedClass['name']) {
            return false;
          }
        }

        // Filter by search query
        if (_searchQuery.isNotEmpty) {
          final fullName = '${bill['surname']} ${bill['firstName']} ${bill['otherName'] ?? ''}'
              .toLowerCase();
          final className = (bill['className'] ?? '').toString().toLowerCase();
          final armName = (bill['armName'] ?? '').toString().toLowerCase();
          final query = _searchQuery.toLowerCase();

          return fullName.contains(query) ||
              className.contains(query) ||
              armName.contains(query);
        }

        return true;
      }).toList();
    });
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _filterBills();
  }

  void _onClassFilterChanged(int? classId) {
    setState(() => _selectedClassId = classId);
    _filterBills();
  }

  String _formatCurrency(num amount) {
    final formatter = NumberFormat('#,##0.00');
    return formatter.format(amount);
  }

  Color _getStatusColor(num totalBill, num totalPaid) {
    final outstanding = totalBill - totalPaid;
    if (outstanding <= 0) return Colors.green;
    if (totalPaid > 0) return Colors.orange;
    return Colors.red;
  }

  Future<void> _exportToPDF() async {
    if (_filteredBills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No data to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);

      // Get school profile
      final schoolProfileData = await DatabaseHelperWrapper().getSchoolProfile();
      final schoolProfile = schoolProfileData ?? {
        'name': 'School Name',
        'address': '',
        'phone': '',
        'email': '',
      };

      // Get filter class name if applicable
      String? filterClassName;
      if (_selectedClassId != null) {
        final selectedClass = _classes.firstWhere(
          (c) => c['id'] == _selectedClassId,
          orElse: () => {'name': ''},
        );
        filterClassName = selectedClass['name'] as String?;
      }

      // Generate PDF
      final pdfPath = await ClassBillsPDFGenerator.generateClassBillsPDF(
        studentBills: _filteredBills,
        term: _currentTerm,
        session: _currentSession,
        schoolProfile: schoolProfile,
        filterClassName: filterClassName,
      );

      setState(() => _isLoading = false);

      if (!mounted) return;

      // Show success dialog with options
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('PDF Generated Successfully'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your Class Bills report has been generated.'),
              const SizedBox(height: 12),
              Text(
                'File saved to:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                pdfPath.split('/').last,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await Printing.sharePdf(
                  bytes: await File(pdfPath).readAsBytes(),
                  filename: pdfPath.split('/').last,
                );
              },
              icon: const Icon(Icons.share),
              label: const Text('Share'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Bills'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          // Prominent Export PDF Button
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _exportToPDF,
              icon: const Icon(Icons.picture_as_pdf, size: 20),
              label: const Text(
                'Export PDF',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.indigo,
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header with term/session info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade50, Colors.blue.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                bottom: BorderSide(color: Colors.indigo.shade200),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long, color: Colors.indigo.shade700, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Student Bills Overview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$_currentTerm, $_currentSession',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_filteredBills.length} students',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                // Search Bar
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search by name or class...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.indigo.shade400),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Class Filter
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedClassId,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.filter_list, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.indigo.shade400),
                      ),
                    ),
                    hint: const Text('All Classes', style: TextStyle(fontSize: 13)),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All Classes', style: TextStyle(fontSize: 13)),
                      ),
                      ..._classes.map((cls) {
                        return DropdownMenuItem<int?>(
                          value: cls['id'] as int,
                          child: Text(
                            cls['name'] as String,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }),
                    ],
                    onChanged: _onClassFilterChanged,
                  ),
                ),
              ],
            ),
          ),

          // Student Bills List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredBills.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty || _selectedClassId != null
                                  ? 'No students found'
                                  : 'No student bills for this term',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filteredBills.length,
                        itemBuilder: (context, index) {
                          final bill = _filteredBills[index];
                          return _buildStudentBillCard(bill);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentBillCard(Map<String, dynamic> bill) {
    final studentId = bill['studentId'] as int;
    final surname = bill['surname'] as String;
    final firstName = bill['firstName'] as String;
    final otherName = bill['otherName'] as String?;
    final parentPhone = bill['parentPhone'] as String?;
    final className = bill['className'] as String;
    final armName = bill['armName'] as String?;
    final totalBill = (bill['totalBill'] as num).toDouble();
    final totalPaid = (bill['totalPaid'] as num).toDouble();
    final outstanding = totalBill - totalPaid;

    final fullName = '$surname $firstName ${otherName ?? ''}'.trim();
    final classArm = armName != null ? '$className - $armName' : className;
    final statusColor = _getStatusColor(totalBill, totalPaid);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () async {
          // Fetch student and navigate to details
          try {
            final studentMap = await DatabaseHelperWrapper().getStudentById(studentId);
            if (studentMap != null && mounted) {
              final student = Student.fromMap(studentMap);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StudentDetailsScreen(student: student),
                ),
              );
            }
          } catch (e) {
            debugPrint('Error loading student: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error loading student details: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Student Info
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                fullName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SiblingMark(show: isSiblingPhone(parentPhone, _siblingPhones)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.class_, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              classArm,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Bill Amount
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₦${_formatCurrency(totalBill)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Total Bill',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Payment Summary
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Paid
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Paid',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '₦${_formatCurrency(totalPaid)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),

                    // Outstanding
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Outstanding',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              outstanding <= 0
                                  ? Icons.check_circle
                                  : Icons.warning,
                              size: 14,
                              color: statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '₦${_formatCurrency(outstanding)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
