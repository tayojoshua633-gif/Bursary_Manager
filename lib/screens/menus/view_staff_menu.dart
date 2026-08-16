// lib/screens/menus/view_staff_menu.dart
import 'package:flutter/material.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/permission_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../staff/staff_view/staff_list_screen.dart';
import '../staff/staff_view/staff_table_screen.dart';
import '../staff/staff_payroll/staff_incentive_screen.dart';
import '../staff/staff_payroll/staff_loan_screen.dart';
import '../staff/staff_payroll/staff_deduction_screen.dart';
import '../staff/staff_payroll/staff_payroll_screen.dart';
import '../staff/staff_payroll/salary_payment_record_screen.dart';
import '../staff/staff_view/staff_deactivate_screen.dart';
import '../staff/staff_payroll/salary_increment_screen.dart';

class ViewStaffMenu extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const ViewStaffMenu({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('View Staff'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Staff Directory Section
            _sectionHeader('Staff Directory'),
            const SizedBox(height: 12),
            GridView.extent(
              maxCrossAxisExtent: context.gridMaxExtent,
              crossAxisSpacing: ds.cardPadding,
              mainAxisSpacing: ds.cardPadding,
              childAspectRatio: context.gridChildAspectRatio,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _permissionMenuCard(
                  context,
                  module: 'staff_view',
                  title: 'Staff List',
                  subtitle: 'View all staff',
                  icon: Icons.people,
                  color: Colors.blue,
                  page: StaffListScreen(currentUser: currentUser),
                  pageId: 'staff_management/view_staff/list',
                ),
                _permissionMenuCard(
                  context,
                  module: 'staff_listing',
                  title: 'Staff Listing',
                  subtitle: 'Table view',
                  icon: Icons.table_chart,
                  color: Colors.blueGrey,
                  page: const StaffTableScreen(),
                  pageId: 'staff_management/view_staff/table',
                ),
                _permissionMenuCard(
                  context,
                  module: 'staff_view',
                  title: 'Deactivate Staff',
                  subtitle: 'Manage active/inactive staff',
                  icon: Icons.person_off,
                  color: Colors.red,
                  page: const StaffDeactivateScreen(),
                  pageId: 'staff_management/view_staff/deactivate',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Payroll Management Section
            _sectionHeader('Payroll Management'),
            const SizedBox(height: 12),
            GridView.extent(
              maxCrossAxisExtent: context.gridMaxExtent,
              crossAxisSpacing: ds.cardPadding,
              mainAxisSpacing: ds.cardPadding,
              childAspectRatio: context.gridChildAspectRatio,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _permissionMenuCard(
                  context,
                  module: 'staff_incentive',
                  title: 'Staff Incentive',
                  subtitle: 'Monthly incentives/grants',
                  icon: Icons.card_giftcard,
                  color: Colors.green,
                  page: const StaffIncentiveScreen(),
                  pageId: 'staff_management/view_staff/incentive',
                ),
                _permissionMenuCard(
                  context,
                  module: 'staff_loan',
                  title: 'Staff Loan',
                  subtitle: 'Loan records',
                  icon: Icons.account_balance_wallet,
                  color: Colors.orange,
                  page: StaffLoanScreen(currentUser: currentUser),
                  pageId: 'staff_management/view_staff/loan',
                ),
                _permissionMenuCard(
                  context,
                  module: 'staff_deduction',
                  title: 'Penalty/Deduction',
                  subtitle: 'Salary deductions',
                  icon: Icons.remove_circle,
                  color: Colors.red,
                  page: const StaffDeductionScreen(),
                  pageId: 'staff_management/view_staff/deduction',
                ),
                _permissionMenuCard(
                  context,
                  module: 'staff_payroll',
                  title: 'Staff Salary',
                  subtitle: 'View payroll & export',
                  icon: Icons.receipt_long,
                  color: Colors.purple,
                  page: const StaffPayrollScreen(),
                  pageId: 'staff_management/view_staff/payroll',
                ),
                _permissionMenuCard(
                  context,
                  module: 'staff_payroll',
                  title: 'Payment Record',
                  subtitle: 'Salary payment history',
                  icon: Icons.history,
                  color: Colors.teal,
                  page: SalaryPaymentRecordScreen(currentUser: currentUser),
                  pageId: 'staff_management/view_staff/payment_record',
                ),
                _permissionMenuCard(
                  context,
                  module: 'staff_payroll',
                  title: 'Salary Increment',
                  subtitle: 'Record salary changes',
                  icon: Icons.trending_up,
                  color: Colors.amber,
                  page: const SalaryIncrementScreen(),
                  pageId: 'staff_management/view_staff/salary_increment',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
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
