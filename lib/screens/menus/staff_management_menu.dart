// lib/screens/menus/staff_management_menu.dart
import 'package:flutter/material.dart';
import '../../utils/display_settings_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import 'staff_setup_menu.dart';
import 'view_staff_menu.dart';

class StaffManagementMenu extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const StaffManagementMenu({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Management'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.indigo.shade400,
                    Colors.indigo.shade700,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.groups,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Staff Management',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage your staff records, offices, allocations, and payroll',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Main Menu Grid
            GridView.extent(
              maxCrossAxisExtent: context.gridMaxExtent * 1.5,
              crossAxisSpacing: ds.cardPadding,
              mainAxisSpacing: ds.cardPadding,
              childAspectRatio: 1.2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _mainMenuCard(
                  context,
                  title: 'Staff Setup',
                  subtitle: 'Register staff, manage offices, allocations & salaries',
                  icon: Icons.settings,
                  color: Colors.indigo,
                  items: [
                    'Register Staff',
                    'Staff Offices',
                    'Class Allocation',
                    'Office Allocation',
                    'Staff Salary Setup',
                  ],
                  page: StaffSetupMenu(currentUser: currentUser),
                  pageId: 'staff_management/setup',
                ),
                _mainMenuCard(
                  context,
                  title: 'View Staff',
                  subtitle: 'View staff directory, incentives, loans & payroll',
                  icon: Icons.people,
                  color: Colors.blue,
                  items: [
                    'Staff List',
                    'Staff Incentive/Grant',
                    'Staff Loan',
                    'Penalty/Deduction',
                    'Staff Payroll',
                  ],
                  page: ViewStaffMenu(currentUser: currentUser),
                  pageId: 'staff_management/view',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mainMenuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<String> items,
    required Widget page,
    String? pageId,
  }) {
    final ds = DisplaySettingsProvider.of(context);

    return Card(
      elevation: 4,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(ds.cardPadding * 0.75),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: ds.iconSize * 1.4,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: ds.titleFontSize,
                            color: color,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: ds.subtitleFontSize * 0.9,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: items
                      .map((item) => Chip(
                            label: Text(
                              item,
                              style: TextStyle(
                                fontSize: ds.subtitleFontSize * 0.85,
                                color: color,
                              ),
                            ),
                            backgroundColor: color.withValues(alpha: 0.1),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
