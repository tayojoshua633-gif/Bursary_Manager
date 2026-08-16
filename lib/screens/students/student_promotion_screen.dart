// lib/screens/students/student_promotion_screen.dart
import 'package:flutter/material.dart';
import 'package:bursary_manager/data/database_helper_wrapper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';

class StudentPromotionScreen extends StatefulWidget {
  const StudentPromotionScreen({super.key});

  @override
  State<StudentPromotionScreen> createState() => _StudentPromotionScreenState();
}

class _StudentPromotionScreenState extends State<StudentPromotionScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sourceArms = [];
  List<Map<String, dynamic>> _targetArms = [];
  List<Map<String, dynamic>> _students = [];

  int? _sourceClassId;
  int? _sourceArmId;
  int? _targetClassId;
  int? _targetArmId;

  Set<int> _selectedStudents = {};
  Set<String> _siblingPhones = {};
  bool _selectAll = false;
  bool _loading = true;
  bool _loadingStudents = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _loading = true);
    _classes = await _db.getClasses();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSourceArms(int classId) async {
    final arms = await _db.getArmsByClass(classId);
    setState(() {
      _sourceArms = arms;
      _sourceArmId = null;
      _students = [];
      _selectedStudents.clear();
    });
  }

  Future<void> _loadTargetArms(int classId) async {
    final arms = await _db.getArmsByClass(classId);
    setState(() {
      _targetArms = arms;
      _targetArmId = null;
    });
  }

  Future<void> _loadStudents() async {
    if (_sourceClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select source class first')),
      );
      return;
    }

    setState(() => _loadingStudents = true);

    final db = await _db.database;
    
    String query = '''
      SELECT 
        s.*,
        c.name as className,
        a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.isActive = 1 AND s.classId = ?
    ''';

    List<dynamic> args = [_sourceClassId];

    if (_sourceArmId != null) {
      query += ' AND s.armId = ?';
      args.add(_sourceArmId);
    }

    query += ' ORDER BY s.surname ASC, s.firstName ASC';

    final students = await db.rawQuery(query, args);
    final siblingPhones = computeSiblingPhones(await _db.getActiveStudents());

    if (mounted) {
      setState(() {
        _students = students;
        _siblingPhones = siblingPhones;
        _selectedStudents.clear();
        _selectAll = false;
        _loadingStudents = false;
      });
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectAll) {
        _selectedStudents.clear();
        _selectAll = false;
      } else {
        _selectedStudents = _students.map((s) => s['id'] as int).toSet();
        _selectAll = true;
      }
    });
  }

  void _toggleStudent(int studentId) {
    setState(() {
      if (_selectedStudents.contains(studentId)) {
        _selectedStudents.remove(studentId);
        _selectAll = false;
      } else {
        _selectedStudents.add(studentId);
        if (_selectedStudents.length == _students.length) {
          _selectAll = true;
        }
      }
    });
  }

  Future<void> _promoteStudents() async {
    if (_selectedStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select students to promote')),
      );
      return;
    }

    if (_targetClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select target class')),
      );
      return;
    }

    // Confirm promotion
    final sourceClassName = _classes.firstWhere((c) => c['id'] == _sourceClassId)['name'];
    final targetClassName = _classes.firstWhere((c) => c['id'] == _targetClassId)['name'];
    final sourceArmName = _sourceArmId != null 
        ? _sourceArms.firstWhere((a) => a['id'] == _sourceArmId)['name']
        : 'All Arms';
    final targetArmName = _targetArmId != null
        ? _targetArms.firstWhere((a) => a['id'] == _targetArmId)['name']
        : 'No Arm';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Promotion'),
        content: Text(
          'Promote ${_selectedStudents.length} student(s) from:\n'
          '$sourceClassName - $sourceArmName\n\n'
          'To:\n'
          '$targetClassName${_targetArmId != null ? ' - $targetArmName' : ''}?\n\n'
          'This action will update their class and arm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Promote'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final db = await _db.database;
      int billsGeneratedCount = 0;

      // Perform bulk update
      for (final studentId in _selectedStudents) {
        await db.update(
          'students',
          {
            'classId': _targetClassId,
            'armId': _targetArmId,
          },
          where: 'id = ?',
          whereArgs: [studentId],
        );

        // Optional: Log promotion history
        await db.insert('promotion_history', {
          'studentId': studentId,
          'fromClassId': _sourceClassId,
          'fromArmId': _sourceArmId,
          'toClassId': _targetClassId,
          'toArmId': _targetArmId,
          'promotionDate': DateTime.now().toIso8601String(),
        });

        // AUTO-GENERATE BILL FOR NEW CLASS
        try {
          final billGenerated = await _autoGenerateBillForStudent(studentId, _targetClassId!);
          if (billGenerated) billsGeneratedCount++;
        } catch (e) {
          debugPrint('Failed to auto-generate bill for student $studentId: $e');
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully promoted ${_selectedStudents.length} student(s)\n'
            '${billsGeneratedCount > 0 ? 'Bills auto-generated for $billsGeneratedCount student(s)' : 'No fees assigned to target class'}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      // Reload students
      _loadStudents();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error promoting students: $e')),
      );
    }
  }

  // ----------------------------------------------------------
  // AUTO-GENERATE BILL FOR PROMOTED STUDENT
  // ----------------------------------------------------------
  Future<bool> _autoGenerateBillForStudent(int studentId, int classId) async {
    try {
      // Get active term and session
      final activeTerm = await _db.getActiveTerm();
      final activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";

      if (activeTerm.isEmpty || activeSession.isEmpty) {
        debugPrint('No active term/session - skipping auto-bill generation');
        return false;
      }

      // Check if class has assigned fees for this term/session
      final classFees = await _db.getClassFees(
        classId,
        activeTerm,
        activeSession,
      );

      if (classFees.isEmpty) {
        debugPrint('No fees assigned to target class - skipping auto-bill generation');
        return false;
      }

      // Calculate previous balance
      final previousBalance = await _db.computeOutstandingBeforeTerm(
        studentId,
        term: activeTerm,
        session: activeSession,
      );

      // Calculate total amount from class fees
      final subtotal = classFees.fold<double>(
        0.0,
        (sum, fee) => sum + ((fee['amount'] as num?)?.toDouble() ?? 0.0),
      );
      final grandTotal = subtotal + previousBalance;

      // Create bill data
      final bill = {
        'studentId': studentId,
        'totalAmount': grandTotal,
        'previousBalance': previousBalance,
        'term': activeTerm,
        'session': activeSession,
        'billDate': DateTime.now().toIso8601String(),
      };

      // Create breakdown data
      final breakdown = classFees.map((fee) {
        return {
          'feeItemId': fee['feeItemId'],
          'amount': fee['amount'],
          'label': '', // Will be populated from fee_items table
        };
      }).toList();

      // Insert or update bill
      await _db.insertStudentBill(bill, breakdown);

      debugPrint('Auto-generated bill for promoted student $studentId to class $classId');
      return true;
    } catch (e) {
      debugPrint('Error auto-generating bill: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promote Students'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // INFO CARD
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Promote students to the next class at the end of the session. '
                              'Students who are repeating should not be promoted.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // SOURCE CLASS SECTION
                  const Text(
                    'FROM (Current Class)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Source Class Dropdown
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Source Class',
                      prefixIcon: Icon(Icons.school),
                    ),
                    initialValue: _sourceClassId,
                    items: _classes
                        .map((c) => DropdownMenuItem<int>(
                              value: c['id'],
                              child: Text(c['name']),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _sourceClassId = v;
                        _sourceArmId = null;
                        _students = [];
                        _selectedStudents.clear();
                      });
                      if (v != null) _loadSourceArms(v);
                    },
                  ),

                  const SizedBox(height: 12),

                  // Source Arm Dropdown
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Source Arm (Optional)',
                      prefixIcon: Icon(Icons.people),
                      hintText: 'All Arms',
                    ),
                    initialValue: _sourceArmId,
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('All Arms'),
                      ),
                      ..._sourceArms.map((a) => DropdownMenuItem<int>(
                            value: a['id'],
                            child: Text(a['name']),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() => _sourceArmId = v);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Load Students Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _sourceClassId == null ? null : _loadStudents,
                      icon: const Icon(Icons.search),
                      label: const Text('Load Students'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // TARGET CLASS SECTION
                  const Text(
                    'TO (Target Class)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Target Class Dropdown
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Target Class',
                      prefixIcon: Icon(Icons.arrow_upward),
                    ),
                    initialValue: _targetClassId,
                    items: _classes
                        .map((c) => DropdownMenuItem<int>(
                              value: c['id'],
                              child: Text(c['name']),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _targetClassId = v;
                        _targetArmId = null;
                      });
                      if (v != null) _loadTargetArms(v);
                    },
                  ),

                  const SizedBox(height: 12),

                  // Target Arm Dropdown
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Target Arm (Optional)',
                      prefixIcon: Icon(Icons.people),
                      hintText: 'No Arm',
                    ),
                    initialValue: _targetArmId,
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('No Arm'),
                      ),
                      ..._targetArms.map((a) => DropdownMenuItem<int>(
                            value: a['id'],
                            child: Text(a['name']),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() => _targetArmId = v);
                    },
                  ),

                  const SizedBox(height: 24),

                  // STUDENTS LIST
                  if (_students.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Students (${_students.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              '${_selectedStudents.length} selected',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _toggleSelectAll,
                              child: Text(_selectAll ? 'Deselect All' : 'Select All'),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Students List
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _students.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: Colors.grey.shade200,
                        ),
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          final studentId = student['id'] as int;
                          final isSelected = _selectedStudents.contains(studentId);
                          final name = '${student['surname']} ${student['firstName']}'.trim();

                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (_) => _toggleStudent(studentId),
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                                SiblingMark(
                                  show: isSiblingPhone(
                                    student['parentPhone'] as String?,
                                    _siblingPhones,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              'Adm No: ${student['admissionNo']}\n'
                              '${student['className']} - ${student['armName']}',
                            ),
                            isThreeLine: true,
                            secondary: CircleAvatar(
                              backgroundColor: isSelected ? Colors.green : Colors.grey.shade300,
                              child: Icon(
                                isSelected ? Icons.check : Icons.person,
                                color: isSelected ? Colors.white : Colors.grey.shade600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // PROMOTE BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _selectedStudents.isEmpty ? null : _promoteStudents,
                        icon: const Icon(Icons.arrow_upward),
                        label: Text(
                          'Promote ${_selectedStudents.length} Student(s)',
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ],

                  if (_loadingStudents)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    ),

                  if (_students.isEmpty && !_loadingStudents && _sourceClassId != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No students found in the selected class/arm',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}