// lib/widgets/student_quick_access_bar.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/database_helper_wrapper.dart';
import '../models/student.dart';
import '../screens/billing/bill_generate_screen.dart';
import '../screens/new_intake/items_given_screen.dart';
import '../screens/payments/payment_history_screen.dart';
import '../screens/payments/payment_record_screen.dart';
import '../screens/students/siblings_information_screen.dart';
import '../screens/students/student_details_screen.dart';
import '../screens/students/student_edit_screen.dart';
import '../utils/display_settings_helper.dart';
import '../utils/navigation_helper.dart';
import '../utils/permission_helper.dart';

/// Self-contained right-hand "Quick Access" panel for a single student.
///
/// Mirrors the bar shown on [StudentDetailsScreen] so the same jump-to
/// actions (Record Payment, Generate Bills, Payment History, Items Given,
/// Siblings, Dial Parent, Edit Student) are reachable from the screens those
/// actions open, without navigating back to the details page first. Fetches
/// its own student/siblings/permission data so callers only need to pass a
/// [studentId].
class StudentQuickAccessBar extends StatefulWidget {
  final int studentId;
  final String pageId;

  const StudentQuickAccessBar({
    super.key,
    required this.studentId,
    this.pageId = 'student_management/students',
  });

  @override
  State<StudentQuickAccessBar> createState() => _StudentQuickAccessBarState();
}

