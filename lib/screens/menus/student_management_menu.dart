// lib/screens/menus/student_management_menu.dart
import 'package:flutter/material.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/permission_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../students/student_list_screen.dart';
import '../students/new_students_screen.dart';
import '../students/student_promotion_screen.dart';
import '../students/deactivate_student_screen.dart';
import '../students/inactive_students_screen.dart';
import '../students/siblings_screen.dart';
import '../reports/debtors_list_screen.dart';
import '../billing/class_bills_screen.dart';

class StudentManagementMenu extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const StudentManagementMenu({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Management'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: GridView.extent(
        maxCrossAxisExtent: context.gridMaxExtent,
        padding: EdgeInsets.all(ds.cardPadding),
        crossAxisSpacing: ds.cardPadding,
        mainAxisSpacing: ds.cardPadding,
        childAspectRatio: context.gridChildAspectRatio,
        children: [
          _permissionMenuCard(
            context,
            module: 'students_manage',
            title: 'Students',
            subtitle: 'Manage students',
            icon: Icons.person_outline,
            color: Colors.green,
            page: const StudentListScreen(),
            pageId: 'student_management/students',
          ),
          _permissionMenuCard(
            context,
            module: 'students_view',
            title: 'View New Students',
            subtitle: 'Current term registrations',
            icon: Icons.person_add_outlined,
            color: Colors.teal,
            page: const NewStudentsScreen(),
            pageId: 'student_management/new_students',
          ),
          _permissionMenuCard(
            context,
            module: 'students_manage',
            title: 'Promote Students',
            subtitle: 'Move to next class',
            icon: Icons.arrow_upward_outlined,
            color: Colors.deepPurple,
            page: const StudentPromotionScreen(),
            pageId: 'student_management/promote',
          ),
          _permissionMenuCard(
            context,
            module: 'students_manage',
            title: 'Deactivate Student',
            subtitle: 'Archive students',
            icon: Icons.person_remove_outlined,
            color: Colors.orange,
            page: const DeactivateStudentScreen(),
            pageId: 'student_management/deactivate',
          ),
          _permissionMenuCard(
            context,
            module: 'students_manage',
            title: 'Inactive Students',
            subtitle: 'View archived',
            icon: Icons.archive_outlined,
            color: Colors.blueGrey,
            page: const InactiveStudentsScreen(),
            pageId: 'student_management/inactive',
          ),
          _permissionMenuCard(
            context,
            module: 'students_view',
            title: 'Siblings',
            subtitle: 'Students with mutual parent',
            icon: Icons.family_restroom_outlined,
            color: Colors.cyan,
            page: const SiblingsScreen(),
            pageId: 'student_management/siblings',
          ),
          _permissionMenuCard(
            context,
            module: 'debtors_report',
            title: 'Debtors',
            subtitle: 'Outstanding fees',
            icon: Icons.warning_amber_outlined,
            color: Colors.red,
            page: const DebtorsListScreen(),
            pageId: 'student_management/debtors',
          ),
          _permissionMenuCard(
            context,
            module: 'bills_generate',
            title: 'Class Bills',
            subtitle: 'Student bill overview',
            icon: Icons.receipt_long_outlined,
            color: Colors.indigo,
            page: const ClassBillsScreen(),
            pageId: 'student_management/class_bills',
          ),
        ],
      ),
    );
  }

  Widget _menuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget page,
    String? pageId,
  }) {
    final ds = DisplaySettingsProvider.of(context);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final screenSize = MediaQuery.of(context).size;
          final showSidebar = screenSize.shortestSide >= 700;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => showSidebar
                  ? SidebarScaffold(
                      currentUser: currentUser,
                      currentPageId: pageId,
                      child: page,
                    )
                  : page,
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.all(ds.cardPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(ds.cardPadding),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: ds.iconSize * 1.6,
                  color: color,
                ),
              ),
              SizedBox(height: ds.cardPadding * 0.75),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: ds.titleFontSize * 0.85,
                ),
              ),
              SizedBox(height: ds.cardPadding * 0.25),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ds.subtitleFontSize,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionMenuCard(
    BuildContext context, {
    required String module,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget page,
    String? pageId,
  }) {
    return FutureBuilder<bool>(
      future: PermissionHelper.hasPermission(currentUser, module),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'Error loading $title',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.data != true) {
          return const SizedBox.shrink();
        }

        return _menuCard(
          context,
          title: title,
          subtitle: subtitle,
          icon: icon,
          color: color,
          page: page,
          pageId: pageId,
        );
      },
    );
  }
}
