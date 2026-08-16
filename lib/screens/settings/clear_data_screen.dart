// lib/screens/settings/clear_data_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/permission_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../auth/welcome_screen.dart';

class ClearDataScreen extends StatefulWidget {
  const ClearDataScreen({super.key});

  @override
  State<ClearDataScreen> createState() => _ClearDataScreenState();
}

class _ClearDataScreenState extends State<ClearDataScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _codeCtrl = TextEditingController();

  bool _loading = true;
  bool _hasPermission = false;
  String _activeTerm = "";
  String _activeSession = "";

  static const String _clearCode = "12341234";

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadMeta();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';

    final currentUser = {
      'id': userId,
      'userType': userType,
      'username': username,
    };

    final hasDataManagementPerm = await PermissionHelper.hasPermission(currentUser, 'data_management');

    if (mounted) {
      setState(() => _hasPermission = hasDataManagementPerm);
    }
  }

  Future<void> _loadMeta() async {
    setState(() => _loading = true);
    _activeTerm = await _db.getActiveTerm();
    _activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";
    if (mounted) setState(() => _loading = false);
  }

  // -------------------------------------------------------------------
  // CODE VERIFICATION
  // -------------------------------------------------------------------

  Future<bool> _verifyCode(String action) async {
    _codeCtrl.clear();

    return await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Text('Security Code Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to: $action',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Enter security code to proceed:'),
            const SizedBox(height: 8),
            TextField(
              controller: _codeCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Security Code',
                border: OutlineInputBorder(),
                counterText: '',
                prefixIcon: Icon(Icons.vpn_key),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_codeCtrl.text == _clearCode) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid security code!'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Verify'),
          ),
        ],
      ),
    ) ?? false;
  }

  // -------------------------------------------------------------------
  // CLEAR METHODS FOR EACH CATEGORY
  // -------------------------------------------------------------------

  Future<void> _clearStudents() async {
    final db = await _db.database;
    await db.delete("students");
    await db.delete("student_bills");
    await db.delete("student_fee_breakdown");
    await db.delete("payments");
    await db.delete("promotion_history");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All students and related data cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  // -------------------------------------------------------------------
  // CLEAR STUDENTS BY CLASS / ARM (fix wrong-class uploads)
  // -------------------------------------------------------------------

  Future<void> _openClearStudentsByClassArm() async {
    final verified = await _verifyCode('Clear Students by Class/Arm');
    if (!verified) return;

    final db = await _db.database;
    final classes = await db.query('classes', orderBy: 'name ASC');

    if (!mounted) return;

    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No classes found'), backgroundColor: Colors.red),
      );
      return;
    }

    int? selectedClassId;
    int? selectedArmId;
    List<Map<String, dynamic>> arms = [];
    int? studentCount;

    Future<void> refreshCount(void Function(void Function()) setDialogState) async {
      if (selectedClassId == null) {
        setDialogState(() => studentCount = null);
        return;
      }
      final where = selectedArmId != null ? 'classId = ? AND armId = ?' : 'classId = ?';
      final args = selectedArmId != null ? [selectedClassId, selectedArmId] : [selectedClassId];
      final result = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM students WHERE $where',
        args,
      );
      final count = (result.first['cnt'] as int?) ?? 0;
      setDialogState(() => studentCount = count);
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.people_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('Clear Students by Class/Arm'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Only use this to fix students mistakenly uploaded to the wrong class/arm. '
                            'Do NOT use this to remove genuine, existing students — it will also delete '
                            'their bills, payments and promotion history permanently.',
                            style: TextStyle(fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select the class (and optionally arm) whose students you want to remove.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Class',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: selectedClassId,
                    items: classes
                        .map((c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text(c['name'].toString()),
                            ))
                        .toList(),
                    onChanged: (v) async {
                      setDialogState(() {
                        selectedClassId = v;
                        selectedArmId = null;
                        arms = [];
                        studentCount = null;
                      });
                      if (v != null) {
                        final armData = await db.query(
                          'arms',
                          where: 'classId = ?',
                          whereArgs: [v],
                          orderBy: 'name ASC',
                        );
                        setDialogState(() => arms = armData);
                      }
                      await refreshCount(setDialogState);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    decoration: const InputDecoration(
                      labelText: 'Arm',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: selectedArmId,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All arms in this class'),
                      ),
                      ...arms.map((a) => DropdownMenuItem<int?>(
                            value: a['id'] as int,
                            child: Text('Arm ${a['name']}'),
                          )),
                    ],
                    onChanged: selectedClassId == null
                        ? null
                        : (v) async {
                            setDialogState(() => selectedArmId = v);
                            await refreshCount(setDialogState);
                          },
                  ),
                  const SizedBox(height: 16),
                  if (studentCount != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: studentCount! > 0 ? Colors.orange.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: studentCount! > 0 ? Colors.orange.shade200 : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.people,
                            color: studentCount! > 0 ? Colors.orange : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              studentCount! > 0
                                  ? '$studentCount student(s) will be removed, along with their bills, payments and promotion history.'
                                  : 'No students found in this selection.',
                              style: TextStyle(
                                color: studentCount! > 0 ? Colors.orange.shade900 : Colors.grey.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: (selectedClassId == null || studentCount == null || studentCount == 0)
                    ? null
                    : () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );

    if (proceed != true || selectedClassId == null) return;

    final className = classes.firstWhere((c) => c['id'] == selectedClassId)['name'].toString();
    final armName = selectedArmId == null
        ? 'All Arms'
        : arms.firstWhere((a) => a['id'] == selectedArmId)['name'].toString();

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Final Confirmation'),
          ],
        ),
        content: Text(
          'You are about to permanently delete $studentCount student(s) in "$className — $armName", '
          'including their bills, payments and promotion history.\n\n'
          'Only proceed if these students were mistakenly uploaded to the wrong class/arm. '
          'Do NOT proceed if these are genuine, existing students — their records will be lost.\n\n'
          'This cannot be undone!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final where = selectedArmId != null ? 'classId = ? AND armId = ?' : 'classId = ?';
    final args = selectedArmId != null ? [selectedClassId, selectedArmId] : [selectedClassId];

    final students = await db.query('students', columns: ['id'], where: where, whereArgs: args);
    final studentIds = students.map((s) => s['id'] as int).toList();

    if (studentIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No students found in this selection'), backgroundColor: Colors.red),
      );
      return;
    }

    final placeholders = List.filled(studentIds.length, '?').join(',');

    await db.rawDelete(
      'DELETE FROM student_fee_breakdown WHERE billId IN (SELECT id FROM student_bills WHERE studentId IN ($placeholders))',
      studentIds,
    );
    await db.delete('student_bills', where: 'studentId IN ($placeholders)', whereArgs: studentIds);
    await db.delete('payments', where: 'studentId IN ($placeholders)', whereArgs: studentIds);
    await db.delete('promotion_history', where: 'studentId IN ($placeholders)', whereArgs: studentIds);
    await db.delete('students', where: 'id IN ($placeholders)', whereArgs: studentIds);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
            const SizedBox(width: 8),
            const Text('Success'),
          ],
        ),
        content: Text('${studentIds.length} student(s) removed from "$className — $armName".'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearClassesArms() async {
    final db = await _db.database;
    await db.delete("arms");
    await db.delete("classes");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All classes and arms cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearExpenses() async {
    final db = await _db.database;
    await db.delete("expenses");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All expenses cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearSalesRecords() async {
    final db = await _db.database;

    // Get all sales to restore stock quantities
    final sales = await db.query('sales', where: 'quantity > 0');

    // Restore stock for each sale
    for (final sale in sales) {
      final stockItemId = sale['stockItemId'] as int;
      final quantity = sale['quantity'] as int;

      await db.rawUpdate('''
        UPDATE stock_items
        SET currentQuantity = currentQuantity + ?
        WHERE id = ?
      ''', [quantity, stockItemId]);
    }

    await db.delete("sales");
    await db.delete("sales_debtors");
    await db.delete("stock_movements");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All sales records cleared and stock restored"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearStockItems() async {
    final db = await _db.database;
    await db.delete("stock_items");
    await db.delete("stock_movements");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All stock items cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearPayments() async {
    final db = await _db.database;
    await db.delete("payments");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All payments cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearBills() async {
    final db = await _db.database;
    await db.delete("student_bills");
    await db.delete("student_fee_breakdown");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All bills cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearFeeItems() async {
    final db = await _db.database;
    await db.delete("fee_items");
    await db.delete("class_fees");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All fee items cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearSpecialFeeItems() async {
    final db = await _db.database;
    await db.delete("special_fee_items");
    await db.delete("special_class_fees");
    await db.delete("excluded_default_fees");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All special fee items and assignments cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearSpecialClassFees() async {
    final db = await _db.database;
    await db.delete("special_class_fees");
    await db.delete("excluded_default_fees");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All special class fee assignments cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearExcludedDefaultFees() async {
    final db = await _db.database;
    await db.delete("excluded_default_fees");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All excluded default fees cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearParents() async {
    final db = await _db.database;
    await db.delete("parents");

    // Also clear parent references in students table
    await db.rawUpdate('UPDATE students SET parentId = NULL');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All parents cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  // TEMPORARY TOOL: Clear parent data inside student table
  Future<void> _clearStudentParentData() async {
    final db = await _db.database;

    // Clear parent-related fields in students table (use empty strings for NOT NULL fields)
    await db.rawUpdate('''
      UPDATE students SET
        parentPhone = '',
        parentName = '',
        parentEmail = '',
        parentAddress = '',
        parentId = NULL
    ''');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Parent data cleared from all student records"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearStaff() async {
    final db = await _db.database;

    // Clear all staff-related tables
    await db.delete("staff_salary_payments");
    await db.delete("staff_deductions");
    await db.delete("staff_loans");
    await db.delete("staff_incentives");
    await db.delete("staff_office_allocations");
    await db.delete("staff_class_allocations");
    await db.delete("staff");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All staff and related records cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearStaffOffices() async {
    final db = await _db.database;

    // Clear office allocations first (foreign key dependency)
    await db.delete("staff_office_allocations");
    await db.delete("staff_offices");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All staff offices cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearStaffAllocations() async {
    final db = await _db.database;
    await db.delete("staff_class_allocations");
    await db.delete("staff_office_allocations");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All staff allocations cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearStaffPayroll() async {
    final db = await _db.database;
    await db.delete("staff_salary_payments");
    await db.delete("staff_deductions");
    await db.delete("staff_loans");
    await db.delete("staff_incentives");

    // Reset staff salaries to 0
    await db.rawUpdate('UPDATE staff SET salary = 0');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All staff payroll data cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearUsers() async {
    final db = await _db.database;
    await db.delete("users");

    // Re-create default admin user
    await db.insert('users', {
      'username': 'admin',
      'password': 'admin123',
      'userType': 'super_admin',
      'email': '',
      'isActive': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Users reset to default admin account"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearSuppliers() async {
    final db = await _db.database;

    // Clear supplier references in stock_items first
    await db.rawUpdate('UPDATE stock_items SET supplierId = NULL');
    await db.delete("suppliers");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All suppliers cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearLicenses() async {
    final db = await _db.database;
    await db.delete("licenses");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All licenses cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearSessions() async {
    final db = await _db.database;
    await db.delete("sessions");

    // Re-create a default session
    await db.insert('sessions', {
      'sessionName': '2024/2025',
      'isActive': 1,
    });

    // Reset active term to 1st Term
    await db.update(
      'settings',
      {'value': '1st Term'},
      where: 'key = ?',
      whereArgs: ['active_term'],
    );

    await _loadMeta();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Sessions reset to default (2024/2025, 1st Term)"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearSchoolProfile() async {
    final db = await _db.database;

    // Clear school profile settings
    await db.delete(
      'settings',
      where: 'key IN (?, ?, ?, ?, ?, ?, ?)',
      whereArgs: [
        'school_name',
        'school_address',
        'school_phone',
        'school_email',
        'school_motto',
        'school_logo',
        'principal_name',
      ],
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("School profile cleared"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearFeePriority() async {
    final db = await _db.database;
    await db.delete("fee_priority");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Fee priority order cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearExpenseCategories() async {
    final db = await _db.database;
    await db.delete("expense_categories");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Expense categories cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearExamRegistrations() async {
    final db = await _db.database;
    await db.delete("examination_registrations");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Exam registrations cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearExternalExaminations() async {
    final db = await _db.database;
    await db.delete("examination_registrations");
    await db.delete("external_examinations");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("External examinations and registrations cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearStaffSalaryHistory() async {
    final db = await _db.database;
    await db.delete("staff_salary_history");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Staff salary history cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearSchoolDivisions() async {
    final db = await _db.database;
    await db.delete("division_class_allocations");
    await db.delete("school_divisions");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("School divisions and allocations cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearSubjects() async {
    final db = await _db.database;
    await db.delete("subject_teacher_allocations");
    await db.delete("class_subject_allocations");
    await db.delete("student_scores");
    await db.delete("subjects");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Subjects and related allocations cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearActivities() async {
    final db = await _db.database;
    await db.delete("class_activity_allocations");
    await db.delete("student_psychomotor_scores");
    await db.delete("student_affective_scores");
    await db.delete("activities");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Activities and related records cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearExamsAndGrading() async {
    final db = await _db.database;
    await db.delete("result_computations");
    await db.delete("student_scores");
    await db.delete("grading_definitions");
    await db.delete("exams");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Exams and grading definitions cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearStudentScores() async {
    final db = await _db.database;
    await db.delete("result_computations");
    await db.delete("student_psychomotor_scores");
    await db.delete("student_affective_scores");
    await db.delete("student_scores");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("All student scores and results cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearPsychomotorAffective() async {
    final db = await _db.database;
    await db.delete("student_psychomotor_scores");
    await db.delete("student_affective_scores");
    await db.delete("psychomotor_skills");
    await db.delete("affective_traits");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Psychomotor skills and affective traits cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearResultComputations() async {
    final db = await _db.database;
    await db.delete("result_computations");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Result computations cleared"), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearPrintCounters() async {
    final db = await _db.database;
    await db.delete("print_counters");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Print counters reset"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _resetPermissions() async {
    final db = await _db.database;
    await db.delete("permissions");

    // Re-seed default permissions
    await _seedDefaultPermissions(db);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Permissions reset to defaults"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _seedDefaultPermissions(Database db) async {
    // Default permissions for each role
    final defaultPermissions = {
      'admin': [
        'dashboard', 'students', 'classes', 'fees', 'payments',
        'billing', 'reports', 'expenses', 'stock', 'sales',
        'backup', 'sessions', 'school_profile',
      ],
      'bursar': [
        'dashboard', 'students', 'fees', 'payments', 'billing',
        'reports', 'expenses', 'stock', 'sales',
      ],
    };

    for (final entry in defaultPermissions.entries) {
      for (final module in entry.value) {
        await db.insert(
          'permissions',
          {
            'role': entry.key,
            'module': module,
            'canAccess': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  Future<void> _clearAllAppData() async {
    try {
      await _db.closeAndReset();
      final dbPath = await getDatabasesPath();
      final fullPath = path.join(dbPath, 'bursary_manager.db');
      await deleteDatabase(fullPath);

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("All app data cleared! Database recreated."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // -------------------------------------------------------------------
  // BUILD CATEGORY CARD
  // -------------------------------------------------------------------

  Widget _buildCategoryCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onClear,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          description,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: ElevatedButton(
          onPressed: () async {
            bool verified = await _verifyCode('Clear $title');
            if (!verified) return;

            bool confirm = await showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Confirm'),
                content: Text('Clear all $title?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ) ?? false;

            if (confirm) {
              onClear();

              // Show success confirmation dialog
              if (!mounted) return;
              await showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
                      const SizedBox(width: 8),
                      const Text('Success'),
                    ],
                  ),
                  content: Text('$title has been cleared successfully.'),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
          child: const Text('Clear'),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // BUILD UI
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission && !_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Data Clearing Tools"),
          backgroundColor: Colors.red,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Access Denied',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'You do not have permission to access data clearing tools.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Data Clearing Tools"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Active term/session info
                Card(
                  color: Colors.blue.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.info_outline, color: Colors.blue),
                    title: Text("Term: $_activeTerm | Session: $_activeSession"),
                    subtitle: const Text("A security code is required for all operations"),
                  ),
                ),

                const SizedBox(height: 20),

                // Students
                _buildCategoryCard(
                  title: 'Students',
                  description: 'Remove all students, bills, payments & promotion history',
                  icon: Icons.people,
                  color: Colors.orange,
                  onClear: _clearStudents,
                ),

                // Students by Class/Arm (targeted fix for wrong-class uploads)
                Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.withValues(alpha: 0.1),
                      child: const Icon(Icons.people_outline, color: Colors.orange),
                    ),
                    title: const Text(
                      'Students by Class/Arm',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Only for fixing mistaken uploads to the wrong class/arm — not for removing '
                      'existing students. Deletes their bills, payments & promotion history too.',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: ElevatedButton(
                      onPressed: _openClearStudentsByClassArm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Clear'),
                    ),
                  ),
                ),

                // Classes & Arms
                _buildCategoryCard(
                  title: 'Classes & Arms',
                  description: 'Remove all classes and arms',
                  icon: Icons.class_,
                  color: Colors.purple,
                  onClear: _clearClassesArms,
                ),

                // Fee Items
                _buildCategoryCard(
                  title: 'Fee Items',
                  description: 'Remove all fee items and class fee assignments',
                  icon: Icons.attach_money,
                  color: Colors.teal,
                  onClear: _clearFeeItems,
                ),

                // Fee Priority
                _buildCategoryCard(
                  title: 'Fee Priority',
                  description: 'Clear fee payment priority ordering (Fee Tracker)',
                  icon: Icons.low_priority,
                  color: Colors.teal.shade300,
                  onClear: _clearFeePriority,
                ),

                // Special Fee Items (New Intake)
                _buildCategoryCard(
                  title: 'Special Fee Items',
                  description: 'Remove all special fee items, class assignments & exclusions',
                  icon: Icons.add_card,
                  color: Colors.orange.shade700,
                  onClear: _clearSpecialFeeItems,
                ),

                // Special Class Fees
                _buildCategoryCard(
                  title: 'Special Class Fees',
                  description: 'Remove special fee assignments to classes (keeps fee items)',
                  icon: Icons.assignment,
                  color: Colors.amber.shade700,
                  onClear: _clearSpecialClassFees,
                ),

                // Excluded Default Fees
                _buildCategoryCard(
                  title: 'Excluded Default Fees',
                  description: 'Restore all default fees to new intake bills',
                  icon: Icons.restore,
                  color: Colors.lightBlue.shade700,
                  onClear: _clearExcludedDefaultFees,
                ),

                // Bills
                _buildCategoryCard(
                  title: 'Bills',
                  description: 'Remove all student bills and fee breakdowns',
                  icon: Icons.receipt_long,
                  color: Colors.indigo,
                  onClear: _clearBills,
                ),

                // Payments
                _buildCategoryCard(
                  title: 'Payments',
                  description: 'Remove all payment records',
                  icon: Icons.payment,
                  color: Colors.green,
                  onClear: _clearPayments,
                ),

                // Stock Items
                _buildCategoryCard(
                  title: 'Stock Items',
                  description: 'Remove all stock items and movements',
                  icon: Icons.inventory_2,
                  color: Colors.brown,
                  onClear: _clearStockItems,
                ),

                // Sales Records
                _buildCategoryCard(
                  title: 'Sales Records',
                  description: 'Remove all sales, debtors & movements (restores stock)',
                  icon: Icons.point_of_sale,
                  color: Colors.deepOrange,
                  onClear: _clearSalesRecords,
                ),

                // Expenses
                _buildCategoryCard(
                  title: 'Expenses',
                  description: 'Remove all expense records',
                  icon: Icons.money_off,
                  color: Colors.pink,
                  onClear: _clearExpenses,
                ),

                // Expense Categories
                _buildCategoryCard(
                  title: 'Expense Categories',
                  description: 'Remove all expense category definitions (preset & custom)',
                  icon: Icons.category,
                  color: Colors.pink.shade300,
                  onClear: _clearExpenseCategories,
                ),

                // Exam Registrations
                _buildCategoryCard(
                  title: 'Exam Registrations',
                  description: 'Clear all student exam registration records (keeps exam definitions)',
                  icon: Icons.how_to_reg,
                  color: Colors.cyan.shade700,
                  onClear: _clearExamRegistrations,
                ),

                // External Examinations
                _buildCategoryCard(
                  title: 'External Examinations',
                  description: 'Remove all exam definitions and registrations (WAEC, NECO, JAMB, etc.)',
                  icon: Icons.school_outlined,
                  color: Colors.cyan.shade900,
                  onClear: _clearExternalExaminations,
                ),

                // Parents
                _buildCategoryCard(
                  title: 'Parents',
                  description: 'Remove all parent records',
                  icon: Icons.family_restroom,
                  color: Colors.cyan,
                  onClear: _clearParents,
                ),

                // Staff
                _buildCategoryCard(
                  title: 'Staff',
                  description: 'Remove all staff, allocations, loans, incentives & payroll',
                  icon: Icons.badge,
                  color: Colors.indigo.shade700,
                  onClear: _clearStaff,
                ),

                // Staff Offices
                _buildCategoryCard(
                  title: 'Staff Offices',
                  description: 'Remove all staff offices and office allocations',
                  icon: Icons.business,
                  color: Colors.teal.shade700,
                  onClear: _clearStaffOffices,
                ),

                // Staff Allocations
                _buildCategoryCard(
                  title: 'Staff Allocations',
                  description: 'Remove all class and office allocations (keeps staff)',
                  icon: Icons.assignment_ind,
                  color: Colors.deepPurple.shade400,
                  onClear: _clearStaffAllocations,
                ),

                // Staff Payroll
                _buildCategoryCard(
                  title: 'Staff Payroll',
                  description: 'Remove salary payments, deductions, loans & incentives',
                  icon: Icons.account_balance_wallet,
                  color: Colors.green.shade700,
                  onClear: _clearStaffPayroll,
                ),

                // Staff Salary History
                _buildCategoryCard(
                  title: 'Staff Salary History',
                  description: 'Clear staff salary increment history records',
                  icon: Icons.history,
                  color: Colors.green.shade400,
                  onClear: _clearStaffSalaryHistory,
                ),

                // Suppliers
                _buildCategoryCard(
                  title: 'Suppliers',
                  description: 'Remove all supplier records',
                  icon: Icons.local_shipping,
                  color: Colors.blue.shade700,
                  onClear: _clearSuppliers,
                ),

                // TEMPORARY: Student Parent Data
                _buildCategoryCard(
                  title: 'Student Parent Data',
                  description: 'Clear parent info (phone, name, email, address) from student records',
                  icon: Icons.person_remove,
                  color: Colors.lime.shade700,
                  onClear: _clearStudentParentData,
                ),

                // Print Counters
                _buildCategoryCard(
                  title: 'Print Counters',
                  description: 'Reset all print count records',
                  icon: Icons.print,
                  color: Colors.blueGrey,
                  onClear: _clearPrintCounters,
                ),

                // School Profile
                _buildCategoryCard(
                  title: 'School Profile',
                  description: 'Clear school name, address, logo & contact info',
                  icon: Icons.school,
                  color: Colors.amber,
                  onClear: _clearSchoolProfile,
                ),

                // ── CA Portal ──────────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    'CA Portal Data',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),

                // School Divisions
                _buildCategoryCard(
                  title: 'School Divisions',
                  description: 'Remove division definitions and class-to-division assignments',
                  icon: Icons.account_tree,
                  color: Colors.blueGrey.shade600,
                  onClear: _clearSchoolDivisions,
                ),

                // Subjects
                _buildCategoryCard(
                  title: 'Subjects',
                  description: 'Remove subjects, class/teacher allocations and student scores',
                  icon: Icons.menu_book,
                  color: Colors.indigo.shade400,
                  onClear: _clearSubjects,
                ),

                // Activities
                _buildCategoryCard(
                  title: 'Activities',
                  description: 'Remove activities, class allocations and psychomotor/affective scores',
                  icon: Icons.directions_run,
                  color: Colors.orange.shade800,
                  onClear: _clearActivities,
                ),

                // Exams & Grading
                _buildCategoryCard(
                  title: 'Exams & Grading',
                  description: 'Remove exam definitions, grading scales, scores and result computations',
                  icon: Icons.grading,
                  color: Colors.deepPurple.shade400,
                  onClear: _clearExamsAndGrading,
                ),

                // Student Scores
                _buildCategoryCard(
                  title: 'Student Scores',
                  description: 'Clear all scores, psychomotor/affective assessments and result computations',
                  icon: Icons.score,
                  color: Colors.deepPurple.shade700,
                  onClear: _clearStudentScores,
                ),

                // Psychomotor & Affective Skills
                _buildCategoryCard(
                  title: 'Psychomotor & Affective Skills',
                  description: 'Remove skill/trait definitions and all student assessments',
                  icon: Icons.psychology,
                  color: Colors.purple.shade400,
                  onClear: _clearPsychomotorAffective,
                ),

                // Result Computations
                _buildCategoryCard(
                  title: 'Result Computations',
                  description: 'Clear computed result/report card data only',
                  icon: Icons.calculate,
                  color: Colors.purple.shade700,
                  onClear: _clearResultComputations,
                ),
                // ───────────────────────────────────────────────────────

                // Sessions & Terms
                _buildCategoryCard(
                  title: 'Sessions & Terms',
                  description: 'Reset sessions and terms to default (2024/2025)',
                  icon: Icons.calendar_month,
                  color: Colors.deepPurple,
                  onClear: _clearSessions,
                ),

                // Permissions
                _buildCategoryCard(
                  title: 'Permissions',
                  description: 'Reset all role permissions to defaults',
                  icon: Icons.admin_panel_settings,
                  color: Colors.red,
                  onClear: _resetPermissions,
                ),

                // Users
                _buildCategoryCard(
                  title: 'Users',
                  description: 'Reset all login accounts (keeps default admin)',
                  icon: Icons.manage_accounts,
                  color: Colors.red.shade400,
                  onClear: _clearUsers,
                ),

                // Licenses
                _buildCategoryCard(
                  title: 'Licenses',
                  description: 'Remove all license records (will require reactivation)',
                  icon: Icons.verified_user,
                  color: Colors.red.shade700,
                  onClear: _clearLicenses,
                ),

                const SizedBox(height: 20),
                const Divider(thickness: 2, color: Colors.red),
                const SizedBox(height: 20),

                // DANGER ZONE - Clear All
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade300, width: 2),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        '⚠️ DANGER ZONE ⚠️',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Clear ALL app data and reset to factory settings.\n'
                        'You will be logged out immediately.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.delete_forever, size: 28),
                        label: const Text(
                          'CLEAR ALL APP DATA',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                        onPressed: () async {
                          bool verified = await _verifyCode('Clear ALL App Data');
                          if (!verified) return;

                          bool confirm = await showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('⚠️ FINAL WARNING'),
                              content: const Text(
                                'This will DELETE EVERYTHING:\n\n'
                                '• All students, classes, arms\n'
                                '• All bills, payments, fees\n'
                                '• All stock, sales, debtors\n'
                                '• All expenses and reports\n'
                                '• All settings and preferences\n\n'
                                'THIS CANNOT BE UNDONE!\n\n'
                                'Continue?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('DELETE EVERYTHING'),
                                ),
                              ],
                            ),
                          ) ?? false;

                          if (confirm) await _clearAllAppData();
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
    );
  }
}
