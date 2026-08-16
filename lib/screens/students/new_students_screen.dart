// lib/screens/students/new_students_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/student.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';
import 'student_details_screen.dart';

class NewStudentsScreen extends StatefulWidget {
  const NewStudentsScreen({super.key});

  @override
  State<NewStudentsScreen> createState() => _NewStudentsScreenState();
}

class _NewStudentsScreenState extends State<NewStudentsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _newStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  bool _loading = true;
  String _activeTerm = '';
  String _activeSession = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Set<String> _siblingPhones = {};

  @override
  void initState() {
    super.initState();
    _loadNewStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNewStudents() async {
    setState(() => _loading = true);

    try {
      // Get active term and session
      _activeTerm = await _db.getActiveTerm();
      final activeSessionData = await _db.getActiveSession();
      _activeSession = activeSessionData?['sessionName'] ?? '';

      if (_activeTerm.isEmpty || _activeSession.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      // Query to get new students (students with registration fee in current term/session)
      // Uses the same logic as termly_report_screen.dart (lines 193-240)
      // Check the 'label' field from student_fee_breakdown for registration fee variations
      final db = await _db.database;

      // Get all students with bills in current term/session
      final billsRaw = await db.rawQuery('''
        SELECT DISTINCT sb.id as billId, sb.studentId
        FROM student_bills sb
        WHERE sb.term = ? AND sb.session = ?
      ''', [_activeTerm, _activeSession]);

      debugPrint('📊 Found ${billsRaw.length} bills for $_activeTerm - $_activeSession');

      final List<int> newStudentIds = [];

      for (var billRow in billsRaw) {
        final billId = billRow['billId'] as int;
        final studentId = billRow['studentId'] as int;

        // Get bill breakdown (same as termly report)
        final breakdown = await _db.getBillBreakdown(billId);

        // Check if any fee item contains "registration" or "reg" (same logic as termly report)
        bool hasRegistrationFee = false;
        for (var item in breakdown) {
          final label = (item['label'] ?? '').toString().toLowerCase();
          if (label.contains('registration') ||
              label.contains('reg. fee') ||
              label.contains('reg fee') ||
              label == 'reg.' ||
              label == 'reg') {
            hasRegistrationFee = true;
            break;
          }
        }

        if (hasRegistrationFee) {
          newStudentIds.add(studentId);
        }
      }

      debugPrint('📊 Found ${newStudentIds.length} new students with registration fees');

      // Now get full student details for the identified new students
      List<Map<String, dynamic>> results = [];
      if (newStudentIds.isNotEmpty) {
        final placeholders = List.filled(newStudentIds.length, '?').join(',');
        results = await db.rawQuery('''
          SELECT
            s.id,
            s.admissionNo,
            s.surname,
            s.firstName,
            s.otherName,
            s.classId,
            s.armId,
            s.dateOfAdmission,
            s.gender,
            s.dob,
            s.address,
            s.parentName,
            s.parentPhone,
            s.parentEmail,
            s.parentAddress,
            s.photoPath,
            s.isActive,
            c.name as className,
            a.name as armName
          FROM students s
          INNER JOIN classes c ON s.classId = c.id
          LEFT JOIN arms a ON s.armId = a.id
          WHERE s.isActive = 1
            AND s.id IN ($placeholders)
          ORDER BY
            CASE WHEN s.dateOfAdmission IS NOT NULL THEN 0 ELSE 1 END,
            s.dateOfAdmission DESC,
            s.surname,
            s.firstName
        ''', newStudentIds);
      }

      final siblingPhones = computeSiblingPhones(await _db.getActiveStudents());

      setState(() {
        _newStudents = results;
        _filteredStudents = results;
        _siblingPhones = siblingPhones;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading new students: $e');
      setState(() => _loading = false);
    }
  }

  void _filterStudents(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredStudents = _newStudents;
      } else {
        _filteredStudents = _newStudents.where((student) {
          final fullName =
              '${student['surname']} ${student['firstName']} ${student['otherName'] ?? ''}'
                  .toLowerCase();
          final admissionNo = (student['admissionNo'] ?? '').toString().toLowerCase();
          final className = (student['className'] ?? '').toString().toLowerCase();
          final searchLower = query.toLowerCase();

          return fullName.contains(searchLower) ||
              admissionNo.contains(searchLower) ||
              className.contains(searchLower);
        }).toList();
      }
    });
  }

  void _navigateToStudentDetails(Map<String, dynamic> studentData) {
    final student = Student.fromMap(studentData);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentDetailsScreen(student: student),
      ),
    ).then((value) {
      if (value == true) {
        _loadNewStudents();
      }
    });
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Not recorded';
    try {
      final date = DateTime.parse(dateStr);
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Students'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade600, Colors.teal.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNewStudents,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header Section with Gradient
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.teal.shade50, Colors.blue.shade50],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade300,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title and Count
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade600,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.teal.shade200,
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.person_add,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Current Term Registrations',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_activeTerm - $_activeSession',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Count Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade600,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.shade200,
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                '${_filteredStudents.length}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Search Bar
                        if (_newStudents.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: _searchController,
                            onChanged: _filterStudents,
                            decoration: InputDecoration(
                              hintText: 'Search by name, admission no, or class...',
                              prefixIcon: const Icon(Icons.search, color: Colors.teal),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: () {
                                        _searchController.clear();
                                        _filterStudents('');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.teal.shade400, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Students List
                Expanded(
                  child: _newStudents.isEmpty
                      ? _buildEmptyState()
                      : _filteredStudents.isEmpty
                          ? _buildNoResultsState()
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredStudents.length,
                              itemBuilder: (context, index) {
                                final student = _filteredStudents[index];
                                return _buildStudentCard(student, index);
                              },
                            ),
                ),
              ],
            ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student, int index) {
    final fullName =
        '${student['surname']} ${student['firstName']} ${student['otherName'] ?? ''}'
            .trim();
    final admissionNo = student['admissionNo'] ?? 'N/A';
    final className = student['className'] ?? 'N/A';
    final armName = student['armName'] ?? '';
    final admissionClass = armName.isNotEmpty ? '$className - $armName' : className;
    final dateOfAdmission = _formatDate(student['dateOfAdmission']);
    final gender = student['gender'] ?? 'N/A';
    final photoPath = student['photoPath'];

    // Check if photo exists
    ImageProvider? photoProvider;
    if (photoPath != null && photoPath.isNotEmpty && File(photoPath).existsSync()) {
      photoProvider = FileImage(File(photoPath));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _navigateToStudentDetails(student),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Serial Number Badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade400, Colors.teal.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Student Photo/Avatar
              Hero(
                tag: 'student_${student['id']}',
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: gender == 'Male'
                      ? Colors.blue.shade100
                      : Colors.pink.shade100,
                  backgroundImage: photoProvider,
                  child: photoProvider == null
                      ? Icon(
                          gender == 'Male' ? Icons.boy : Icons.girl,
                          size: 32,
                          color: gender == 'Male'
                              ? Colors.blue.shade700
                              : Colors.pink.shade700,
                        )
                      : null,
                ),
              ),

              const SizedBox(width: 16),

              // Student Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fullName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SiblingMark(
                          show: isSiblingPhone(student['parentPhone'] as String?, _siblingPhones),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Admission Number
                    Row(
                      children: [
                        Icon(Icons.badge, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          admissionNo,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Class
                    Row(
                      children: [
                        Icon(Icons.class_, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            admissionClass,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Date of Admission
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.teal.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateOfAdmission,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.teal.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow Icon
              Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_add_disabled,
                size: 80,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No New Students',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'For $_activeTerm - $_activeSession',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.teal.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 24, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Text(
                        'How it works:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Students appear here when they have a Registration Fee in their bill'),
                  const SizedBox(height: 8),
                  _buildInfoRow('Fee names like "Reg", "Reg. Fee", or "Registration" are detected'),
                  const SizedBox(height: 8),
                  _buildInfoRow('Generate bills with registration fees for new students'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No Results Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.blue.shade600,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
