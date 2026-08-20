// lib/screens/menus/preferences_menu.dart
import 'package:flutter/material.dart';
import '../../utils/permission_helper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/school_sync_registry.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../backup/backup_screen.dart';
import '../license/license_management_screen.dart';
import '../permissions/permission_management_screen.dart';
import '../school_profile/sync_key_screen.dart';
import '../settings/thermal_printer_screen.dart';
import '../settings/usb_printer_screen.dart';
import '../settings/clear_data_screen.dart';
import '../settings/display_settings_screen.dart';
import '../settings/security_settings_screen.dart';
import '../auth/user_management_screen.dart';
import '../settings/read_only_settings_screen.dart';
import '../settings/sms_settings_screen.dart';
import '../settings/admission_number_settings_screen.dart';

class PreferencesMenu extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const PreferencesMenu({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = (currentUser['userType'] ?? 'bursar') == 'super_admin';
    final displaySettings = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: GridView.extent(
        maxCrossAxisExtent: context.gridMaxExtent,
        padding: EdgeInsets.all(displaySettings.cardPadding),
        crossAxisSpacing: displaySettings.cardPadding,
        mainAxisSpacing: displaySettings.cardPadding,
        childAspectRatio: context.gridChildAspectRatio,
        children: [
          _permissionMenuCard(
            context,
            module: 'backup',
            title: 'Backup',
            subtitle: 'Save & restore data',
            icon: Icons.save_alt_outlined,
            color: Colors.blueGrey,
            page: const BackupScreen(),
            pageId: 'preferences/backup',
          ),
          _readOnlyAwareCard(context),
          _permissionMenuCard(
            context,
            module: 'license_management',
            title: 'License',
            subtitle: 'Manage app license',
            icon: Icons.verified_user_outlined,
            color: Colors.green,
            page: const LicenseManagementScreen(),
            pageId: 'preferences/license',
          ),
          _menuCard(
            context,
            title: 'Thermal Printer',
            subtitle: 'Bluetooth printer settings',
            icon: Icons.print_outlined,
            color: Colors.indigo,
            page: const ThermalPrinterScreen(),
            pageId: 'preferences/thermal_printer',
          ),
          _menuCard(
            context,
            title: 'USB Printer',
            subtitle: 'OTG cable printer settings',
            icon: Icons.usb_outlined,
            color: Colors.deepPurple,
            page: const UsbPrinterScreen(),
            pageId: 'preferences/usb_printer',
          ),
          _menuCard(
            context,
            title: 'SMS Settings',
            subtitle: 'SMS gateway & notifications',
            icon: Icons.sms_outlined,
            color: Colors.blue,
            page: const SmsSettingsScreen(),
            pageId: 'preferences/sms_settings',
          ),
          _menuCard(
            context,
            title: 'Admission Number',
            subtitle: 'Editable & serial restart rules',
            icon: Icons.badge_outlined,
            color: Colors.indigo,
            page: const AdmissionNumberSettingsScreen(),
            pageId: 'preferences/admission_number',
          ),
          _menuCard(
            context,
            title: 'Display Settings',
            subtitle: 'Screen size optimization',
            icon: Icons.display_settings,
            color: Colors.teal,
            page: const DisplaySettingsScreen(),
            pageId: 'preferences/display',
          ),
          _menuCard(
            context,
            title: 'Security',
            subtitle: 'Auto-logout settings',
            icon: Icons.security,
            color: Colors.red,
            page: const SecuritySettingsScreen(),
            pageId: 'preferences/security',
          ),
          _menuCard(
            context,
            title: 'Data Management',
            subtitle: 'Clear data & reset',
            icon: Icons.cleaning_services_outlined,
            color: Colors.orange,
            page: const ClearDataScreen(),
            pageId: 'preferences/data_management',
          ),
          // Permissions - Super Admin Only
          if (isSuperAdmin)
            _menuCard(
              context,
              title: 'Permissions',
              subtitle: 'Manage role permissions',
              icon: Icons.security,
              color: Colors.purple,
              page: PermissionManagementScreen(currentUser: currentUser),
              pageId: 'preferences/permissions',
            ),
          // User Management - Super Admin Only
          if (isSuperAdmin)
            _menuCard(
              context,
              title: 'User Management',
              subtitle: 'Manage user accounts',
              icon: Icons.people_outline,
              color: Colors.deepOrange,
              page: UserManagementScreen(currentUser: currentUser),
              pageId: 'preferences/user_management',
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

  /// Read-only devices see "Linked Schools" (manage what's linked, no
  /// permission gate — same as the old CloudSync card). Write devices see
  /// "Read-Only Access" (generate/revoke the key that grants it), gated by
  /// sync_key_management since handing out data access is a sensitive action.
  Widget _readOnlyAwareCard(BuildContext context) {
    return FutureBuilder<bool>(
      future: SchoolSyncRegistry.isReadOnlyMode(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.data == true) {
          return _menuCard(
            context,
            title: 'Linked Schools',
            subtitle: 'Manage schools synced to this device',
            icon: Icons.school_outlined,
            color: Colors.orange,
            page: const ReadOnlySettingsScreen(),
            pageId: 'preferences/read_only',
          );
        }

        return _permissionMenuCard(
          context,
          module: 'sync_key_management',
          title: 'Read-Only Access',
          subtitle: 'Sync key for viewer devices',
          icon: Icons.key_outlined,
          color: Colors.teal,
          page: const SyncKeyScreen(),
          pageId: 'preferences/sync_key',
        );
      },
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
