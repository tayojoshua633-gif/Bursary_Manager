// lib/screens/menus/staff_setup_menu.dart
import 'package:flutter/material.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/permission_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../staff/staff_setup/staff_register_screen.dart';
import '../staff/staff_setup/staff_photo_capture_screen.dart';
import '../staff/staff_setup/staff_offices_screen.dart';
import '../staff/staff_setup/class_allocation_screen.dart';
import '../staff/staff_setup/office_allocation_screen.dart';
import '../staff/staff_setup/staff_salary_screen.dart';

class StaffSetupMenu extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const StaffSetupMenu({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Setup'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: GridView.extent(
          maxCrossAxisExtent: context.gridMaxExtent,
          crossAxisSpacing: ds.cardPadding,
          mainAxisSpacing: ds.cardPadding,
          childAspectRatio: context.gridChildAspectRatio,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _permissionMenuCard(
              context,
              module: 'staff_add',
              title: 'Register Staff',
              subtitle: 'Add new staff member',
              icon: Icons.person_add,
              color: Colors.indigo,
              page: const StaffRegisterScreen(),
              pageId: 'staff_management/staff_setup/register',
            ),
            _permissionMenuCard(
              context,
              module: 'staff_add',
              title: 'Photo Capture',
              subtitle: 'Capture staff photos',
              icon: Icons.camera_alt,
              color: Colors.deepPurple,
              page: const StaffPhotoCaptureScreen(),
              pageId: 'staff_management/staff_setup/photo',
            ),
            _permissionMenuCard(
              context,
              module: 'staff_offices',
              title: 'Staff Offices',
              subtitle: 'Manage offices',
              icon: Icons.business,
              color: Colors.teal,
              page: const StaffOfficesScreen(),
              pageId: 'staff_management/staff_setup/offices',
            ),
            _permissionMenuCard(
              context,
              module: 'staff_class_allocation',
              title: 'Class Allocation',
              subtitle: 'Assign teachers to classes',
              icon: Icons.class_,
              color: Colors.deepPurple,
              page: const ClassAllocationScreen(),
              pageId: 'staff_management/staff_setup/class_allocation',
            ),
            _permissionMenuCard(
              context,
              module: 'staff_office_allocation',
              title: 'Office Allocation',
              subtitle: 'Assign staff to offices',
              icon: Icons.meeting_room,
              color: Colors.orange,
              page: const OfficeAllocationScreen(),
              pageId: 'staff_management/staff_setup/office_allocation',
            ),
            _permissionMenuCard(
              context,
              module: 'staff_salary',
              title: 'Staff Salary',
              subtitle: 'Set staff salaries',
              icon: Icons.payments,
              color: Colors.green,
              page: const StaffSalaryScreen(),
              pageId: 'staff_management/staff_setup/salary',
            ),
          ],
        ),
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
              child: const Center(child: CircularProgressIndicator()),
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
