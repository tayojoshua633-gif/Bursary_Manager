// lib/navigation/menu_data.dart
import 'package:flutter/material.dart';

// Screen imports
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/school_profile/school_profile_screen.dart';
import '../screens/classes/class_list_screen.dart';
import '../screens/sessions/session_term_management_screen.dart';
import '../screens/students/student_list_screen.dart';
import '../screens/students/new_students_screen.dart';
import '../screens/students/student_promotion_screen.dart';
import '../screens/students/deactivate_student_screen.dart';
import '../screens/students/inactive_students_screen.dart';
import '../screens/students/siblings_screen.dart';
import '../screens/reports/debtors_list_screen.dart';
import '../screens/billing/class_bills_screen.dart';
import '../screens/billing/view_term_bills_screen.dart';
import '../screens/parents/all_parents_screen.dart';
import '../screens/fees/fee_item_list_screen.dart';
import '../screens/billing/bill_student_select_screen.dart';
import '../screens/payments/payment_student_select_screen.dart';
import '../screens/reports/overpayment_tracker_screen.dart';
import '../screens/reports/daily_report_screen.dart';
import '../screens/reports/termly_report_screen.dart';
import '../screens/reports/sales_report_screen.dart';
import '../screens/reports/daily_print_count_screen.dart';
import '../screens/reports/custom_report_screen.dart';
import '../screens/reports/activity_log_screen.dart';
import '../screens/stock/stock_item_list_screen.dart';
import '../screens/stock/supplier_list_screen.dart';
import '../screens/stock/purchase_history_screen.dart';
import '../screens/sales/buyer_selection_screen.dart';
import '../screens/reports/stock_record_report_screen.dart';
import '../screens/expenses/expense_form_screen.dart';
import '../screens/expenses/expense_list_screen.dart';
import '../screens/staff/staff_setup/staff_register_screen.dart';
import '../screens/staff/staff_setup/staff_offices_screen.dart';
import '../screens/staff/staff_setup/class_allocation_screen.dart';
import '../screens/staff/staff_setup/office_allocation_screen.dart';
import '../screens/staff/staff_setup/staff_salary_screen.dart';
import '../screens/staff/staff_view/staff_list_screen.dart';
import '../screens/staff/staff_payroll/staff_incentive_screen.dart';
import '../screens/staff/staff_payroll/staff_loan_screen.dart';
import '../screens/staff/staff_payroll/staff_deduction_screen.dart';
import '../screens/staff/staff_payroll/staff_payroll_screen.dart';
import '../screens/backup/backup_screen.dart';
import '../screens/license/license_management_screen.dart';
import '../screens/settings/thermal_printer_screen.dart';
import '../screens/settings/display_settings_screen.dart';
import '../screens/settings/security_settings_screen.dart';
import '../screens/settings/clear_data_screen.dart';
import '../screens/permissions/permission_management_screen.dart';
import '../screens/auth/user_management_screen.dart';
import '../screens/new_intake/special_fee_items_screen.dart';
import '../screens/new_intake/view_new_intake_bills_screen.dart';
import '../screens/billing/last_term_debtors_screen.dart';

// Menu screen imports for collapsed sidebar navigation
import '../screens/menus/school_management_menu.dart';
import '../screens/menus/student_management_menu.dart';
import '../screens/menus/parents_management_menu.dart';
import '../screens/menus/bills_payment_menu.dart';
import '../screens/menus/transportation_menu.dart';
import '../screens/transportation/route_list_screen.dart';
import '../screens/transportation/transport_student_select_screen.dart';
import '../screens/transportation/route_students_screen.dart';
import '../screens/fee_tracker/set_bill_priority_screen.dart';
import '../screens/fee_tracker/track_fee_item_screen.dart';
import '../screens/fee_tracker/payment_progression_screen.dart';
import '../screens/menus/reports_menu.dart';
import '../screens/menus/stock_sales_menu.dart';
import '../screens/menus/expenditure_menu.dart';
import '../screens/menus/staff_management_menu.dart';
import '../screens/menus/preferences_menu.dart';
import '../screens/web/web_view_screen.dart';

/// Represents a single menu item in the sidebar
class SidebarMenuItem {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final String? permissionModule;
  final Widget Function(Map<String, dynamic> currentUser)? pageBuilder;
  final List<SidebarMenuItem> children;
  final bool isSuperAdminOnly;

