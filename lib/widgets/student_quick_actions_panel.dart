// lib/widgets/student_quick_actions_panel.dart
//
// Shared "Quick Actions" panel for the student-management screens. Shows as
// a right-hand side panel on large screens (shortest side >= 700, the same
// breakpoint the app's own sidebar uses) and as an end drawer on phones.
//
// Used by the student list screen and the 7 screens it links to, so the
// same set of shortcuts is reachable from anywhere in the module without
// going back to the list each time.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/students/student_form_screen.dart';
import '../screens/students/batch_student_upload_screen.dart';
import '../screens/students/new_students_screen.dart';
import '../screens/students/student_promotion_screen.dart';
import '../screens/students/deactivate_student_screen.dart';
import '../screens/students/inactive_students_screen.dart';
import '../screens/students/siblings_screen.dart';
import '../utils/permission_helper.dart';
import '../utils/display_settings_helper.dart';
import '../utils/navigation_helper.dart';

/// Identifies which screen is hosting the panel, so that screen's own
/// shortcut can be left out of its list.
enum StudentQuickAction {
  studentList,
  register,
  batchUpload,
  newStudents,
  promote,
  deactivate,
  inactive,
  siblings,
}

/// Static helpers for wiring [StudentQuickActionsPanel] into a screen's
/// [Scaffold] with the standard side-panel/drawer breakpoint.
class StudentQuickAccess {
  StudentQuickAccess._();

  static bool showSidePanel(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 700;

  /// Wraps [body] with the side panel on large screens; returns [body]
  /// unchanged on phones (pair with [buildEndDrawer] for the phone case).
  static Widget wrapBody(
    BuildContext context, {
    required Widget body,
    required StudentQuickAction current,
    VoidCallback? onReturn,
  }) {
    if (!showSidePanel(context)) return body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        Container(
          width: 220,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(left: BorderSide(color: Colors.grey.shade300)),
          ),
          child: SingleChildScrollView(
            child: StudentQuickActionsPanel(current: current, onReturn: onReturn),
          ),
        ),
      ],
    );
  }

  /// Returns the drawer to register as the host [Scaffold]'s `endDrawer` on
  /// phones (Flutter adds the AppBar toggle icon automatically); `null` on
  /// large screens, where the panel is already inline via [wrapBody].
  static Widget? buildEndDrawer(
    BuildContext context, {
    required StudentQuickAction current,
    VoidCallback? onReturn,
  }) {
    if (showSidePanel(context)) return null;
    return Drawer(
      child: SafeArea(
        child: SingleChildScrollView(
          child: StudentQuickActionsPanel(current: current, onReturn: onReturn),
        ),
      ),
    );
  }
}

class StudentQuickActionsPanel extends StatefulWidget {
  final StudentQuickAction current;
  final VoidCallback? onReturn;

  const StudentQuickActionsPanel({super.key, required this.current, this.onReturn});

  @override
  State<StudentQuickActionsPanel> createState() => _StudentQuickActionsPanelState();
}

class _StudentQuickActionsPanelState extends State<StudentQuickActionsPanel> {
  Map<String, dynamic> _currentUser = {};
  bool _canManageStudents = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };
    final canManage = await PermissionHelper.hasPermission(currentUser, 'students_manage');
    if (mounted) {
      setState(() {
        _currentUser = currentUser;
        _canManageStudents = canManage;
        _ready = true;
      });
    }
  }

  Future<void> _open(Widget page, String pageId) async {
    await NavigationHelper.pushWithSidebar(
      context,
      page: page,
      currentUser: _currentUser,
      pageId: pageId,
    );
    if (mounted) widget.onReturn?.call();
  }

  Widget _button({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required DisplaySettings ds,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: ds.cardPadding * 0.5),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: ds.iconSize * 0.85),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(fontSize: ds.bodyFontSize, fontWeight: FontWeight.w600),
          ),
        ),
        style: ElevatedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size.fromHeight(0),
          padding: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.75, vertical: ds.cardPadding * 0.8),
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    final current = widget.current;

    if (!_ready) {
      return Padding(
        padding: EdgeInsets.all(ds.cardPadding),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final buttons = <Widget>[];

    if (_canManageStudents && current != StudentQuickAction.register) {
      buttons.add(_button(
        label: 'Register',
        icon: Icons.person_add,
        color: Colors.green,
        ds: ds,
        onTap: () => _open(const StudentFormScreen(), 'student_management/students'),
      ));
    }

    if (_canManageStudents && current != StudentQuickAction.batchUpload) {
      buttons.add(_button(
        label: 'Batch Upload',
        icon: Icons.upload_file,
        color: Colors.orange,
        ds: ds,
        onTap: () => _open(const BatchStudentUploadScreen(), 'student_management/students'),
      ));
    }

    if (current != StudentQuickAction.newStudents) {
      buttons.add(_button(
        label: 'View New Students',
        icon: Icons.person_add_outlined,
        color: Colors.teal,
        ds: ds,
        onTap: () => _open(const NewStudentsScreen(), 'student_management/new_students'),
      ));
    }

    if (_canManageStudents && current != StudentQuickAction.promote) {
      buttons.add(_button(
        label: 'Promote Students',
        icon: Icons.arrow_upward_outlined,
        color: Colors.deepPurple,
        ds: ds,
        onTap: () => _open(const StudentPromotionScreen(), 'student_management/promote'),
      ));
    }

    if (_canManageStudents && current != StudentQuickAction.deactivate) {
      buttons.add(_button(
        label: 'Deactivate Student',
        icon: Icons.person_remove_outlined,
        color: Colors.redAccent,
        ds: ds,
        onTap: () => _open(const DeactivateStudentScreen(), 'student_management/deactivate'),
      ));
    }

    if (_canManageStudents && current != StudentQuickAction.inactive) {
      buttons.add(_button(
        label: 'Inactive Students',
        icon: Icons.archive_outlined,
        color: Colors.blueGrey,
        ds: ds,
        onTap: () => _open(const InactiveStudentsScreen(), 'student_management/inactive'),
      ));
    }

    if (current != StudentQuickAction.siblings) {
      buttons.add(_button(
        label: 'Siblings',
        icon: Icons.family_restroom_outlined,
        color: Colors.cyan.shade700,
        ds: ds,
        onTap: () => _open(const SiblingsScreen(), 'student_management/siblings'),
      ));
    }

    return Padding(
      padding: EdgeInsets.all(ds.cardPadding * 0.75),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: ds.cardPadding * 0.5, left: ds.cardPadding * 0.25),
            child: Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: ds.subtitleFontSize,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (buttons.isEmpty)
            Padding(
              padding: EdgeInsets.only(left: ds.cardPadding * 0.25),
              child: Text(
                'No other actions available',
                style: TextStyle(fontSize: ds.subtitleFontSize, color: Colors.grey.shade500),
              ),
            ),
          ...buttons,
        ],
      ),
    );
  }
}