class _StudentQuickAccessBarState extends State<StudentQuickAccessBar> {
  Student? _student;
  List<Map<String, dynamic>> _siblings = [];
  Map<String, dynamic> _currentUser = {};
  bool _canManageStudents = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StudentQuickAccessBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };

    Student? student;
    List<Map<String, dynamic>> siblings = [];

    try {
      final db = await DatabaseHelperWrapper().database;
      final result = await db.rawQuery('''
        SELECT s.*, c.name as className, a.name as armName
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        WHERE s.id = ?
      ''', [widget.studentId]);

      if (result.isNotEmpty) {
        student = Student.fromMap(result.first);

        siblings = await db.rawQuery('''
          SELECT
            s.id, s.surname, s.firstName, s.otherName, s.admissionNo,
            s.gender, s.photoPath,
            c.name as className, a.name as armName
          FROM students s
          LEFT JOIN classes c ON s.classId = c.id
          LEFT JOIN arms a ON s.armId = a.id
          WHERE s.id != ?
            AND s.isActive = 1
            AND s.parentPhone IS NOT NULL
            AND s.parentPhone != ''
            AND s.parentPhone = ?
          ORDER BY s.surname, s.firstName
        ''', [student.id, student.parentPhone]);
      }
    } catch (_) {
      // Leave student null — the panel renders a "not found" placeholder.
    }

    final canManage = await PermissionHelper.hasPermission(currentUser, 'students_manage');

    if (!mounted) return;
    setState(() {
      _student = student;
      _siblings = siblings;
      _currentUser = currentUser;
      _canManageStudents = canManage;
      _loading = false;
    });
  }

  Future<void> _dialPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open dialer')),
      );
    }
  }

  void _openStudentDetails() {
    final student = _student;
    if (student == null) return;
    NavigationHelper.pushWithSidebar(
      context,
      page: StudentDetailsScreen(student: student),
      currentUser: _currentUser,
      pageId: widget.pageId,
    );
  }

  void _openRecordPayment() {
    final student = _student;
    if (student == null) return;
    NavigationHelper.pushWithSidebar(
      context,
      page: PaymentRecordScreen(
        studentId: student.id!,
        studentName: "${student.surname} ${student.firstName}",
      ),
      currentUser: _currentUser,
      pageId: widget.pageId,
    );
  }

  void _openGenerateBill() {
    final student = _student;
    if (student == null) return;
    NavigationHelper.pushWithSidebar(
      context,
      page: BillGenerateScreen(
        studentId: student.id!,
        studentName: "${student.surname} ${student.firstName}",
        isSibling: _siblings.isNotEmpty,
      ),
      currentUser: _currentUser,
      pageId: widget.pageId,
    );
  }

  void _openPaymentHistory() {
    final student = _student;
    if (student == null) return;
    NavigationHelper.pushWithSidebar(
      context,
      page: PaymentHistoryScreen(
        studentId: student.id!,
        studentName: "${student.surname} ${student.firstName}",
      ),
      currentUser: _currentUser,
      pageId: widget.pageId,
    );
  }

  void _openItemsGiven() {
    final student = _student;
    if (student == null) return;
    NavigationHelper.pushWithSidebar(
      context,
      page: ItemsGivenScreen(
        studentId: student.id!,
        studentName: "${student.surname} ${student.firstName}",
      ),
      currentUser: _currentUser,
      pageId: widget.pageId,
    );
  }

  void _openSiblingsInformation() {
    final student = _student;
    if (student == null) return;

    final allSiblings = [
      {
        'id': student.id,
        'surname': student.surname,
        'firstName': student.firstName,
        'otherName': student.otherName,
        'gender': student.gender,
        'className': student.className,
        'armName': student.armName,
        'parentPhone': student.parentPhone,
        'parentName': student.parentName,
      },
      ..._siblings.map((s) => Map<String, dynamic>.from(s)),
    ];

    final siblingGroup = {
      'parentPhone': student.parentPhone,
      'parentName': student.parentName,
      'students': allSiblings,
    };

    NavigationHelper.pushWithSidebar(
      context,
      page: SiblingsInformationScreen(
        siblingGroup: siblingGroup,
        groupColor: Colors.purple,
      ),
      currentUser: _currentUser,
      pageId: widget.pageId,
    );
  }

  void _openEditStudent() {
    final student = _student;
    if (student == null) return;
    NavigationHelper.pushWithSidebar(
      context,
      page: StudentEditScreen(student: student),
      currentUser: _currentUser,
      pageId: widget.pageId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = DisplaySettingsProvider.of(context);
    final student = _student;
    final hasParentPhone = student != null && student.parentPhone.trim().isNotEmpty;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(ds.cardPadding * 0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: ds.cardPadding * 0.25,
                bottom: ds.cardPadding * 0.5,
              ),
              child: Text(
                'Quick Access',
                style: TextStyle(
                  fontSize: ds.titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            if (_loading)
              Padding(
                padding: EdgeInsets.all(ds.cardPadding),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (student == null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.25),
                child: Text(
                  'Student not found',
                  style: TextStyle(fontSize: ds.bodyFontSize, color: Colors.grey.shade600),
                ),
              )
            else ...[
              _tile(
                ds,
                icon: Icons.receipt_long,
                color: Colors.teal,
                label: 'Go to Bills & Payments',
                onTap: _openStudentDetails,
              ),
              _tile(
                ds,
                icon: Icons.payment,
                color: Colors.green,
                label: 'Record Payment',
                onTap: _openRecordPayment,
              ),
              _tile(
                ds,
                icon: Icons.request_quote,
                color: Colors.blue,
                label: 'Generate Bills',
                onTap: _openGenerateBill,
              ),
              _tile(
                ds,
                icon: Icons.history,
                color: Colors.deepPurple,
                label: 'Payment History',
                onTap: _openPaymentHistory,
              ),
              _tile(
                ds,
                icon: Icons.inventory_2_outlined,
                color: Colors.cyan.shade700,
                label: 'Items Given',
                onTap: _openItemsGiven,
              ),
              if (_siblings.isNotEmpty)
                _tile(
                  ds,
                  icon: Icons.family_restroom,
                  color: Colors.purple,
                  label: 'View Siblings Information',
                  subtitle: '${_siblings.length} sibling${_siblings.length == 1 ? '' : 's'}',
                  onTap: _openSiblingsInformation,
                ),
              if (hasParentPhone)
                _tile(
                  ds,
                  icon: Icons.call,
                  color: Colors.green.shade700,
                  label: 'Dial Parent',
                  subtitle: student.parentPhone,
                  onTap: () => _dialPhone(student.parentPhone),
                ),
              if (_canManageStudents)
                _tile(
                  ds,
                  icon: Icons.edit,
                  color: Colors.orange.shade800,
                  label: "Edit Student's Information",
                  onTap: _openEditStudent,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(
    DisplaySettings ds, {
    required IconData icon,
    required Color color,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: ds.cardPadding * 0.5),
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ds.cardPadding * 0.6,
              vertical: ds.cardPadding * 0.6,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ds.cardPadding * 0.4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: ds.iconSize * 0.9, color: Colors.white),
                ),
                SizedBox(width: ds.cardPadding * 0.6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: ds.bodyFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: ds.bodyFontSize * 0.85,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the current screen is wide enough to show [StudentQuickAccessBar]
/// (matches the large-screen rule used across the app: shortest side >= 700).
bool shouldShowStudentQuickAccessBar(BuildContext context) {
  return MediaQuery.of(context).size.shortestSide >= 700;
}