  const SidebarMenuItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    this.permissionModule,
    this.pageBuilder,
    this.children = const [],
    this.isSuperAdminOnly = false,
  });

  bool get hasChildren => children.isNotEmpty;
  bool get isLeaf => children.isEmpty && pageBuilder != null;
}

/// Complete menu hierarchy
class MenuData {
  static List<SidebarMenuItem> getMenuItems() => [
        // Dashboard - Direct leaf
        SidebarMenuItem(
          id: 'dashboard',
          title: 'Dashboard',
          icon: Icons.dashboard_outlined,
          color: Colors.blue,
          pageBuilder: (_) => const DashboardScreen(),
        ),

        // Updates
        SidebarMenuItem(
          id: 'updates',
          title: 'Updates',
          icon: Icons.system_update_outlined,
          color: Colors.cyan,
          pageBuilder: (_) => const WebViewScreen(
            url: 'https://tysolutions.com.ng/apps/bursary-manager.html',
            title: 'Updates',
          ),
        ),

        // School Management
        SidebarMenuItem(
          id: 'school_management',
          title: 'School Management',
          icon: Icons.account_balance_outlined,
          color: Colors.deepPurple,
          pageBuilder: (user) => SchoolManagementMenu(currentUser: user),
          children: [
            SidebarMenuItem(
              id: 'school_management/profile',
              title: 'School Profile',
              icon: Icons.business,
              color: Colors.deepPurple,
              permissionModule: 'school_profile',
              pageBuilder: (_) => const SchoolProfileScreen(),
            ),
            SidebarMenuItem(
              id: 'school_management/classes',
              title: 'Classes & Arms',
              icon: Icons.class_outlined,
              color: Colors.deepPurple,
              permissionModule: 'classes_manage',
              pageBuilder: (_) => const ClassListScreen(),
            ),
            SidebarMenuItem(
              id: 'school_management/sessions',
              title: 'Session & Term',
              icon: Icons.calendar_today_outlined,
              color: Colors.deepPurple,
              permissionModule: 'session_term',
              pageBuilder: (_) => const SessionTermManagementScreen(),
            ),
          ],
        ),

        // Student Management
        SidebarMenuItem(
          id: 'student_management',
          title: 'Student Management',
          icon: Icons.people_outlined,
          color: Colors.green,
          pageBuilder: (user) => StudentManagementMenu(currentUser: user),
          children: [
            SidebarMenuItem(
              id: 'student_management/students',
              title: 'Students',
              icon: Icons.person_outline,
              color: Colors.green,
              permissionModule: 'students_manage',
              pageBuilder: (_) => const StudentListScreen(),
            ),
            SidebarMenuItem(
              id: 'student_management/new_students',
              title: 'View New Students',
              icon: Icons.person_add_outlined,
              color: Colors.teal,
              permissionModule: 'students_view',
              pageBuilder: (_) => const NewStudentsScreen(),
            ),
            SidebarMenuItem(
              id: 'student_management/promote',
              title: 'Promote Students',
              icon: Icons.arrow_upward_outlined,
              color: Colors.deepPurple,
              permissionModule: 'students_manage',
              pageBuilder: (_) => const StudentPromotionScreen(),
            ),
            SidebarMenuItem(
              id: 'student_management/deactivate',
              title: 'Deactivate Student',
              icon: Icons.person_remove_outlined,
              color: Colors.orange,
              permissionModule: 'students_manage',
              pageBuilder: (_) => const DeactivateStudentScreen(),
            ),
            SidebarMenuItem(
              id: 'student_management/inactive',
              title: 'Inactive Students',
              icon: Icons.archive_outlined,
              color: Colors.blueGrey,
              permissionModule: 'students_manage',
              pageBuilder: (_) => const InactiveStudentsScreen(),
            ),
            SidebarMenuItem(
              id: 'student_management/siblings',
              title: 'Siblings',
              icon: Icons.family_restroom_outlined,
              color: Colors.cyan,
              permissionModule: 'students_view',
              pageBuilder: (_) => const SiblingsScreen(),
            ),
            SidebarMenuItem(
              id: 'student_management/debtors',
              title: 'Debtors',
              icon: Icons.warning_amber_outlined,
              color: Colors.red,
              permissionModule: 'debtors_report',
              pageBuilder: (_) => const DebtorsListScreen(),
            ),
            SidebarMenuItem(
              id: 'student_management/class_bills',
              title: 'Class Bills',
              icon: Icons.receipt_long_outlined,
              color: Colors.indigo,
              permissionModule: 'bills_generate',
              pageBuilder: (_) => const ClassBillsScreen(),
            ),
          ],
        ),

        // Parents Management
        SidebarMenuItem(
          id: 'parents_management',
          title: 'Parents Management',
          icon: Icons.family_restroom_outlined,
          color: Colors.teal,
          pageBuilder: (user) => ParentsManagementMenu(currentUser: user),
          children: [
            SidebarMenuItem(
              id: 'parents_management/all_parents',
              title: 'All Parents',
              icon: Icons.people_outline,
              color: Colors.teal,
              permissionModule: 'parents_view',
              pageBuilder: (_) => const AllParentsScreen(),
            ),
          ],
        ),

        // Bills & Payment
        SidebarMenuItem(
          id: 'bills_payment',
          title: 'Bills & Payment',
          icon: Icons.receipt_long_outlined,
          color: Colors.indigo,
          pageBuilder: (user) => BillsPaymentMenu(currentUser: user),
          children: [
            SidebarMenuItem(
              id: 'bills_payment/fee_items',
              title: 'Fee Items',
              icon: Icons.list_alt_outlined,
              color: Colors.indigo,
              permissionModule: 'fees_manage',
              pageBuilder: (_) => const FeeItemListScreen(),
            ),
            SidebarMenuItem(
              id: 'bills_payment/student_bills',
              title: 'Student Bills',
              icon: Icons.receipt_outlined,
              color: Colors.teal,
              permissionModule: 'bills_generate',
              pageBuilder: (_) => const BillStudentSelectScreen(),
            ),
            SidebarMenuItem(
              id: 'bills_payment/view_term_bills',
              title: 'View Term Bills',
              icon: Icons.receipt_long,
              color: Colors.purple,
              permissionModule: 'bills_generate',
              pageBuilder: (_) => const ViewTermBillsScreen(),
            ),
            SidebarMenuItem(
              id: 'bills_payment/payments',
              title: 'Payments',
              icon: Icons.payment_outlined,
              color: Colors.green,
              permissionModule: 'payments_record',
              pageBuilder: (_) => const PaymentStudentSelectScreen(),
            ),
            SidebarMenuItem(
              id: 'bills_payment/overpayment',
              title: 'Overpayment Tracker',
              icon: Icons.trending_up_outlined,
              color: Colors.orange,
              permissionModule: 'payments_view',
              pageBuilder: (_) => const OverpaymentTrackerScreen(),
            ),
            SidebarMenuItem(
              id: 'bills_payment/debtors',
              title: 'Debtors',
              icon: Icons.warning_amber_outlined,
              color: Colors.red,
              permissionModule: 'debtors_report',
              pageBuilder: (_) => const DebtorsListScreen(),
            ),
            SidebarMenuItem(
              id: 'bills_payment/last_term_debtors',
              title: 'Last Term Debtors',
              icon: Icons.history_edu_outlined,
              color: Colors.deepOrange,
              permissionModule: 'debtors_report',
              pageBuilder: (_) => const LastTermDebtorsScreen(),
            ),
            SidebarMenuItem(
              id: 'bills_payment/new_intake',
              title: 'New Intake Bills',
              icon: Icons.person_add_alt_1_outlined,
              color: Colors.deepOrange,
              children: [
                SidebarMenuItem(
                  id: 'bills_payment/new_intake/special_items',
                  title: 'Special Bills Items',
                  icon: Icons.add_box_outlined,
                  color: Colors.deepOrange,
                  permissionModule: 'fee_items_manage',
                  pageBuilder: (_) => const SpecialFeeItemsScreen(),
                ),
                SidebarMenuItem(
                  id: 'bills_payment/new_intake/view_bills',
                  title: 'View New Intake Bills',
                  icon: Icons.visibility_outlined,
                  color: Colors.orange,
                  permissionModule: 'billing_generate',
                  pageBuilder: (_) => const ViewNewIntakeBillsScreen(),
                ),
              ],
            ),
            SidebarMenuItem(
              id: 'bills_payment/fee_tracker',
              title: 'Fee Tracker',
              icon: Icons.track_changes_outlined,
              color: Colors.blueGrey,
              children: [
                SidebarMenuItem(
                  id: 'bills_payment/fee_tracker/priority',
                  title: 'Set Bill Priority',
                  icon: Icons.low_priority_outlined,
                  color: Colors.blue,
                  permissionModule: 'fee_tracker',
                  pageBuilder: (_) => const SetBillPriorityScreen(),
                ),
                SidebarMenuItem(
                  id: 'bills_payment/fee_tracker/track',
                  title: 'Track Fee Item',
                  icon: Icons.track_changes_outlined,
                  color: Colors.orange,
                  permissionModule: 'fee_tracker',
                  pageBuilder: (_) => const TrackFeeItemScreen(),
                ),
                SidebarMenuItem(
                  id: 'bills_payment/fee_tracker/progression',
                  title: 'Payment Progression',
                  icon: Icons.stacked_bar_chart_outlined,
                  color: Colors.green,
                  permissionModule: 'fee_tracker',
                  pageBuilder: (_) => const PaymentProgressionScreen(),
                ),
              ],
            ),
          ],
        ),

        // Transportation
        SidebarMenuItem(
          id: 'transportation',
          title: 'Transportation',
          icon: Icons.directions_bus_outlined,
          color: Colors.teal,
          pageBuilder: (user) => TransportationMenu(currentUser: user),
          children: [
            SidebarMenuItem(
              id: 'transportation/routes',
              title: 'Routes',
              icon: Icons.alt_route_outlined,
              color: Colors.teal,
              permissionModule: 'transportation_manage',
              pageBuilder: (user) => RouteListScreen(currentUser: user),
            ),
            SidebarMenuItem(
              id: 'transportation/allocate',
              title: 'Allocate Students',
              icon: Icons.directions_bus_outlined,
              color: Colors.indigo,
              permissionModule: 'transportation_allocate',
              pageBuilder: (_) => const TransportStudentSelectScreen(),
            ),
            SidebarMenuItem(
              id: 'transportation/students',
              title: 'Route Students',
              icon: Icons.groups_outlined,
              color: Colors.deepPurple,
              permissionModule: 'transportation_allocate',
              pageBuilder: (_) => const RouteStudentsScreen(),
            ),
          ],
        ),

        // Reports
        SidebarMenuItem(
          id: 'reports',
          title: 'Reports',
          icon: Icons.bar_chart_outlined,
          color: Colors.deepOrange,
          pageBuilder: (user) => ReportsMenu(currentUser: user),
          children: [
            SidebarMenuItem(
              id: 'reports/daily',
              title: 'Daily Report',
              icon: Icons.today_outlined,
              color: Colors.deepOrange,
              permissionModule: 'daily_report',
              pageBuilder: (_) => const DailyReportScreen(),
            ),
            SidebarMenuItem(
              id: 'reports/termly',
              title: 'Termly Report',
              icon: Icons.calendar_month_outlined,
              color: Colors.blue,
              permissionModule: 'termly_report',
              pageBuilder: (_) => const TermlyReportScreen(),
            ),
            SidebarMenuItem(
              id: 'reports/sales',
              title: 'Sales Report',
              icon: Icons.point_of_sale_outlined,
              color: Colors.green,
              permissionModule: 'sales_report',
              pageBuilder: (_) => const SalesReportScreen(),
            ),
            SidebarMenuItem(
              id: 'reports/print_count',
              title: 'Daily Print Count',
              icon: Icons.print_outlined,
              color: Colors.purple,
              permissionModule: 'reports_view',
              pageBuilder: (_) => const DailyPrintCountScreen(),
            ),
            SidebarMenuItem(
              id: 'reports/custom',
              title: 'Custom Report',
              icon: Icons.date_range_outlined,
              color: Colors.teal,
              permissionModule: 'custom_report',
              pageBuilder: (_) => const CustomReportScreen(),
            ),
            SidebarMenuItem(
              id: 'reports/activity-log',
              title: 'Activity Log',
              icon: Icons.history_outlined,
              color: Colors.indigo,
              permissionModule: 'audit_log_view',
              pageBuilder: (_) => const ActivityLogScreen(),
            ),
          ],
        ),

        // Stock & Sales
        SidebarMenuItem(
          id: 'stock_sales',
          title: 'Stock & Sales',
          icon: Icons.inventory_2_outlined,
          color: Colors.brown,
          pageBuilder: (user) => StockSalesMenu(currentUser: user),
          children: [
            SidebarMenuItem(
              id: 'stock_sales/stock_items',
              title: 'Stock Items',
              icon: Icons.inventory_outlined,
              color: Colors.brown,
              permissionModule: 'stock_manage',
              pageBuilder: (_) => const StockItemListScreen(),
            ),
            SidebarMenuItem(
              id: 'stock_sales/suppliers',
              title: 'Suppliers',
              icon: Icons.local_shipping_outlined,
              color: Colors.blue,
              permissionModule: 'stock_manage',
              pageBuilder: (_) => const SupplierListScreen(),
            ),
            SidebarMenuItem(
              id: 'stock_sales/purchase_history',
              title: 'Purchase History',
              icon: Icons.history_outlined,
              color: Colors.purple,
              permissionModule: 'stock_view',
              pageBuilder: (_) => const PurchaseHistoryScreen(),
            ),
            SidebarMenuItem(
              id: 'stock_sales/sales',
              title: 'Sales',
              icon: Icons.point_of_sale_outlined,
              color: Colors.orange,
              permissionModule: 'sales_record',
              pageBuilder: (_) => const BuyerSelectionScreen(),
            ),
            SidebarMenuItem(
              id: 'stock_sales/report',
              title: 'Stock Report',
              icon: Icons.assessment_outlined,
              color: Colors.teal,
              permissionModule: 'stock_report',
              pageBuilder: (_) => const StockRecordReportScreen(),
            ),
          ],
        ),

        // Expenditure
        SidebarMenuItem(
          id: 'expenditure',
          title: 'Expenditure',
          icon: Icons.money_off_outlined,
          color: Colors.purple,
          pageBuilder: (user) => ExpenditureMenu(currentUser: user),
          children: [
            SidebarMenuItem(
              id: 'expenditure/record',
              title: 'Record Expense',
              icon: Icons.add_circle_outline,
              color: Colors.purple,
              permissionModule: 'expenses_record',
              pageBuilder: (user) => ExpenseFormScreen(currentUser: user),
            ),
            SidebarMenuItem(
              id: 'expenditure/list',
              title: 'Expense List',
              icon: Icons.list_outlined,
              color: Colors.deepPurple,
              permissionModule: 'expenses_view',
              pageBuilder: (user) => ExpenseListScreen(currentUser: user),
            ),
          ],
        ),

        // Staff Management (nested)
        SidebarMenuItem(
          id: 'staff_management',
          title: 'Staff Management',
          icon: Icons.badge_outlined,
          color: Colors.indigo,
          pageBuilder: (user) => StaffManagementMenu(currentUser: user),
          children: [
            // Staff Setup (nested submenu)
            SidebarMenuItem(
              id: 'staff_management/setup',
              title: 'Staff Setup',
              icon: Icons.settings,
              color: Colors.indigo,
              children: [
                SidebarMenuItem(
                  id: 'staff_management/setup/register',
                  title: 'Register Staff',
                  icon: Icons.person_add,
                  color: Colors.indigo,
                  permissionModule: 'staff_add',
                  pageBuilder: (_) => const StaffRegisterScreen(),
                ),
                SidebarMenuItem(
                  id: 'staff_management/setup/offices',
                  title: 'Staff Offices',
                  icon: Icons.business,
                  color: Colors.blue,
                  permissionModule: 'staff_manage',
                  pageBuilder: (_) => const StaffOfficesScreen(),
                ),
                SidebarMenuItem(
                  id: 'staff_management/setup/class_allocation',
                  title: 'Class Allocation',
                  icon: Icons.class_outlined,
                  color: Colors.green,
                  permissionModule: 'staff_manage',
                  pageBuilder: (_) => const ClassAllocationScreen(),
                ),
                SidebarMenuItem(
                  id: 'staff_management/setup/office_allocation',
                  title: 'Office Allocation',
                  icon: Icons.meeting_room_outlined,
                  color: Colors.orange,
                  permissionModule: 'staff_manage',
                  pageBuilder: (_) => const OfficeAllocationScreen(),
                ),
                SidebarMenuItem(
                  id: 'staff_management/setup/salary',
                  title: 'Staff Salary Setup',
                  icon: Icons.attach_money,
                  color: Colors.teal,
                  permissionModule: 'staff_salary',
                  pageBuilder: (_) => const StaffSalaryScreen(),
                ),
              ],
            ),
            // View Staff (nested submenu)
            SidebarMenuItem(
              id: 'staff_management/view',
              title: 'View Staff',
              icon: Icons.people,
              color: Colors.blue,
              children: [
                SidebarMenuItem(
                  id: 'staff_management/view/list',
                  title: 'Staff List',
                  icon: Icons.list_outlined,
                  color: Colors.blue,
                  permissionModule: 'staff_view',
                  pageBuilder: (user) => StaffListScreen(currentUser: user),
                ),
                SidebarMenuItem(
                  id: 'staff_management/view/incentive',
                  title: 'Staff Incentive/Grant',
                  icon: Icons.card_giftcard_outlined,
                  color: Colors.green,
                  permissionModule: 'staff_payroll',
                  pageBuilder: (_) => const StaffIncentiveScreen(),
                ),
                SidebarMenuItem(
                  id: 'staff_management/view/loan',
                  title: 'Staff Loan',
                  icon: Icons.account_balance_wallet_outlined,
                  color: Colors.orange,
                  permissionModule: 'staff_payroll',
                  pageBuilder: (user) => StaffLoanScreen(currentUser: user),
                ),
                SidebarMenuItem(
                  id: 'staff_management/view/deduction',
                  title: 'Penalty/Deduction',
                  icon: Icons.remove_circle_outline,
                  color: Colors.red,
                  permissionModule: 'staff_payroll',
                  pageBuilder: (_) => const StaffDeductionScreen(),
                ),
                SidebarMenuItem(
                  id: 'staff_management/view/payroll',
                  title: 'Staff Payroll',
                  icon: Icons.payment_outlined,
                  color: Colors.purple,
                  permissionModule: 'staff_payroll',
                  pageBuilder: (_) => const StaffPayrollScreen(),
                ),
              ],
            ),
          ],
        ),

        // Preferences
        SidebarMenuItem(
          id: 'preferences',
          title: 'Preferences',
          icon: Icons.settings_outlined,
          color: Colors.blueGrey,
          pageBuilder: (user) => PreferencesMenu(currentUser: user),
          children: [
            SidebarMenuItem(
              id: 'preferences/backup',
              title: 'Backup',
              icon: Icons.backup_outlined,
              color: Colors.blue,
              permissionModule: 'backup_manage',
              pageBuilder: (_) => const BackupScreen(),
            ),
            SidebarMenuItem(
              id: 'preferences/license',
              title: 'License',
              icon: Icons.verified_user_outlined,
              color: Colors.green,
              permissionModule: 'license_manage',
              pageBuilder: (_) => const LicenseManagementScreen(),
            ),
            SidebarMenuItem(
              id: 'preferences/thermal_printer',
              title: 'Thermal Printer',
              icon: Icons.print_outlined,
              color: Colors.orange,
              permissionModule: 'settings_manage',
              pageBuilder: (_) => const ThermalPrinterScreen(),
            ),
            SidebarMenuItem(
              id: 'preferences/display_settings',
              title: 'Display Settings',
              icon: Icons.display_settings_outlined,
              color: Colors.purple,
              pageBuilder: (_) => const DisplaySettingsScreen(),
            ),
            SidebarMenuItem(
              id: 'preferences/security',
              title: 'Security',
              icon: Icons.security_outlined,
              color: Colors.red,
              permissionModule: 'settings_manage',
              pageBuilder: (_) => const SecuritySettingsScreen(),
            ),
            SidebarMenuItem(
              id: 'preferences/data_management',
              title: 'Data Management',
              icon: Icons.storage_outlined,
              color: Colors.blueGrey,
              permissionModule: 'data_clear',
              pageBuilder: (_) => const ClearDataScreen(),
            ),
            SidebarMenuItem(
              id: 'preferences/permissions',
              title: 'Permissions',
              icon: Icons.admin_panel_settings_outlined,
              color: Colors.deepPurple,
              isSuperAdminOnly: true,
              pageBuilder: (user) => PermissionManagementScreen(currentUser: user),
            ),
          ],
        ),

        // User Management (Super Admin only)
        SidebarMenuItem(
          id: 'user_management',
          title: 'User Management',
          icon: Icons.manage_accounts_outlined,
          color: Colors.red,
          isSuperAdminOnly: true,
          pageBuilder: (user) => UserManagementScreen(currentUser: user),
        ),
      ];
}
