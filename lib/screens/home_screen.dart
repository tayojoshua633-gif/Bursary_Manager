// lib/screens/home_screen.dart
import 'package:flutter/material.dart';

import 'students/student_list_screen.dart';
import 'students/student_promotion_screen.dart';
import 'classes/class_list_screen.dart';
import 'fees/fee_item_list_screen.dart';
import 'billing/bill_student_select_screen.dart';
import 'payments/payment_student_select_screen.dart';
import 'school_profile/school_profile_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'backup/backup_screen.dart';
import 'sessions/session_term_management_screen.dart';
import 'auth/welcome_screen.dart';
import 'auth/user_management_screen.dart';
import 'reports/debtors_list_screen.dart';
import 'license/license_management_screen.dart'; // NEW: License Management
import '../utils/license_checker.dart'; // NEW: License Checker

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const HomeScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _licenseStatus;

  @override
  void initState() {
    super.initState();
    // Check license status and show warning if needed
    _checkLicenseStatus();
  }

  Future<void> _checkLicenseStatus() async {
    // Get license status
    final status = await LicenseChecker.getLicenseStatus();
    
    if (mounted) {
      setState(() {
        _licenseStatus = status;
      });
      
      // Show expiry warning if needed
      LicenseChecker.showExpiryWarningIfNeeded(context);
    }
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

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = widget.currentUser['userType'] == 'super_admin';
    final username = widget.currentUser['username'] ?? 'User';
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('School Bursary Manager'),
        centerTitle: true,
        actions: [
          // License Status Indicator
          _buildLicenseIndicator(),
          
          const SizedBox(width: 8),
          
          // User Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    isSuperAdmin
                        ? Icons.admin_panel_settings
                        : Icons.person,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    username,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          // Logout Button
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: isLandscape ? 3 : 2,
        padding: const EdgeInsets.all(16),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: isLandscape ? 1.8 : 0.85,
        children: [
          _menuCard(
            context,
            title: 'Dashboard',
            subtitle: 'Summary & statistics',
            icon: Icons.dashboard_outlined,
            color: Colors.blue,
            page: const DashboardScreen(),
          ),

          _menuCard(
            context,
            title: 'Session & Term',
            subtitle: 'Manage sessions',
            icon: Icons.date_range_outlined,
            color: Colors.purple,
            page: const SessionTermManagementScreen(),
          ),

          _menuCard(
            context,
            title: 'Students',
            subtitle: 'Manage students',
            icon: Icons.person_outline,
            color: Colors.green,
            page: const StudentListScreen(),
          ),

          _menuCard(
            context,
            title: 'Promote Students',
            subtitle: 'Move to next class',
            icon: Icons.arrow_upward_outlined,
            color: Colors.deepPurple,
            page: const StudentPromotionScreen(),
          ),

          _menuCard(
            context,
            title: 'Classes & Arms',
            subtitle: 'Configure classes',
            icon: Icons.school_outlined,
            color: Colors.orange,
            page: const ClassListScreen(),
          ),

          _menuCard(
            context,
            title: 'Fee Items',
            subtitle: 'Define & assign fees',
            icon: Icons.payments_outlined,
            color: Colors.teal,
            page: const FeeItemListScreen(),
          ),

          _menuCard(
            context,
            title: 'Student Bills',
            subtitle: 'Generate bills',
            icon: Icons.receipt_long_outlined,
            color: Colors.indigo,
            page: const BillStudentSelectScreen(),
          ),

          _menuCard(
            context,
            title: 'Payments',
            subtitle: 'Record payments',
            icon: Icons.attach_money_outlined,
            color: Colors.lightGreen,
            page: const PaymentStudentSelectScreen(),
          ),

          _menuCard(
            context,
            title: 'Debtors List',
            subtitle: 'Track outstanding payments',
            icon: Icons.money_off_outlined,
            color: Colors.red,
            page: const DebtorsListScreen(),
          ),

          _menuCard(
            context,
            title: 'School Profile',
            subtitle: 'School info & logo',
            icon: Icons.account_balance_outlined,
            color: Colors.deepPurple,
            page: const SchoolProfileScreen(),
          ),

          // User Management (Super Admin Only)
          if (isSuperAdmin)
            _menuCard(
              context,
              title: 'User Management',
              subtitle: 'Manage user accounts',
              icon: Icons.manage_accounts_outlined,
              color: Colors.red,
              page: UserManagementScreen(currentUser: widget.currentUser),
            ),

          // License Management (Super Admin Only)
          if (isSuperAdmin)
            _menuCard(
              context,
              title: 'License',
              subtitle: 'Manage license',
              icon: Icons.vpn_key_outlined,
              color: Colors.amber,
              page: const LicenseManagementScreen(),
            ),

          _menuCard(
            context,
            title: 'Backup',
            subtitle: 'Save & restore data',
            icon: Icons.save_alt_outlined,
            color: Colors.blueGrey,
            page: const BackupScreen(),
          ),
        ],
      ),
    );
  }

  /// Build license status indicator in AppBar
  Widget _buildLicenseIndicator() {
    if (_licenseStatus == null) {
      return const SizedBox.shrink();
    }

    final isValid = _licenseStatus!['valid'] == true;
    final isTrial = _licenseStatus!['isTrial'] == true;
    final isLifetime = _licenseStatus!['isLifetime'] == true;
    final daysRemaining = _licenseStatus!['daysRemaining'] as int?;

    // Determine indicator color and icon
    Color indicatorColor;
    IconData indicatorIcon;
    String tooltipText;

    if (!isValid) {
      indicatorColor = Colors.red;
      indicatorIcon = Icons.error;
      tooltipText = 'License Invalid/Expired';
    } else if (isTrial) {
      if (daysRemaining != null && daysRemaining <= 7) {
        indicatorColor = Colors.orange;
        indicatorIcon = Icons.warning;
        tooltipText = 'Trial expires in $daysRemaining days';
      } else {
        indicatorColor = Colors.blue;
        indicatorIcon = Icons.timer;
        tooltipText = isTrial ? 'Trial: $daysRemaining days left' : 'Trial Active';
      }
    } else if (isLifetime) {
      indicatorColor = Colors.green;
      indicatorIcon = Icons.verified;
      tooltipText = 'Lifetime License';
    } else if (daysRemaining != null && daysRemaining <= 7) {
      indicatorColor = Colors.orange;
      indicatorIcon = Icons.warning;
      tooltipText = 'License expires in $daysRemaining days';
    } else {
      indicatorColor = Colors.green;
      indicatorIcon = Icons.check_circle;
      tooltipText = daysRemaining != null 
          ? 'License Active: $daysRemaining days left'
          : 'License Active';
    }

    return IconButton(
      icon: Icon(indicatorIcon, color: indicatorColor),
      tooltip: tooltipText,
      onPressed: () {
        // Navigate to license management screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LicenseManagementScreen(),
          ),
        ).then((_) => _checkLicenseStatus()); // Refresh status when returning
      },
    );
  }

  Widget _menuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget page,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => page),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
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