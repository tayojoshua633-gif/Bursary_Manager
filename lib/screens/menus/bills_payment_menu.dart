// lib/screens/menus/bills_payment_menu.dart
import 'package:flutter/material.dart';
import '../../utils/permission_helper.dart';
import '../../utils/display_settings_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../fees/fee_item_list_screen.dart';
import '../billing/bill_student_select_screen.dart';
import '../payments/payment_student_select_screen.dart';
import '../reports/overpayment_tracker_screen.dart';
import '../reports/debtors_list_screen.dart';
import '../billing/last_term_debtors_screen.dart';
import '../billing/view_term_bills_screen.dart';
import '../new_intake/new_intake_menu.dart';
import '../billing/debt_notification_hub_screen.dart';
import '../billing/virtual_ledger_screen.dart';
import 'fee_tracker_menu.dart';

class BillsPaymentMenu extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const BillsPaymentMenu({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills & Payment'),
        backgroundColor: Colors.indigo,
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
            module: 'fee_items',
            title: 'Fee Items',
            subtitle: 'Define & assign fees',
            icon: Icons.payments_outlined,
            color: Colors.teal,
            page: FeeItemListScreen(currentUser: currentUser),
            pageId: 'bills_payment/fee_items',
          ),
          _permissionMenuCard(
            context,
            module: 'billing',
            title: 'View Term Bills',
            subtitle: 'Bill breakdown by class',
            icon: Icons.receipt_long,
            color: Colors.purple,
            page: const ViewTermBillsScreen(),
            pageId: 'bills_payment/view_term_bills',
          ),
          _permissionMenuCard(
            context,
            module: 'fee_items_manage',
            title: 'New Intake Bills',
            subtitle: 'Special fees for new students',
            icon: Icons.person_add_alt_1_outlined,
            color: Colors.deepOrange,
            page: NewIntakeMenu(currentUser: currentUser),
            pageId: 'bills_payment/new_intake',
          ),
          _permissionMenuCard(
            context,
            module: 'billing',
            title: 'Student Bills',
            subtitle: 'Generate bills',
            icon: Icons.receipt_long_outlined,
            color: Colors.indigo,
            page: const BillStudentSelectScreen(),
            pageId: 'bills_payment/student_bills',
          ),
          _permissionMenuCard(
            context,
            module: 'payments',
            title: 'Payments',
            subtitle: 'Record payments',
            icon: Icons.attach_money_outlined,
            color: Colors.lightGreen,
            page: const PaymentStudentSelectScreen(),
            pageId: 'bills_payment/payments',
          ),
          _permissionMenuCard(
            context,
            module: 'overpayment_tracker',
            title: 'Overpayment Tracker',
            subtitle: 'Track overpayments',
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.amber,
            page: const OverpaymentTrackerScreen(),
            pageId: 'bills_payment/overpayment',
          ),
          _permissionMenuCard(
            context,
            module: 'debtors_report',
            title: 'Debtors',
            subtitle: 'Outstanding fees',
            icon: Icons.warning_amber_outlined,
            color: Colors.red,
            page: const DebtorsListScreen(),
            pageId: 'bills_payment/debtors',
          ),
          _permissionMenuCard(
            context,
            module: 'debtors_report',
            title: 'Last Term Debtors',
            subtitle: 'Previous balance status',
            icon: Icons.history_edu_outlined,
            color: Colors.deepOrange,
            page: const LastTermDebtorsScreen(),
            pageId: 'bills_payment/last_term_debtors',
          ),
          _permissionMenuCard(
            context,
            module: 'fee_tracker',
            title: 'Fee Tracker',
            subtitle: 'Track payment allocation & progression',
            icon: Icons.track_changes_outlined,
            color: Colors.blueGrey,
            page: FeeTrackerMenu(currentUser: currentUser),
            pageId: 'bills_payment/fee_tracker',
          ),
          _permissionMenuCard(
            context,
            module: 'debtors_report',
            title: 'Debt Notification',
            subtitle: 'Generate letters for debtors',
            icon: Icons.mail_outline,
            color: Colors.red,
            page: const DebtNotificationHubScreen(),
            pageId: 'bills_payment/debt_notification',
          ),
          _permissionMenuCard(
            context,
            module: 'debtors_report',
            title: 'Virtual Ledger',
            subtitle: 'Student ledger sheet by instalments',
            icon: Icons.table_chart_outlined,
            color: Colors.brown,
            page: const VirtualLedgerScreen(),
            pageId: 'bills_payment/virtual_ledger',
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
