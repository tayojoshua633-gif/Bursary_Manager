// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import '../utils/app_version.dart';
import '../utils/app_uptime.dart';
import '../utils/display_settings_helper.dart';
import '../utils/license_checker.dart';
import '../utils/license_helper.dart';
import '../utils/license_tier_helper.dart';
import '../data/database_helper_wrapper.dart';
import '../navigation/sidebar_scaffold.dart';
import 'dashboard/dashboard_screen.dart';
import 'auth/welcome_screen.dart';
import 'settings/change_credentials_screen.dart';
import 'menus/school_management_menu.dart';
import 'menus/student_management_menu.dart';
import 'menus/parents_management_menu.dart';
import 'menus/bills_payment_menu.dart';
import 'menus/transportation_menu.dart';
import 'menus/reports_menu.dart';
import 'menus/stock_sales_menu.dart';
import 'menus/expenditure_menu.dart';
import 'menus/preferences_menu.dart';
import 'menus/staff_management_menu.dart';
import '../server/server.dart';
import '../widgets/network_status_indicator.dart';
import '../db/database_helper.dart';
import '../utils/school_sync_registry.dart';
import '../utils/school_sync_client.dart';
import '../utils/central_backup_helper.dart';
import '../utils/permission_helper.dart';
import 'reports/unified_report_screen.dart';
import '../utils/active_session_term_notifier.dart';
import 'guide/app_guide_screen.dart';
import 'examinations/examination_menu_screen.dart';
import 'web/web_view_screen.dart';
import '../widgets/whats_new_dialog.dart';

