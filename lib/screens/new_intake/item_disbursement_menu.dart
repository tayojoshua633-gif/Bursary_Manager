// lib/screens/new_intake/item_disbursement_menu.dart
import 'package:flutter/material.dart';
import '../../utils/permission_helper.dart';
import '../../utils/display_settings_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import 'disburse_settings_screen.dart';
import 'disburse_items_screen.dart';
import 'disburse_report_screen.dart';

class ItemDisbursementMenu extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const ItemDisbursementMenu({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Disbursement'),
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
            module: 'fee_items_manage',
            title: 'Disburse Settings',
            subtitle: 'Choose items to track per class',
            icon: Icons.rule_outlined,
            color: Colors.deepPurple,
            page: const DisburseSettingsScreen(),
            pageId: 'bills_payment/item_disbursement/disburse_settings',
          ),
          _permissionMenuCard(
            context,
            module: 'fee_items_manage',
            title: 'Disburse Items',
            subtitle: 'Mark uniforms/textbooks received',
            icon: Icons.inventory_2_outlined,
            color: Colors.cyan,
            page: DisburseItemsScreen(currentUser: currentUser),
            pageId: 'bills_payment/item_disbursement/disburse_items',
          ),
          _permissionMenuCard(
            context,
            module: 'fee_items_manage',
            title: 'Disburse Report',
            subtitle: 'View students given their items',
            icon: Icons.fact_check_outlined,
            color: Colors.teal,
            page: const DisburseReportScreen(),
            pageId: 'bills_payment/item_disbursement/disburse_report',
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
