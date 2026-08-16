// lib/screens/menus/reports_menu.dart
import 'package:flutter/material.dart';
import '../../utils/permission_helper.dart';
import '../../utils/display_settings_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../reports/daily_report_screen.dart';
import '../reports/termly_report_screen.dart';
import '../reports/sales_report_screen.dart';
import '../reports/daily_print_count_screen.dart';
import '../reports/custom_report_screen.dart';
import '../reports/activity_log_screen.dart';
import '../reports/fees_balance_report_screen.dart';

class ReportsMenu extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const ReportsMenu({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: Colors.deepOrange,
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
            module: 'daily_report',
            title: 'Daily Report',
            subtitle: 'Daily payment summary',
            icon: Icons.today_outlined,
            color: Colors.blue,
            page: const DailyReportScreen(),
            pageId: 'reports/daily',
          ),
          _permissionMenuCard(
            context,
            module: 'custom_report',
            title: 'Custom Report',
            subtitle: 'Weekly, monthly or custom range',
            icon: Icons.date_range_outlined,
            color: Colors.teal,
            page: const CustomReportScreen(),
            pageId: 'reports/custom',
          ),
          _permissionMenuCard(
            context,
            module: 'termly_report',
            title: 'Termly Report',
            subtitle: 'Term-wise analysis',
            icon: Icons.calendar_month_outlined,
            color: Colors.purple,
            page: const TermlyReportScreen(),
            pageId: 'reports/termly',
          ),
          _permissionMenuCard(
            context,
            module: 'sales_report',
            title: 'Sales Report',
            subtitle: 'Daily sales summary',
            icon: Icons.analytics_outlined,
            color: Colors.deepOrange,
            page: const SalesReportScreen(),
            pageId: 'reports/sales',
          ),
          _permissionMenuCard(
            context,
            module: 'daily_print_count',
            title: 'Daily Print Count',
            subtitle: 'Track print statistics',
            icon: Icons.print_outlined,
            color: Colors.teal,
            page: const DailyPrintCountScreen(),
            pageId: 'reports/print_count',
          ),
          _permissionMenuCard(
            context,
            module: 'audit_log_view',
            title: 'Activity Log',
            subtitle: 'Payment create/edit/delete trail',
            icon: Icons.history_outlined,
            color: Colors.indigo,
            page: const ActivityLogScreen(),
            pageId: 'reports/activity-log',
          ),
          _permissionMenuCard(
            context,
            module: 'reports_fees_balance',
            title: 'School Fees Balance Report',
            subtitle: 'Balanced vs owing, term & session comparison',
            icon: Icons.fact_check_outlined,
            color: Colors.green,
            page: const FeesBalanceReportScreen(),
            pageId: 'reports/fees-balance',
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