// Quick access imports
import 'students/student_form_screen.dart';
import 'students/student_list_screen.dart';
import 'payments/payment_student_select_screen.dart';
import 'sales/buyer_selection_screen.dart';
import 'reports/daily_report_screen.dart';
import 'expenses/expense_form_screen.dart';
import 'billing/bill_student_select_screen.dart';
import 'backup/backup_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const HomeScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _appMode = 'standalone';
  bool _isReadOnlyMode = false;
  bool _isSyncing = false;

  List<LinkedSchool> _linkedSchools = [];
  String? _activeSchoolId;
  TabController? _schoolTabController;

  String? _activeSession;
  String? _activeTerm;
  int? _licenseDaysRemaining;
  LicenseTier? _currentTier;
  bool _isMasterKey = false;
  String _uptimeText = AppUptime.format();
  Timer? _uptimeTimer;

  @override
  void initState() {
    super.initState();
    _loadAppMode();
    _loadLinkedSchools();
    _loadActiveSessionTerm();
    _loadLicenseStatus();
    ActiveSessionTermNotifier.listenable.addListener(_loadActiveSessionTerm);
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _uptimeText = AppUptime.format());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WhatsNewDialog.maybeShow(context);
    });
  }

  @override
  void dispose() {
    ActiveSessionTermNotifier.listenable.removeListener(_loadActiveSessionTerm);
    _uptimeTimer?.cancel();
    _schoolTabController?.dispose();
    super.dispose();
  }

  Future<void> _loadAppMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _appMode = prefs.getString('app_mode') ?? 'standalone';
    });
  }

  /// A device is Read-Only purely by having ≥1 linked school — see
  /// SchoolSyncRegistry.isReadOnlyMode(). Reloads the tab list and rebuilds
  /// the TabController whenever the set of linked schools changes (add,
  /// remove, or on first load).
  Future<void> _loadLinkedSchools() async {
    final schools = await SchoolSyncRegistry.getAll();
    final activeId = await SchoolSyncRegistry.getActiveId();
    if (!mounted) return;
    setState(() {
      _linkedSchools = schools;
      _isReadOnlyMode = schools.isNotEmpty;
      _activeSchoolId = schools.isEmpty
          ? null
          : (schools.any((s) => s.id == activeId) ? activeId : schools.first.id);
      _rebuildSchoolTabController();
    });
  }

  void _rebuildSchoolTabController() {
    _schoolTabController?.dispose();
    if (_linkedSchools.isEmpty) {
      _schoolTabController = null;
      return;
    }
    final initialIndex = _activeSchoolId == null
        ? 0
        : _linkedSchools.indexWhere((s) => s.id == _activeSchoolId).clamp(0, _linkedSchools.length - 1);
    _schoolTabController = TabController(
      length: _linkedSchools.length,
      vsync: this,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    );
  }

  /// Switches the active local database to [school] — instant, offline, no
  /// network involved. Refreshing a school's data happens separately, via
  /// pull-to-refresh or the sync button.
  Future<void> _switchToSchool(LinkedSchool school) async {
    if (school.id == _activeSchoolId) return;
    setState(() => _activeSchoolId = school.id);
    await DatabaseHelper().switchDatabase(school.dbFileName);
    await SchoolSyncRegistry.setActiveId(school.id);
    if (!mounted) return;
    await Future.wait([_loadActiveSessionTerm(), _loadLicenseStatus()]);
  }

  Future<void> _loadActiveSessionTerm() async {
    final db = DatabaseHelperWrapper();
    final results = await Future.wait([
      db.getActiveSession(),
      db.getActiveTerm(),
    ]);
    if (!mounted) return;
    setState(() {
      final session = results[0] as Map<String, dynamic>?;
      _activeSession = session?['sessionName'] as String?;
      _activeTerm = results[1] as String?;
    });
  }

  Future<void> _loadLicenseStatus() async {
    final db = DatabaseHelperWrapper();
    final status = await LicenseChecker.checkLicense();
    final activeLicense = await db.getActiveLicense();

    // Re-decode the stored key just to read the isMasterKey flag — that
    // flag isn't persisted on the licenses table itself.
    final decoded = activeLicense != null
        ? LicenseHelper.validateLicenseKey(activeLicense['licenseKey'] as String)
        : null;

    if (!mounted) return;
    setState(() {
      _licenseDaysRemaining = status.isValid ? status.daysRemaining : null;
      _isMasterKey = decoded?['isMasterKey'] == true;
      // Tiers were introduced after many licenses were already activated,
      // so older licenses carry no maxStudents cap (0/null = unlimited) and
      // have no tier to show. For newer licenses, derive the tier from the
      // maxStudents entitlement actually purchased — not the school's
      // current active student count, which fluctuates independently of
      // what was paid for. A master key isn't a real pricing tier, so it's
      // shown separately in the app bar title instead.
      final maxStudents = status.maxStudents;
      _currentTier = (_isMasterKey || maxStudents == null || maxStudents <= 0)
          ? null
          : tierForStudentCount(maxStudents);
    });
  }

  /// Manual sync: refreshes the active school on Read-Only devices, pushes
  /// this device's own data to the central server on Write devices.
  Future<void> _triggerManualSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    Map<String, dynamic> result;
    if (_isReadOnlyMode) {
      final active = _linkedSchools.where((s) => s.id == _activeSchoolId).firstOrNull;
      if (active == null) {
        result = {'success': false, 'message': 'No school selected.'};
      } else {
        result = await SchoolSyncClient.refreshSchool(active, makeActive: true);
      }
    } else {
      result = await CentralBackupHelper.triggerAutoUpload();
    }

    if (!mounted) return;

    if (result['success'] == true && _isReadOnlyMode) {
      await Future.wait([_loadActiveSessionTerm(), _loadLicenseStatus()]);
      if (!mounted) return;
    }

    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              result['success'] == true ? Icons.cloud_done : Icons.cloud_off,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(result['message'] ?? 'Sync complete')),
          ],
        ),
        backgroundColor: result['success'] == true
            ? Colors.teal.shade700
            : Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<bool> _showExitConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.exit_to_app, color: Colors.red),
            SizedBox(width: 10),
            Text('Exit App'),
          ],
        ),
        content: const Text('Are you sure you want to exit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // HIDDEN: Server hosting permission check (pending future upgrade)
  // Will be re-enabled in next version
  // Future<bool> _hasServerHostingPermission() async {
  //   final userTypeRaw = widget.currentUser['userType'] ?? 'bursar';
  //   // Super admin always has access
  //   if (userTypeRaw == 'super_admin') {
  //     return true;
  //   }
  //   // Check permission for admin and bursar
  //   final db = DatabaseHelperWrapper();
  //   return await db.hasPermission(userTypeRaw, 'server_hosting');
  // }

  void _showUserProfileDialog(BuildContext context) {
    final userTypeRaw = widget.currentUser['userType'] ?? 'bursar';
    final username = widget.currentUser['username'] ?? 'User';
    final userType = userTypeRaw == 'super_admin'
        ? 'Super Admin'
        : userTypeRaw == 'admin'
        ? 'Admin'
        : 'Bursar';
    final userId =
        widget.currentUser['userId'] ?? widget.currentUser['id'] ?? 'N/A';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_circle, color: Colors.blue),
            SizedBox(width: 8),
            Text('User Profile'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _profileInfoRow('Username', username),
            const SizedBox(height: 12),
            _profileInfoRow('User Type', userType),
            const SizedBox(height: 12),
            _profileInfoRow('User ID', userId.toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _profileInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Stop server if running
    final server = BursaryServer();
    if (server.isRunning) {
      try {
        await server.stop();
        debugPrint('🛑 Server stopped on logout');
      } catch (e) {
        debugPrint('⚠️ Error stopping server on logout: $e');
      }
    }

    // Clear user data from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('username');
    await prefs.remove('userType');
    await prefs.remove('userId');
    await prefs.remove('email');
    await prefs.remove('schoolId');

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  /// Helper method to navigate with sidebar support
  void _navigateWithSidebar(BuildContext context, Widget page, String? pageId) {
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;
    final showSidebar = shortestSide >= 700;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: widget.currentUser,
                currentPageId: pageId,
                child: page,
              )
            : page,
      ),
    ).then((_) => Future.wait([_loadActiveSessionTerm(), _loadLinkedSchools()]));
  }

  @override
  Widget build(BuildContext context) {
    final userTypeRaw = widget.currentUser['userType'] ?? 'bursar';
    final isSuperAdmin = userTypeRaw == 'super_admin';
    final isAdmin = userTypeRaw == 'admin';
    final username = widget.currentUser['username'] ?? 'User';
    final userDisplayRole = userTypeRaw == 'super_admin'
        ? 'Super Admin'
        : userTypeRaw == 'admin'
        ? 'Admin'
        : 'Bursar';
    final ds = DisplaySettingsProvider.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmation();
        if (shouldExit && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          // Explicit solid color + transparent surface tint so the sync
          // button and user card (both styled for a dark bar) stay readable
          // at all times — Material 3's default AppBar surface is near-white
          // and only picks up a tint (making white content legible) once
          // content scrolls under it.
          backgroundColor: Colors.indigo.shade700,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          title: Text(
            _isMasterKey
                ? 'School Bursary Manager 🔑 Master $kAppVersion'
                : _currentTier == null
                    ? 'School Bursary Manager $kAppVersion'
                    : 'School Bursary Manager ${_currentTier!.label} $kAppVersion',
          ),
          centerTitle: true,
          actions: [
            // Mode Indicators
            if (_appMode == 'client')
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: NetworkStatusIndicator(
                  onDisconnected: () {
                    // Handle disconnection - could show reconnect dialog
                  },
                ),
              ),
            // HIDDEN: Server badge (pending future upgrade)
            // Will be re-enabled in next version
            // FutureBuilder<bool>(
            //   future: _hasServerHostingPermission(),
            //   builder: (context, snapshot) {
            //     final hasPermission = snapshot.data ?? false;
            //     if (!hasPermission) return const SizedBox.shrink();
            //     return Padding(...);
            //   },
            // ),

            // Sync button — write devices can always push; read-only devices
            // only once a school is selected to refresh.
            if (!_isReadOnlyMode || _activeSchoolId != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _isSyncing
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          _isReadOnlyMode
                              ? Icons.cloud_download
                              : Icons.cloud_upload,
                          color: Colors.white,
                        ),
                        tooltip: _isReadOnlyMode
                            ? 'Sync active school'
                            : 'Push to central backup',
                        onPressed: _triggerManualSync,
                      ),
              ),

            // User Menu - Larger and more visible
            PopupMenuButton<String>(
              offset: const Offset(0, 56),
              tooltip: 'User Menu',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSuperAdmin ? Icons.admin_panel_settings : Icons.person,
                      size: 24,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: 24,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(
                        isSuperAdmin
                            ? Icons.admin_panel_settings
                            : isAdmin
                            ? Icons.admin_panel_settings_outlined
                            : Icons.person,
                        size: 20,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            userDisplayRole,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'change_credentials',
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 20),
                      SizedBox(width: 12),
                      Text('Change Credentials'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Logout', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'profile':
                    // Show user profile info dialog
                    _showUserProfileDialog(context);
                    break;
                  case 'change_credentials':
                    // Navigate to change credentials screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChangeCredentialsScreen(
                          currentUser: widget.currentUser,
                        ),
                      ),
                    );
                    break;
                  case 'logout':
                    _logout(context);
                    break;
                }
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Read-Only Mode banner
            if (_isReadOnlyMode)
              Container(
                width: double.infinity,
                color: Colors.orange.shade700,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Read-Only Mode — pull down or tap Sync to refresh data.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _isSyncing ? null : _triggerManualSync,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _isSyncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Sync Now',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            // Quick Access Bar — replaced by a school switcher in Read-Only mode
            if (_isReadOnlyMode)
              _buildSchoolTabBar(ds)
            else
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ds.cardPadding,
                  vertical: ds.cardPadding * 0.75,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _quickAccessItem(
                      context,
                      icon: Icons.person_add,
                      label: 'Register',
                      color: Colors.green,
                      onTap: () => _navigateWithSidebar(
                        context,
                        const StudentFormScreen(),
                        'student_management/students',
                      ),
                    ),
                    _quickAccessItem(
                      context,
                      icon: Icons.people,
                      label: 'Students',
                      color: Colors.blue,
                      onTap: () => _navigateWithSidebar(
                        context,
                        const StudentListScreen(),
                        'student_management/students',
                      ),
                    ),
                    _quickAccessItem(
                      context,
                      icon: Icons.receipt_long,
                      label: 'Bill',
                      color: Colors.teal,
                      onTap: () => _navigateWithSidebar(
                        context,
                        const BillStudentSelectScreen(),
                        'bills_payment/student_bills',
                      ),
                    ),
                    _quickAccessItem(
                      context,
                      icon: Icons.payment,
                      label: 'Payment',
                      color: Colors.indigo,
                      onTap: () => _navigateWithSidebar(
                        context,
                        const PaymentStudentSelectScreen(),
                        'bills_payment/payments',
                      ),
                    ),
                    _quickAccessItem(
                      context,
                      icon: Icons.point_of_sale,
                      label: 'Sale',
                      color: Colors.orange,
                      onTap: () => _navigateWithSidebar(
                        context,
                        const BuyerSelectionScreen(),
                        'stock_sales/sales',
                      ),
                    ),
                    _quickAccessItem(
                      context,
                      icon: Icons.money_off,
                      label: 'Expense',
                      color: Colors.purple,
                      onTap: () => _navigateWithSidebar(
                        context,
                        ExpenseFormScreen(currentUser: widget.currentUser),
                        'expenditure/record',
                      ),
                    ),
                    _quickAccessItem(
                      context,
                      icon: Icons.assessment,
                      label: 'Daily',
                      color: Colors.deepOrange,
                      onTap: () => _navigateWithSidebar(
                        context,
                        const DailyReportScreen(),
                        'reports/daily',
                      ),
                    ),
                    _quickAccessItem(
                      context,
                      icon: Icons.backup,
                      label: 'Backup',
                      color: Colors.blueGrey,
                      onTap: () => _navigateWithSidebar(
                        context,
                        const BackupScreen(),
                        'preferences/backup',
                      ),
                    ),
                  ],
                ),
              ),

            // Session/Term Strip
            Container(
              width: double.infinity,
              color: Colors.indigo.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_activeSession != null || _activeTerm != null) ...[
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.indigo.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      [
                        if (_activeSession != null) _activeSession!,
                        if (_activeTerm != null) _activeTerm!,
                      ].join('  •  '),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.indigo.shade800,
                      ),
                    ),
                  ],
                  if (_licenseDaysRemaining != null) ...[
                    if (_activeSession != null || _activeTerm != null)
                      const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _licenseDaysRemaining! <= 30
                            ? Colors.red.shade100
                            : Colors.indigo.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'LiRm-${_licenseDaysRemaining}dys',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _licenseDaysRemaining! <= 30
                              ? Colors.red.shade800
                              : Colors.indigo.shade800,
                        ),
                      ),
                    ),
                  ],
                  if (_activeSession != null ||
                      _activeTerm != null ||
                      _licenseDaysRemaining != null)
                    const SizedBox(width: 10),
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: Colors.indigo.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Up: $_uptimeText',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                ],
              ),
            ),

            // Main Menu Grid
            Expanded(
              child: RefreshIndicator(
                onRefresh: _triggerManualSync,
                color: Colors.teal.shade700,
                child: GridView.extent(
                  physics: const AlwaysScrollableScrollPhysics(),
                  maxCrossAxisExtent: context.gridMaxExtent,
                  padding: EdgeInsets.all(ds.cardPadding),
                  crossAxisSpacing: ds.cardPadding,
                  mainAxisSpacing: ds.cardPadding,
                  childAspectRatio: context.gridChildAspectRatio,
                  children: [
                    // Dashboard - Direct access
                    _menuCard(
                      context,
                      title: 'Dashboard',
                      subtitle: 'Summary & statistics',
                      icon: Icons.dashboard_outlined,
                      color: Colors.blue,
                      page: const DashboardScreen(),
                      pageId: 'dashboard',
                    ),

                    // School Management Category
                    _menuCard(
                      context,
                      title: 'School Management',
                      subtitle: 'Profile, classes & sessions',
                      icon: Icons.account_balance_outlined,
                      color: Colors.deepPurple,
                      page: SchoolManagementMenu(
                        currentUser: widget.currentUser,
                      ),
                      pageId: 'school_management',
                    ),

                    // Student Management Category
                    _menuCard(
                      context,
                      title: 'Student Management',
                      subtitle: 'Students & debtors',
                      icon: Icons.people_outlined,
                      color: Colors.green,
                      page: StudentManagementMenu(
                        currentUser: widget.currentUser,
                      ),
                      pageId: 'student_management',
                    ),

                    // Bills & Payment Category
                    _menuCard(
                      context,
                      title: 'Bills & Payment',
                      subtitle: 'Fees, bills & payments',
                      icon: Icons.receipt_long_outlined,
                      color: Colors.indigo,
                      page: BillsPaymentMenu(currentUser: widget.currentUser),
                      pageId: 'bills_payment',
                    ),

                    // Parents Management Category
                    _menuCard(
                      context,
                      title: 'Parents Management',
                      subtitle: 'Parents information',
                      icon: Icons.family_restroom_outlined,
                      color: Colors.teal,
                      page: ParentsManagementMenu(
                        currentUser: widget.currentUser,
                      ),
                      pageId: 'parents_management',
                    ),

                    // Transportation Category
                    _menuCard(
                      context,
                      title: 'Transportation',
                      subtitle: 'Routes & student allocation',
                      icon: Icons.directions_bus_outlined,
                      color: Colors.teal,
                      page: TransportationMenu(currentUser: widget.currentUser),
                      pageId: 'transportation',
                    ),

                    // Reports Category
                    _menuCard(
                      context,
                      title: 'Reports',
                      subtitle: 'Analytics & summaries',
                      icon: Icons.bar_chart_outlined,
                      color: Colors.deepOrange,
                      page: ReportsMenu(currentUser: widget.currentUser),
                      pageId: 'reports',
                    ),

                    // Stock & Sales Management Category
                    _menuCard(
                      context,
                      title: 'Stock & Sales',
                      subtitle: 'Inventory & sales',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.brown,
                      page: StockSalesMenu(currentUser: widget.currentUser),
                      pageId: 'stock_sales',
                    ),

                    // Expenditure Management Category
                    _menuCard(
                      context,
                      title: 'Expenditure',
                      subtitle: 'Track expenses',
                      icon: Icons.money_off_outlined,
                      color: Colors.purple,
                      page: ExpenditureMenu(currentUser: widget.currentUser),
                      pageId: 'expenditure',
                    ),

                    // Staff Management Category
                    _menuCard(
                      context,
                      title: 'Staff Management',
                      subtitle: 'Staff records & allocations',
                      icon: Icons.badge_outlined,
                      color: Colors.indigo,
                      page: StaffManagementMenu(
                        currentUser: widget.currentUser,
                      ),
                      pageId: 'staff_management',
                    ),

                    // Preferences Category
                    _menuCard(
                      context,
                      title: 'Preferences',
                      subtitle: 'Backup, license & settings',
                      icon: Icons.settings_outlined,
                      color: Colors.blueGrey,
                      page: PreferencesMenu(currentUser: widget.currentUser),
                      pageId: 'preferences',
                    ),

                    // External Examination
                    _menuCard(
                      context,
                      title: 'External Examination',
                      subtitle: 'Exam types & registration',
                      icon: Icons.assignment_outlined,
                      color: Colors.cyan,
                      page: ExaminationMenuScreen(
                        currentUser: widget.currentUser,
                      ),
                      pageId: 'external_examinations',
                    ),

                    // App Guide
                    _menuCard(
                      context,
                      title: 'App Guide',
                      subtitle: 'Documentation & manual',
                      icon: Icons.menu_book_outlined,
                      color: Colors.teal,
                      page: const AppGuideScreen(),
                      pageId: 'guide',
                    ),

                    // Updates
                    _menuCard(
                      context,
                      title: 'Updates',
                      subtitle: 'Latest app updates',
                      icon: Icons.system_update_outlined,
                      color: Colors.cyan,
                      page: const WebViewScreen(
                        url: 'https://tysolutions.com.ng/apps/bursary-manager.html',
                        title: 'Updates',
                      ),
                      pageId: 'updates',
                    ),
                  ],
                ), // GridView.extent
              ), // RefreshIndicator
            ), // Expanded
          ], // Column children
        ), // Column
      ), // Scaffold
    );
  }

  /// Replaces the Quick Access Bar in Read-Only mode: one tab per linked
  /// school, plus an "Add School" affordance. Empty state (no schools yet)
  /// shows a prompt instead of an empty tab strip.
  Widget _buildSchoolTabBar(DisplaySettings ds) {
    if (_linkedSchools.isEmpty) {
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: ds.cardPadding,
          vertical: ds.cardPadding,
        ),
        child: Row(
          children: [
            Icon(Icons.school_outlined, color: Colors.grey.shade400),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No schools linked yet — add one from Linked Schools in Preferences.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TabBar(
                controller: _schoolTabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicator: BoxDecoration(
                  color: Colors.indigo.shade700,
                  borderRadius: BorderRadius.circular(24),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.indigo.shade700,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                dividerColor: Colors.transparent,
                onTap: (index) => _switchToSchool(_linkedSchools[index]),
                tabs: _linkedSchools
                    .map((s) => Tab(
                          child: Text(
                            s.displayLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          if (_linkedSchools.length > 1) _buildUnifiedReportButton(),
        ],
      ),
    );
  }

  /// Only shown once >1 school is linked AND the user holds all three
  /// report permissions individually — a role denied one of Daily/Custom/
  /// Termly Report shouldn't see that category's data leak through here.
  Widget _buildUnifiedReportButton() {
    return FutureBuilder<bool>(
      future: _hasUnifiedReportPermission(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            icon: const Icon(Icons.dashboard_customize_outlined, color: Colors.indigo),
            tooltip: 'Unified Report (all schools)',
            onPressed: () => _navigateWithSidebar(
              context,
              const UnifiedReportScreen(),
              null,
            ),
          ),
        );
      },
    );
  }

  Future<bool> _hasUnifiedReportPermission() async {
    final results = await Future.wait([
      PermissionHelper.hasPermission(widget.currentUser, 'daily_report'),
      PermissionHelper.hasPermission(widget.currentUser, 'custom_report'),
      PermissionHelper.hasPermission(widget.currentUser, 'termly_report'),
    ]);
    return results.every((r) => r);
  }

  Widget _quickAccessItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final ds = DisplaySettingsProvider.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Tooltip(
        message: label,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ds.cardPadding * 0.5,
            vertical: ds.cardPadding * 0.4,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: ds.iconSize * 1.1, color: color),
              SizedBox(height: ds.cardPadding * 0.2),
              Text(
                label,
                style: TextStyle(
                  fontSize: ds.subtitleFontSize * 0.75,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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
          // Check if we should show sidebar
          final screenSize = MediaQuery.of(context).size;
          final shortestSide = screenSize.shortestSide;
          final showSidebar = shortestSide >= 700;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => showSidebar
                  ? SidebarScaffold(
                      currentUser: widget.currentUser,
                      currentPageId: pageId,
                      child: page,
                    )
                  : page,
            ),
          ).then((_) => Future.wait([_loadActiveSessionTerm(), _loadLinkedSchools()]));
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
                child: Icon(icon, size: ds.iconSize * 1.6, color: color),
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
}
