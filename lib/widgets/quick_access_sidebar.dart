// lib/widgets/quick_access_sidebar.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/display_settings_helper.dart';
import '../utils/navigation_helper.dart';
import '../utils/permission_helper.dart';
import '../utils/school_sync_registry.dart';

// School Management
import '../screens/school_profile/school_profile_screen.dart';
import '../screens/classes/class_list_screen.dart';
import '../screens/sessions/session_term_management_screen.dart';
// Bills & Payment
import '../screens/fees/fee_item_list_screen.dart';
import '../screens/billing/view_term_bills_screen.dart';
import '../screens/billing/class_bills_screen.dart';
import '../screens/billing/bill_student_select_screen.dart';
import '../screens/billing/debt_notification_hub_screen.dart';
import '../screens/billing/last_term_debtors_screen.dart';
import '../screens/billing/virtual_ledger_screen.dart';
import '../screens/payments/payment_student_select_screen.dart';
import '../screens/reports/overpayment_tracker_screen.dart';
import '../screens/reports/debtors_list_screen.dart';
import '../screens/menus/fee_tracker_menu.dart';
// Fee Tracker
import '../screens/fee_tracker/set_bill_priority_screen.dart';
import '../screens/fee_tracker/track_fee_item_screen.dart';
import '../screens/fee_tracker/payment_progression_screen.dart';
// New Intake & Item Disbursement
import '../screens/new_intake/new_intake_menu.dart';
import '../screens/new_intake/special_fee_items_screen.dart';
import '../screens/new_intake/view_new_intake_bills_screen.dart';
import '../screens/new_intake/all_classes_bills_screen.dart';
import '../screens/new_intake/item_disbursement_menu.dart';
import '../screens/new_intake/disburse_settings_screen.dart';
import '../screens/new_intake/disburse_items_screen.dart';
import '../screens/new_intake/disburse_report_screen.dart';
// Parents
import '../screens/parents/parent_form_screen.dart';
import '../screens/parents/all_parents_screen.dart';
import '../screens/parents/manage_parent_contacts_screen.dart';
// Transportation
import '../screens/transportation/route_list_screen.dart';
import '../screens/transportation/transport_student_select_screen.dart';
import '../screens/transportation/route_students_screen.dart';
// Reports
import '../screens/reports/daily_report_screen.dart';
import '../screens/reports/custom_report_screen.dart';
import '../screens/reports/termly_report_screen.dart';
import '../screens/reports/sales_report_screen.dart';
import '../screens/reports/daily_print_count_screen.dart';
import '../screens/reports/activity_log_screen.dart';
import '../screens/reports/fees_balance_report_screen.dart';
// Examinations
import '../screens/examinations/external_examination_list_screen.dart';
import '../screens/examinations/examination_registration_screen.dart';
import '../screens/examinations/registered_students_screen.dart';
// Staff Setup
import '../screens/staff/staff_setup/staff_register_screen.dart';
import '../screens/staff/staff_setup/staff_photo_capture_screen.dart';
import '../screens/staff/staff_setup/staff_offices_screen.dart';
import '../screens/staff/staff_setup/class_allocation_screen.dart';
import '../screens/staff/staff_setup/office_allocation_screen.dart';
import '../screens/staff/staff_setup/staff_salary_screen.dart';
// View Staff
import '../screens/staff/staff_view/staff_list_screen.dart';
import '../screens/staff/staff_view/staff_table_screen.dart';
import '../screens/staff/staff_view/staff_deactivate_screen.dart';
import '../screens/staff/staff_payroll/staff_incentive_screen.dart';
import '../screens/staff/staff_payroll/staff_loan_screen.dart';
import '../screens/staff/staff_payroll/staff_deduction_screen.dart';
import '../screens/staff/staff_payroll/staff_payroll_screen.dart';
import '../screens/staff/staff_payroll/salary_payment_record_screen.dart';
import '../screens/staff/staff_payroll/salary_increment_screen.dart';
// Preferences
import '../screens/backup/backup_screen.dart';
import '../screens/school_profile/sync_key_screen.dart';
import '../screens/settings/read_only_settings_screen.dart';
import '../screens/license/license_management_screen.dart';
import '../screens/settings/thermal_printer_screen.dart';
import '../screens/settings/usb_printer_screen.dart';
import '../screens/settings/sms_settings_screen.dart';
import '../screens/settings/admission_number_settings_screen.dart';
import '../screens/settings/display_settings_screen.dart';
import '../screens/settings/security_settings_screen.dart';
import '../screens/settings/sound_settings_screen.dart';
import '../screens/settings/clear_data_screen.dart';
import '../screens/permissions/permission_management_screen.dart';
import '../screens/auth/user_management_screen.dart';
// Backup
import '../screens/backup/backup_reminder_settings_screen.dart';
import '../screens/backup/offline_backup_screen.dart';
import '../screens/backup/online_backup_screen.dart';
import '../screens/backup/sync_dsm_screen.dart';

/// The sets of related pages that share a right-hand "Quick Access" sidebar.
enum QuickAccessGroup {
  schoolManagement,
  billsPayment,
  feeTracker,
  newIntake,
  itemDisbursement,
  parents,
  transportation,
  reports,
  examinations,
  staffSetup,
  viewStaff,
  preferences,
  backup,
}

/// Extra visibility rule for an entry, beyond its permission [module].
enum QuickAccessVisibility { always, superAdminOnly, writeModeOnly, readOnlyModeOnly }

/// One quick-access button. Titles, icons, colors, permission modules and
/// page ids mirror the card for the same page on its menu screen, so the
/// sidebar never shows a page the menu would hide.
class QuickAccessEntry {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final String? module;
  final String pageId;
  final Widget Function(Map<String, dynamic> currentUser) builder;
  final QuickAccessVisibility visibility;

  const QuickAccessEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    this.module,
    required this.pageId,
    required this.builder,
    this.visibility = QuickAccessVisibility.always,
  });
}

class QuickAccessGroups {
  static String titleFor(QuickAccessGroup group) {
    switch (group) {
      case QuickAccessGroup.schoolManagement:
        return 'School Management';
      case QuickAccessGroup.billsPayment:
        return 'Bills & Payment';
      case QuickAccessGroup.feeTracker:
        return 'Fee Tracker';
      case QuickAccessGroup.newIntake:
        return 'New Intake Bills';
      case QuickAccessGroup.itemDisbursement:
        return 'Item Disbursement';
      case QuickAccessGroup.parents:
        return 'Parents Management';
      case QuickAccessGroup.transportation:
        return 'Transportation';
      case QuickAccessGroup.reports:
        return 'Reports';
      case QuickAccessGroup.examinations:
        return 'External Examination';
      case QuickAccessGroup.staffSetup:
        return 'Staff Setup';
      case QuickAccessGroup.viewStaff:
        return 'View Staff';
      case QuickAccessGroup.preferences:
        return 'Preferences';
      case QuickAccessGroup.backup:
        return 'Backup & Restore';
    }
  }

  static List<QuickAccessEntry> entriesFor(QuickAccessGroup group) {
    switch (group) {
      case QuickAccessGroup.schoolManagement:
        return [
          QuickAccessEntry(
            id: 'profile',
            title: 'School Profile',
            icon: Icons.account_balance_outlined,
            color: Colors.deepPurple,
            module: 'school_profile',
            pageId: 'school_management/profile',
            builder: (_) => const SchoolProfileScreen(),
          ),
          QuickAccessEntry(
            id: 'classes',
            title: 'Classes & Arms',
            icon: Icons.school_outlined,
            color: Colors.orange,
            module: 'classes_arms',
            pageId: 'school_management/classes',
            builder: (_) => const ClassListScreen(),
          ),
          QuickAccessEntry(
            id: 'session_term',
            title: 'Session & Term',
            icon: Icons.date_range_outlined,
            color: Colors.purple,
            module: 'session_term',
            pageId: 'school_management/session_term',
            builder: (_) => const SessionTermManagementScreen(),
          ),
        ];

      case QuickAccessGroup.billsPayment:
        return [
          QuickAccessEntry(
            id: 'fee_items',
            title: 'Fee Items',
            icon: Icons.payments_outlined,
            color: Colors.teal,
            module: 'fee_items',
            pageId: 'bills_payment/fee_items',
            builder: (user) => FeeItemListScreen(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'view_term_bills',
            title: 'View Term Bills',
            icon: Icons.receipt_long,
            color: Colors.purple,
            module: 'billing',
            pageId: 'bills_payment/view_term_bills',
            builder: (_) => const ViewTermBillsScreen(),
          ),
          QuickAccessEntry(
            id: 'new_intake_bills',
            title: 'New Intake Bills',
            icon: Icons.person_add_alt_1_outlined,
            color: Colors.deepOrange,
            module: 'fee_items_manage',
            pageId: 'bills_payment/new_intake',
            builder: (user) => NewIntakeMenu(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'class_bills',
            title: 'Class Bills',
            icon: Icons.request_quote_outlined,
            color: Colors.blue,
            module: 'bills_generate',
            pageId: 'bills_payment/class_bills',
            builder: (_) => const ClassBillsScreen(),
          ),
          QuickAccessEntry(
            id: 'student_bills',
            title: 'Student Bills',
            icon: Icons.receipt_long_outlined,
            color: Colors.indigo,
            module: 'billing',
            pageId: 'bills_payment/student_bills',
            builder: (_) => const BillStudentSelectScreen(),
          ),
          QuickAccessEntry(
            id: 'payments',
            title: 'Payments',
            icon: Icons.attach_money_outlined,
            color: Colors.lightGreen.shade700,
            module: 'payments',
            pageId: 'bills_payment/payments',
            builder: (_) => const PaymentStudentSelectScreen(),
          ),
          QuickAccessEntry(
            id: 'overpayment',
            title: 'Overpayment',
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.amber.shade700,
            module: 'overpayment_tracker',
            pageId: 'bills_payment/overpayment',
            builder: (_) => const OverpaymentTrackerScreen(),
          ),
          QuickAccessEntry(
            id: 'item_disbursement',
            title: 'Item Disbursement',
            icon: Icons.inventory_2_outlined,
            color: Colors.cyan.shade700,
            module: 'fee_items_manage',
            pageId: 'bills_payment/item_disbursement',
            builder: (user) => ItemDisbursementMenu(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'fee_tracker',
            title: 'Fee Tracker',
            icon: Icons.track_changes_outlined,
            color: Colors.blueGrey,
            module: 'fee_tracker',
            pageId: 'bills_payment/fee_tracker',
            builder: (user) => FeeTrackerMenu(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'debtors',
            title: 'Debtors',
            icon: Icons.warning_amber_outlined,
            color: Colors.red,
            module: 'debtors_report',
            pageId: 'bills_payment/debtors',
            builder: (_) => const DebtorsListScreen(),
          ),
          QuickAccessEntry(
            id: 'debt_notification',
            title: 'Debt Notification',
            icon: Icons.mail_outline,
            color: Colors.red.shade700,
            module: 'debtors_report',
            pageId: 'bills_payment/debt_notification',
            builder: (_) => const DebtNotificationHubScreen(),
          ),
          QuickAccessEntry(
            id: 'last_term_debtors',
            title: 'Last Term Debtors',
            icon: Icons.history_edu_outlined,
            color: Colors.deepOrange,
            module: 'debtors_report',
            pageId: 'bills_payment/last_term_debtors',
            builder: (_) => const LastTermDebtorsScreen(),
          ),
          QuickAccessEntry(
            id: 'virtual_ledger',
            title: 'Virtual Ledger',
            icon: Icons.table_chart_outlined,
            color: Colors.brown,
            module: 'debtors_report',
            pageId: 'bills_payment/virtual_ledger',
            builder: (_) => const VirtualLedgerScreen(),
          ),
        ];

      case QuickAccessGroup.feeTracker:
        return [
          QuickAccessEntry(
            id: 'set_bill_priority',
            title: 'Set Bill Priority',
            icon: Icons.low_priority_outlined,
            color: Colors.blue,
            module: 'fee_tracker',
            pageId: 'bills_payment/fee_tracker/priority',
            builder: (_) => const SetBillPriorityScreen(),
          ),
          QuickAccessEntry(
            id: 'track_fee_item',
            title: 'Track Fee Item',
            icon: Icons.track_changes_outlined,
            color: Colors.orange,
            module: 'fee_tracker',
            pageId: 'bills_payment/fee_tracker/track',
            builder: (_) => const TrackFeeItemScreen(),
          ),
          QuickAccessEntry(
            id: 'payment_progression',
            title: 'Payment Progression',
            icon: Icons.stacked_bar_chart_outlined,
            color: Colors.green,
            module: 'fee_tracker',
            pageId: 'bills_payment/fee_tracker/progression',
            builder: (_) => const PaymentProgressionScreen(),
          ),
        ];

      case QuickAccessGroup.newIntake:
        return [
          QuickAccessEntry(
            id: 'special_items',
            title: 'Special Bills Items',
            icon: Icons.add_box_outlined,
            color: Colors.deepOrange,
            module: 'fee_items_manage',
            pageId: 'bills_payment/new_intake/special_items',
            builder: (user) => SpecialFeeItemsScreen(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'view_bills',
            title: 'View New Intake Bills',
            icon: Icons.visibility_outlined,
            color: Colors.orange,
            module: 'billing_generate',
            pageId: 'bills_payment/new_intake/view_bills',
            builder: (_) => const ViewNewIntakeBillsScreen(),
          ),
          QuickAccessEntry(
            id: 'all_classes_bills',
            title: 'View New Intake Bills - All Classes',
            icon: Icons.table_chart_outlined,
            color: Colors.deepOrange.shade700,
            module: 'billing_generate',
            pageId: 'bills_payment/new_intake/all_classes_bills',
            builder: (_) => const AllClassesBillsScreen(),
          ),
        ];

      case QuickAccessGroup.itemDisbursement:
        return [
          QuickAccessEntry(
            id: 'disburse_settings',
            title: 'Disburse Settings',
            icon: Icons.rule_outlined,
            color: Colors.deepPurple,
            module: 'fee_items_manage',
            pageId: 'bills_payment/item_disbursement/disburse_settings',
            builder: (_) => const DisburseSettingsScreen(),
          ),
          QuickAccessEntry(
            id: 'disburse_items',
            title: 'Disburse Items',
            icon: Icons.inventory_2_outlined,
            color: Colors.cyan.shade700,
            module: 'fee_items_manage',
            pageId: 'bills_payment/item_disbursement/disburse_items',
            builder: (user) => DisburseItemsScreen(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'disburse_report',
            title: 'Disburse Report',
            icon: Icons.fact_check_outlined,
            color: Colors.teal,
            module: 'fee_items_manage',
            pageId: 'bills_payment/item_disbursement/disburse_report',
            builder: (_) => const DisburseReportScreen(),
          ),
        ];

      case QuickAccessGroup.parents:
        return [
          QuickAccessEntry(
            id: 'add_parent',
            title: 'Add New Parent',
            icon: Icons.person_add,
            color: Colors.teal,
            pageId: 'parents_management/add_parent',
            builder: (_) => const ParentFormScreen(),
          ),
          QuickAccessEntry(
            id: 'all_parents',
            title: 'All Parents',
            icon: Icons.people,
            color: Colors.indigo,
            pageId: 'parents_management/all_parents',
            builder: (_) => const AllParentsScreen(),
          ),
          QuickAccessEntry(
            id: 'manage_contacts',
            title: 'Manage Contacts',
            icon: Icons.contact_phone,
            color: Colors.deepPurple,
            pageId: 'parents_management/manage_contacts',
            builder: (_) => const ManageParentContactsScreen(),
          ),
        ];

      case QuickAccessGroup.transportation:
        return [
          QuickAccessEntry(
            id: 'routes',
            title: 'Routes',
            icon: Icons.alt_route_outlined,
            color: Colors.teal,
            module: 'transportation_manage',
            pageId: 'transportation/routes',
            builder: (user) => RouteListScreen(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'allocate',
            title: 'Allocate Students',
            icon: Icons.directions_bus_outlined,
            color: Colors.indigo,
            module: 'transportation_allocate',
            pageId: 'transportation/allocate',
            builder: (_) => const TransportStudentSelectScreen(),
          ),
          QuickAccessEntry(
            id: 'route_students',
            title: 'Route Students',
            icon: Icons.groups_outlined,
            color: Colors.deepPurple,
            module: 'transportation_allocate',
            pageId: 'transportation/students',
            builder: (_) => const RouteStudentsScreen(),
          ),
        ];

      case QuickAccessGroup.reports:
        return [
          QuickAccessEntry(
            id: 'daily',
            title: 'Daily Report',
            icon: Icons.today_outlined,
            color: Colors.blue,
            module: 'daily_report',
            pageId: 'reports/daily',
            builder: (_) => const DailyReportScreen(),
          ),
          QuickAccessEntry(
            id: 'custom',
            title: 'Custom Report',
            icon: Icons.date_range_outlined,
            color: Colors.teal,
            module: 'custom_report',
            pageId: 'reports/custom',
            builder: (_) => const CustomReportScreen(),
          ),
          QuickAccessEntry(
            id: 'termly',
            title: 'Termly Report',
            icon: Icons.calendar_month_outlined,
            color: Colors.purple,
            module: 'termly_report',
            pageId: 'reports/termly',
            builder: (_) => const TermlyReportScreen(),
          ),
          QuickAccessEntry(
            id: 'sales',
            title: 'Sales Report',
            icon: Icons.analytics_outlined,
            color: Colors.deepOrange,
            module: 'sales_report',
            pageId: 'reports/sales',
            builder: (_) => const SalesReportScreen(),
          ),
          QuickAccessEntry(
            id: 'print_count',
            title: 'Daily Print Count',
            icon: Icons.print_outlined,
            color: Colors.cyan.shade700,
            module: 'daily_print_count',
            pageId: 'reports/print_count',
            builder: (_) => const DailyPrintCountScreen(),
          ),
          QuickAccessEntry(
            id: 'activity_log',
            title: 'Activity Log',
            icon: Icons.history_outlined,
            color: Colors.indigo,
            module: 'audit_log_view',
            pageId: 'reports/activity-log',
            builder: (_) => const ActivityLogScreen(),
          ),
          QuickAccessEntry(
            id: 'fees_balance',
            title: 'School Fees Balance Report',
            icon: Icons.fact_check_outlined,
            color: Colors.green,
            module: 'reports_fees_balance',
            pageId: 'reports/fees-balance',
            builder: (_) => const FeesBalanceReportScreen(),
          ),
        ];

      case QuickAccessGroup.examinations:
        return [
          QuickAccessEntry(
            id: 'types',
            title: 'Examination Types',
            icon: Icons.school_outlined,
            color: Colors.cyan.shade700,
            pageId: 'external_examinations/types',
            builder: (_) => const ExternalExaminationListScreen(),
          ),
          QuickAccessEntry(
            id: 'registration',
            title: 'Exam Registration',
            icon: Icons.app_registration_outlined,
            color: Colors.teal,
            pageId: 'external_examinations/registration',
            builder: (user) => ExaminationRegistrationScreen(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'registered_students',
            title: 'Registered Students',
            icon: Icons.people_outline,
            color: Colors.indigo,
            pageId: 'external_examinations/students',
            builder: (_) => const RegisteredStudentsScreen(),
          ),
        ];

      case QuickAccessGroup.staffSetup:
        return [
          QuickAccessEntry(
            id: 'register',
            title: 'Register Staff',
            icon: Icons.person_add,
            color: Colors.indigo,
            module: 'staff_add',
            pageId: 'staff_management/staff_setup/register',
            builder: (_) => const StaffRegisterScreen(),
          ),
          QuickAccessEntry(
            id: 'photo',
            title: 'Photo Capture',
            icon: Icons.camera_alt,
            color: Colors.deepPurple,
            module: 'staff_add',
            pageId: 'staff_management/staff_setup/photo',
            builder: (_) => const StaffPhotoCaptureScreen(),
          ),
          QuickAccessEntry(
            id: 'offices',
            title: 'Staff Offices',
            icon: Icons.business,
            color: Colors.teal,
            module: 'staff_offices',
            pageId: 'staff_management/staff_setup/offices',
            builder: (_) => const StaffOfficesScreen(),
          ),
          QuickAccessEntry(
            id: 'class_allocation',
            title: 'Class Allocation',
            icon: Icons.class_,
            color: Colors.purple,
            module: 'staff_class_allocation',
            pageId: 'staff_management/staff_setup/class_allocation',
            builder: (_) => const ClassAllocationScreen(),
          ),
          QuickAccessEntry(
            id: 'office_allocation',
            title: 'Office Allocation',
            icon: Icons.meeting_room,
            color: Colors.orange,
            module: 'staff_office_allocation',
            pageId: 'staff_management/staff_setup/office_allocation',
            builder: (_) => const OfficeAllocationScreen(),
          ),
          QuickAccessEntry(
            id: 'salary',
            title: 'Staff Salary',
            icon: Icons.payments,
            color: Colors.green,
            module: 'staff_salary',
            pageId: 'staff_management/staff_setup/salary',
            builder: (_) => const StaffSalaryScreen(),
          ),
        ];

      case QuickAccessGroup.viewStaff:
        return [
          QuickAccessEntry(
            id: 'list',
            title: 'Staff List',
            icon: Icons.people,
            color: Colors.blue,
            module: 'staff_view',
            pageId: 'staff_management/view_staff/list',
            builder: (user) => StaffListScreen(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'table',
            title: 'Staff Listing',
            icon: Icons.table_chart,
            color: Colors.blueGrey,
            module: 'staff_listing',
            pageId: 'staff_management/view_staff/table',
            builder: (_) => const StaffTableScreen(),
          ),
          QuickAccessEntry(
            id: 'deactivate',
            title: 'Deactivate Staff',
            icon: Icons.person_off,
            color: Colors.red,
            module: 'staff_view',
            pageId: 'staff_management/view_staff/deactivate',
            builder: (_) => const StaffDeactivateScreen(),
          ),
          QuickAccessEntry(
            id: 'incentive',
            title: 'Staff Incentive',
            icon: Icons.card_giftcard,
            color: Colors.green,
            module: 'staff_incentive',
            pageId: 'staff_management/view_staff/incentive',
            builder: (_) => const StaffIncentiveScreen(),
          ),
          QuickAccessEntry(
            id: 'loan',
            title: 'Staff Loan',
            icon: Icons.account_balance_wallet,
            color: Colors.orange,
            module: 'staff_loan',
            pageId: 'staff_management/view_staff/loan',
            builder: (user) => StaffLoanScreen(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'deduction',
            title: 'Penalty/Deduction',
            icon: Icons.remove_circle,
            color: Colors.red.shade700,
            module: 'staff_deduction',
            pageId: 'staff_management/view_staff/deduction',
            builder: (_) => const StaffDeductionScreen(),
          ),
          QuickAccessEntry(
            id: 'payroll',
            title: 'Staff Salary',
            icon: Icons.receipt_long,
            color: Colors.purple,
            module: 'staff_payroll',
            pageId: 'staff_management/view_staff/payroll',
            builder: (_) => const StaffPayrollScreen(),
          ),
          QuickAccessEntry(
            id: 'payment_record',
            title: 'Payment Record',
            icon: Icons.history,
            color: Colors.teal,
            module: 'staff_payroll',
            pageId: 'staff_management/view_staff/payment_record',
            builder: (user) => SalaryPaymentRecordScreen(currentUser: user),
          ),
          QuickAccessEntry(
            id: 'salary_increment',
            title: 'Salary Increment',
            icon: Icons.trending_up,
            color: Colors.amber.shade800,
            module: 'staff_payroll',
            pageId: 'staff_management/view_staff/salary_increment',
            builder: (_) => const SalaryIncrementScreen(),
          ),
        ];

      case QuickAccessGroup.preferences:
        return [
          QuickAccessEntry(
            id: 'backup',
            title: 'Backup & Restore',
            icon: Icons.save_alt_outlined,
            color: Colors.blueGrey,
            module: 'backup',
            pageId: 'preferences/backup',
            builder: (_) => const BackupScreen(),
          ),
          // Same slot as the Preferences menu: Read-Only Access on the main
          // device, Linked Schools on a Read-Only (viewer) device.
          QuickAccessEntry(
            id: 'sync_key',
            title: 'Read-Only Access',
            icon: Icons.key_outlined,
            color: Colors.teal,
            module: 'sync_key_management',
            pageId: 'preferences/sync_key',
            builder: (_) => const SyncKeyScreen(),
            visibility: QuickAccessVisibility.writeModeOnly,
          ),
          QuickAccessEntry(
            id: 'read_only',
            title: 'Linked Schools',
            icon: Icons.school_outlined,
            color: Colors.orange,
            pageId: 'preferences/read_only',
            builder: (_) => const ReadOnlySettingsScreen(),
            visibility: QuickAccessVisibility.readOnlyModeOnly,
          ),
          QuickAccessEntry(
            id: 'license',
            title: 'License',
            icon: Icons.verified_user_outlined,
            color: Colors.green,
            module: 'license_management',
            pageId: 'preferences/license',
            builder: (_) => const LicenseManagementScreen(),
          ),
          QuickAccessEntry(
            id: 'thermal_printer',
            title: 'Thermal Printer',
            icon: Icons.print_outlined,
            color: Colors.indigo,
            pageId: 'preferences/thermal_printer',
            builder: (_) => const ThermalPrinterScreen(),
          ),
          QuickAccessEntry(
            id: 'usb_printer',
            title: 'USB Printer',
            icon: Icons.usb_outlined,
            color: Colors.deepPurple,
            pageId: 'preferences/usb_printer',
            builder: (_) => const UsbPrinterScreen(),
          ),
          QuickAccessEntry(
            id: 'sms_settings',
            title: 'SMS Settings',
            icon: Icons.sms_outlined,
            color: Colors.blue,
            pageId: 'preferences/sms_settings',
            builder: (_) => const SmsSettingsScreen(),
          ),
          QuickAccessEntry(
            id: 'admission_number',
            title: 'Admission Number',
            icon: Icons.badge_outlined,
            color: Colors.indigo.shade300,
            pageId: 'preferences/admission_number',
            builder: (_) => const AdmissionNumberSettingsScreen(),
          ),
          QuickAccessEntry(
            id: 'display',
            title: 'Display Settings',
            icon: Icons.display_settings,
            color: Colors.teal,
            pageId: 'preferences/display',
            builder: (_) => const DisplaySettingsScreen(),
          ),
          QuickAccessEntry(
            id: 'security',
            title: 'Security',
            icon: Icons.security,
            color: Colors.red,
            pageId: 'preferences/security',
            builder: (_) => const SecuritySettingsScreen(),
          ),
          QuickAccessEntry(
            id: 'sound',
            title: 'Sound Effects',
            icon: Icons.volume_up_outlined,
            color: Colors.teal.shade700,
            pageId: 'preferences/sound',
            builder: (_) => const SoundSettingsScreen(),
          ),
          QuickAccessEntry(
            id: 'data_management',
            title: 'Data Management',
            icon: Icons.cleaning_services_outlined,
            color: Colors.orange,
            pageId: 'preferences/data_management',
            builder: (_) => const ClearDataScreen(),
          ),
          QuickAccessEntry(
            id: 'permissions',
            title: 'Permissions',
            icon: Icons.admin_panel_settings_outlined,
            color: Colors.purple,
            pageId: 'preferences/permissions',
            builder: (user) => PermissionManagementScreen(currentUser: user),
            visibility: QuickAccessVisibility.superAdminOnly,
          ),
          QuickAccessEntry(
            id: 'user_management',
            title: 'User Management',
            icon: Icons.people_outline,
            color: Colors.deepOrange,
            pageId: 'preferences/user_management',
            builder: (user) => UserManagementScreen(currentUser: user),
            visibility: QuickAccessVisibility.superAdminOnly,
          ),
        ];

      case QuickAccessGroup.backup:
        return [
          QuickAccessEntry(
            id: 'reminder',
            title: 'Backup Reminder Settings',
            icon: Icons.notifications_active,
            color: Colors.blue,
            pageId: 'preferences/backup',
            builder: (_) => const BackupReminderSettingsScreen(),
          ),
          QuickAccessEntry(
            id: 'offline',
            title: 'Offline Backup',
            icon: Icons.backup,
            color: Colors.teal,
            pageId: 'preferences/backup',
            builder: (_) => const OfflineBackupScreen(),
          ),
          // Online Backup is locked on Read-Only devices (see BackupScreen).
          QuickAccessEntry(
            id: 'online',
            title: 'Online Backup',
            icon: Icons.cloud,
            color: Colors.blue.shade700,
            pageId: 'preferences/backup',
            builder: (_) => const OnlineBackupScreen(),
            visibility: QuickAccessVisibility.writeModeOnly,
          ),
          QuickAccessEntry(
            id: 'sync_dsm',
            title: 'Sync with DSM',
            icon: Icons.sync_alt,
            color: Colors.indigo,
            pageId: 'preferences/backup',
            builder: (_) => const SyncDsmScreen(),
          ),
        ];
    }
  }
}

/// Whether the screen is wide enough for the Quick Access sidebar (same
/// large-screen rule as the left navigation sidebar: shortest side >= 700).
bool shouldShowQuickAccessSidebar(BuildContext context) {
  return MediaQuery.of(context).size.shortestSide >= 700;
}

/// Places [child] (a full page) beside a right-hand [QuickAccessSidebar] for
/// [group] on large screens; on small screens, or when [enabled] is false,
/// returns [child] unchanged.
class QuickAccessScaffold extends StatelessWidget {
  final QuickAccessGroup group;
  final String currentId;
  final Widget child;
  final bool enabled;

  const QuickAccessScaffold({
    super.key,
    required this.group,
    required this.currentId,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || !shouldShowQuickAccessSidebar(context)) return child;
    return Row(
      children: [
        Expanded(child: child),
        QuickAccessSidebar(group: group, currentId: currentId),
      ],
    );
  }
}

/// Right-hand "Quick Access" list of the pages in [group]. The page matching
/// [currentId] is highlighted; tapping another page replaces the current one
/// so Back still returns to the menu the user started from.
class QuickAccessSidebar extends StatefulWidget {
  final QuickAccessGroup group;
  final String currentId;

  const QuickAccessSidebar({
    super.key,
    required this.group,
    required this.currentId,
  });

  @override
  State<QuickAccessSidebar> createState() => _QuickAccessSidebarState();
}

class _QuickAccessSidebarState extends State<QuickAccessSidebar> {
  Map<String, dynamic> _currentUser = {};
  List<QuickAccessEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant QuickAccessSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = <String, dynamic>{
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };
    final isReadOnly = await SchoolSyncRegistry.isReadOnlyMode();
    final isSuperAdmin = currentUser['userType'] == 'super_admin';

    final visible = <QuickAccessEntry>[];
    for (final entry in QuickAccessGroups.entriesFor(widget.group)) {
      switch (entry.visibility) {
        case QuickAccessVisibility.always:
          break;
        case QuickAccessVisibility.superAdminOnly:
          if (!isSuperAdmin) continue;
          break;
        case QuickAccessVisibility.writeModeOnly:
          if (isReadOnly) continue;
          break;
        case QuickAccessVisibility.readOnlyModeOnly:
          if (!isReadOnly) continue;
          break;
      }
      final module = entry.module;
      if (module != null) {
        bool allowed;
        try {
          allowed = await PermissionHelper.hasPermission(currentUser, module);
        } catch (_) {
          allowed = false;
        }
        if (!allowed) continue;
      }
      visible.add(entry);
    }

    if (!mounted) return;
    setState(() {
      _currentUser = currentUser;
      _entries = visible;
      _loading = false;
    });
  }

  void _open(QuickAccessEntry entry) {
    if (entry.id == widget.currentId) return;
    NavigationHelper.pushReplacementWithSidebar(
      context,
      page: entry.builder(_currentUser),
      currentUser: _currentUser,
      pageId: entry.pageId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = DisplaySettingsProvider.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        width: 250,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.dividerColor)),
        ),
        child: SafeArea(
          left: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: kToolbarHeight),
                padding: EdgeInsets.symmetric(horizontal: ds.cardPadding),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: theme.dividerColor)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Access',
                      style: TextStyle(
                        fontSize: ds.titleFontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      QuickAccessGroups.titleFor(widget.group),
                      style: TextStyle(
                        fontSize: ds.bodyFontSize * 0.85,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: EdgeInsets.all(ds.cardPadding * 0.75),
                        children: [
                          for (final entry in _entries) _tile(ds, entry),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(DisplaySettings ds, QuickAccessEntry entry) {
    final isCurrent = entry.id == widget.currentId;
    final color = entry.color;

    return Padding(
      padding: EdgeInsets.only(bottom: ds.cardPadding * 0.5),
      child: Material(
        color: color.withValues(alpha: isCurrent ? 0.18 : 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isCurrent
              ? BorderSide(color: color, width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: isCurrent ? null : () => _open(entry),
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
                  child: Icon(entry.icon, size: ds.iconSize * 0.9, color: Colors.white),
                ),
                SizedBox(width: ds.cardPadding * 0.6),
                Expanded(
                  child: Text(
                    entry.title,
                    style: TextStyle(
                      fontSize: ds.bodyFontSize,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                    ),
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
