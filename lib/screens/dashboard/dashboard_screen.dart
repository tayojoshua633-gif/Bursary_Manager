import 'package:flutter/material.dart';
import 'package:bursary_manager/data/database_helper_wrapper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// Preferences menu screens
import '../backup/backup_screen.dart';
import '../license/license_management_screen.dart';
import '../settings/thermal_printer_screen.dart';
import '../settings/display_settings_screen.dart';
import '../settings/security_settings_screen.dart';
import '../settings/clear_data_screen.dart';
import '../permissions/permission_management_screen.dart';
import '../auth/user_management_screen.dart';

// Permission helper
import '../../utils/permission_helper.dart';
import '../../utils/navigation_helper.dart';

// Backup reminder helper
import '../../utils/backup_reminder_helper.dart';
import '../../utils/db_backup_helper.dart';
import '../../utils/display_settings_helper.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  int _totalActiveStudents = 0;
  int _totalInactiveStudents = 0;

  // CORRECTED: Term-specific financial data
  double _totalBills = 0;
  double _totalPayments = 0;
  double _outstanding = 0;
  double _totalOverpaid = 0;

  String _currentTerm = "";
  String _currentSession = "";

  bool _loading = true;
  Map<String, dynamic>? _currentUser;

  // Financial data visibility
  bool _isFinancialDataVisible = false;
  static const String _viewingPin = "123123";

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadDashboardData();

    // Check for backup reminder after a short delay (let dashboard load first)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _checkBackupReminder();
    });
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';

    setState(() {
      _currentUser = {
        'id': userId,
        'userType': userType,
        'username': username,
      };
    });
  }

  Future<void> _loadDashboardData() async {
    if (mounted) setState(() => _loading = true);

    try {
      // Use the database helper methods instead of raw queries
      final activeStudents = await _db.getActiveStudents();
      _totalActiveStudents = activeStudents.length;

      final inactiveStudents = await _db.getInactiveStudents();
      _totalInactiveStudents = inactiveStudents.length;

      // Get current term and session
      _currentTerm = await _db.getActiveTerm();
      final sessionData = await _db.getActiveSession();
      _currentSession = sessionData?['sessionName'] ?? "";

      // Get financial data using repository methods (works in all modes)
      _totalBills = await _db.getTotalBillsForTermSession(
        term: _currentTerm,
        session: _currentSession,
      );

      _totalPayments = await _db.getTotalPaymentsForTermSession(
        term: _currentTerm,
        session: _currentSession,
      );

      // Calculate outstanding for current term
      _outstanding = _totalBills - _totalPayments;

      // Calculate total overpaid (students who paid more than their grand total)
      final database = await _db.database;
      final targetKey = DatabaseHelperWrapper.termSortKey(_currentTerm, _currentSession);
      final b2Key = DatabaseHelperWrapper.sqlTermKeyExpr('b2');
      final p2Key = DatabaseHelperWrapper.sqlTermKeyExpr('p2');
      final overpaidQuery = await database.rawQuery('''
        WITH student_totals AS (
          SELECT
            s.id,
            (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0))
            + (
                COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                          WHERE b2.studentId = s.id AND $b2Key < ?), 0)
                -
                COALESCE((SELECT SUM(p2.amount) FROM payments p2
                          WHERE p2.studentId = s.id AND $p2Key < ?), 0)
              ) as grandTotal,
            COALESCE(
              (SELECT SUM(amount) FROM payments
               WHERE studentId = s.id AND term = ? AND session = ?), 0
            ) as totalPaid
          FROM students s
          LEFT JOIN student_bills b ON s.id = b.studentId
            AND b.term = ? AND b.session = ?
          WHERE s.isActive = 1
        )
        SELECT COALESCE(SUM(CASE
          WHEN (totalPaid - grandTotal) > 0 THEN (totalPaid - grandTotal)
          ELSE 0
        END), 0) as totalOverpaid
        FROM student_totals
      ''', [targetKey, targetKey, _currentTerm, _currentSession, _currentTerm, _currentSession]);

      if (overpaidQuery.isNotEmpty) {
        _totalOverpaid = (overpaidQuery.first['totalOverpaid'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (e, st) {
      debugPrint("Dashboard load error: $e\n$st");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Show PIN dialog to view financial data
  Future<void> _showPinDialog() async {
    final pinController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock, color: Colors.blue, size: 28),
            SizedBox(width: 12),
            Text('Enter Viewing PIN'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter PIN to view financial data:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'PIN',
                hintText: 'Enter 6-digit PIN',
                prefixIcon: Icon(Icons.pin),
                counterText: '',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (pinController.text == _viewingPin) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Incorrect PIN. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _isFinancialDataVisible = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Financial data is now visible'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Toggle financial data visibility
  void _toggleFinancialDataVisibility() {
    if (_isFinancialDataVisible) {
      // Hide data
      setState(() {
        _isFinancialDataVisible = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Financial data is now hidden'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Show PIN dialog to view data
      _showPinDialog();
    }
  }

  // Check if backup reminder should be shown
  Future<void> _checkBackupReminder() async {
    final level = await BackupReminderHelper.shouldShowReminder();

    if (level != BackupReminderLevel.none && mounted) {
      await BackupReminderHelper.recordReminderShown();
      _showBackupReminderDialog(level);
    }
  }

  // Show backup reminder dialog based on priority level
  Future<void> _showBackupReminderDialog(BackupReminderLevel level) async {
    final message = await BackupReminderHelper.getReminderMessage(level);
    final days = await BackupReminderHelper.getDaysSinceLastBackup();
    final transactions = await BackupReminderHelper.getTransactionsSinceBackup();

    // Determine dialog colors and properties based on level
    Color titleColor;
    Color iconColor;
    IconData icon;
    bool canDismiss;

    switch (level) {
      case BackupReminderLevel.gentle:
        titleColor = Colors.blue;
        iconColor = Colors.blue;
        icon = Icons.backup;
        canDismiss = true;
        break;
      case BackupReminderLevel.medium:
        titleColor = Colors.orange.shade700;
        iconColor = Colors.orange;
        icon = Icons.warning;
        canDismiss = true;
        break;
      case BackupReminderLevel.critical:
        titleColor = Colors.red.shade700;
        iconColor = Colors.red;
        icon = Icons.error;
        canDismiss = false;
        break;
      case BackupReminderLevel.none:
        return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: canDismiss,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: iconColor, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                level == BackupReminderLevel.critical
                    ? 'BACKUP REQUIRED'
                    : level == BackupReminderLevel.medium
                        ? 'Backup Recommended'
                        : 'Backup Reminder',
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 16),
              // Stats
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Days since backup:', style: TextStyle(fontSize: 13)),
                        Text(
                          days == 999 ? 'Never' : '$days days',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: days >= 14 ? Colors.red : days >= 7 ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Transactions:', style: TextStyle(fontSize: 13)),
                        Text(
                          '$transactions',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: transactions >= 50 ? Colors.orange : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Dismiss options (only for gentle and medium levels)
          if (canDismiss) ...[
            TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await BackupReminderHelper.dismissReminder(DismissDuration.fourHours);
                if (mounted) navigator.pop();
              },
              child: const Text('Later (4h)'),
            ),
            if (level == BackupReminderLevel.gentle)
              TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await BackupReminderHelper.dismissReminder(DismissDuration.laterToday);
                  if (mounted) navigator.pop();
                },
                child: const Text('Tonight'),
              ),
          ],
          // Backup now button
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _performBackup();
            },
            icon: const Icon(Icons.backup),
            label: const Text('Backup Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: level == BackupReminderLevel.critical ? Colors.red : Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Perform backup
  Future<void> _performBackup() async {
    try {
      // Show loading
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Perform backup
      final result = await DBBackupHelper.backupDatabase();

      if (!mounted) return;
      navigator.pop(); // Close loading

      if (result['success']) {
        // Record backup
        await BackupReminderHelper.recordBackup();
        await BackupReminderHelper.clearDismissal();

        messenger.showSnackBar(
          SnackBar(
            content: Text('Backup created successfully!\nSaved to: ${result['filePath'] ?? 'default location'}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Backup failed: ${result['message'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating backup: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Combined student stats card
  Widget _studentStatsCard(DisplaySettings ds) {
    return Container(
      margin: EdgeInsets.only(bottom: ds.cardPadding * 0.75),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ds.cardPadding * 0.5),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.people, size: ds.iconSize, color: Colors.indigo.shade700),
                ),
                SizedBox(width: ds.cardPadding * 0.75),
                Text(
                  "Student Overview",
                  style: TextStyle(
                    fontSize: ds.subtitleFontSize,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            SizedBox(height: ds.cardPadding),
            Row(
              children: [
                Icon(Icons.person, size: ds.iconSize, color: Colors.green),
                SizedBox(width: ds.cardPadding * 0.5),
                Text(
                  "Active Students:",
                  style: TextStyle(fontSize: ds.bodyFontSize, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  "$_totalActiveStudents",
                  style: TextStyle(
                    fontSize: ds.titleFontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            if (_totalInactiveStudents > 0) ...[
              SizedBox(height: ds.cardPadding * 0.75),
              const Divider(height: 1),
              SizedBox(height: ds.cardPadding * 0.75),
              Row(
                children: [
                  Icon(Icons.person_off, size: ds.iconSize, color: Colors.orange),
                  SizedBox(width: ds.cardPadding * 0.5),
                  Text(
                    "Inactive Students:",
                    style: TextStyle(fontSize: ds.bodyFontSize, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Text(
                    "$_totalInactiveStudents",
                    style: TextStyle(
                      fontSize: ds.titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _financialSummaryCard(DisplaySettings ds) {
    final formatter = NumberFormat('#,##0.00');
    return Container(
      margin: EdgeInsets.only(bottom: ds.cardPadding * 0.75),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ds.cardPadding * 0.5),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.account_balance_wallet, size: ds.iconSize, color: Colors.blue.shade700),
                ),
                SizedBox(width: ds.cardPadding * 0.75),
                Expanded(
                  child: Text(
                    "Term-Specific Financial Data",
                    style: TextStyle(
                      fontSize: ds.subtitleFontSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                // View/Hide button
                IconButton(
                  onPressed: _toggleFinancialDataVisibility,
                  icon: Icon(
                    _isFinancialDataVisible ? Icons.visibility_off : Icons.visibility,
                    color: Colors.blue.shade700,
                    size: ds.iconSize,
                  ),
                  tooltip: _isFinancialDataVisible ? 'Hide amounts' : 'View amounts',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    padding: EdgeInsets.all(ds.cardPadding * 0.5),
                  ),
                ),
              ],
            ),
            SizedBox(height: ds.cardPadding),
            _financialRow("Total Fees Expected", formatter.format(_totalBills), Colors.green, Icons.receipt_long, ds),
            SizedBox(height: ds.cardPadding * 0.75),
            const Divider(height: 1),
            SizedBox(height: ds.cardPadding * 0.75),
            _financialRow("Total Payments Received", formatter.format(_totalPayments), Colors.blue, Icons.payment, ds),
            SizedBox(height: ds.cardPadding * 0.75),
            const Divider(height: 1),
            SizedBox(height: ds.cardPadding * 0.75),
            _financialRow("Outstanding Balance", formatter.format(_outstanding), Colors.red, Icons.warning_amber, ds),
            if (_totalOverpaid > 0) ...[
              SizedBox(height: ds.cardPadding * 0.75),
              const Divider(height: 1),
              SizedBox(height: ds.cardPadding * 0.75),
              _financialRow("Total Overpaid", formatter.format(_totalOverpaid), Colors.purple, Icons.account_balance, ds),
            ],
            // Explanation note
            SizedBox(height: ds.cardPadding),
            Container(
              padding: EdgeInsets.all(ds.cardPadding * 0.5),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: ds.iconSize * 0.8, color: Colors.grey.shade600),
                  SizedBox(width: ds.cardPadding * 0.5),
                  Expanded(
                    child: Text(
                      "Fees Expected: Active students only\nPayments Received: All students (for reporting accuracy)",
                      style: TextStyle(
                        fontSize: ds.bodyFontSize * 0.8,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _financialRow(String label, String value, Color color, IconData icon, DisplaySettings ds) {
    // Show masked value if data is hidden
    final displayValue = _isFinancialDataVisible ? "₦$value" : "₦XXXX XXXXX";

    return Row(
      children: [
        Icon(icon, size: ds.iconSize, color: color),
        SizedBox(width: ds.cardPadding * 0.75),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: ds.bodyFontSize,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          displayValue,
          style: TextStyle(
            fontSize: ds.subtitleFontSize,
            fontWeight: FontWeight.bold,
            color: _isFinancialDataVisible ? color : Colors.grey.shade500,
            letterSpacing: _isFinancialDataVisible ? 0 : 2,
          ),
        ),
      ],
    );
  }

  /// Permission-checked quick button - only shows if user has permission
  Widget _permissionQuickButton(
    String title,
    IconData icon,
    Widget screen,
    BuildContext context,
    String module,
    MaterialColor color,
    DisplaySettings ds,
  ) {
    // Return empty expanded widget if no current user loaded yet
    if (_currentUser == null) {
      return const Expanded(child: SizedBox.shrink());
    }

    return Expanded(
      child: FutureBuilder<bool>(
        future: PermissionHelper.hasPermission(_currentUser!, module),
        builder: (context, snapshot) {
          // Hide button if no permission
          if (snapshot.data != true) {
            return const SizedBox.shrink();
          }

          // Show button if has permission
          return Container(
            margin: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.375),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  await NavigationHelper.pushWithSidebar(
                    context,
                    page: screen,
                    currentUser: _currentUser ?? {},
                  );
                  // Auto-refresh dashboard data when returning from any child screen
                  // This ensures Term-Specific Financial Data is always up-to-date
                  _loadDashboardData();
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.shade50,
                        color.shade100.withValues(alpha: 0.3),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: color.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.symmetric(vertical: ds.cardPadding, horizontal: ds.cardPadding * 0.75),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.all(ds.cardPadding * 0.75),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, size: ds.iconSize * 1.5, color: color.shade700),
                      ),
                      SizedBox(height: ds.cardPadding * 0.75),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: ds.bodyFontSize * 0.9,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Quick button without permission check - always visible
  Widget _quickButton(
    String title,
    IconData icon,
    Widget screen,
    BuildContext context,
    MaterialColor color,
    DisplaySettings ds,
  ) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.375),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              await NavigationHelper.pushWithSidebar(
                context,
                page: screen,
                currentUser: _currentUser ?? {},
              );
              _loadDashboardData();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.shade50,
                    color.shade100.withValues(alpha: 0.3),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: EdgeInsets.symmetric(vertical: ds.cardPadding, horizontal: ds.cardPadding * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(ds.cardPadding * 0.75),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: ds.iconSize * 1.5, color: color.shade700),
                  ),
                  SizedBox(height: ds.cardPadding * 0.75),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: ds.bodyFontSize * 0.9,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade700, Colors.blue.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Dashboard",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: ds.titleFontSize,
              ),
            ),
            if (_currentTerm.isNotEmpty && _currentSession.isNotEmpty)
              Text(
                "$_currentTerm - $_currentSession",
                style: TextStyle(
                  fontSize: ds.bodyFontSize * 0.85,
                  fontWeight: FontWeight.normal,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.grey.shade50,
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadDashboardData,
                child: ListView(
                  padding: EdgeInsets.all(ds.cardPadding),
                  children: [
                  // Combined student stats card
                  _studentStatsCard(ds),

                  // Term-specific financial stats - Combined Card
                  _financialSummaryCard(ds),

                  SizedBox(height: ds.cardPadding * 1.2),
                  // Section Header
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(ds.cardPadding * 0.5),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.dashboard_customize,
                          size: ds.iconSize,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      SizedBox(width: ds.cardPadding * 0.75),
                      Text(
                        "Quick Access",
                        style: TextStyle(
                          fontSize: ds.titleFontSize,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ds.cardPadding),

                  // ROW 1 - Backup & License
                  Row(
                    children: [
                      _permissionQuickButton(
                        "Backup",
                        Icons.save_alt_outlined,
                        const BackupScreen(),
                        context,
                        'backup',
                        Colors.blueGrey,
                        ds,
                      ),
                      _permissionQuickButton(
                        "License",
                        Icons.verified_user_outlined,
                        const LicenseManagementScreen(),
                        context,
                        'license_management',
                        Colors.green,
                        ds,
                      ),
                    ],
                  ),

                  // ROW 2 - Thermal Printer & Display Settings
                  Row(
                    children: [
                      _quickButton(
                        "Thermal Printer",
                        Icons.print_outlined,
                        const ThermalPrinterScreen(),
                        context,
                        Colors.indigo,
                        ds,
                      ),
                      _quickButton(
                        "Display Settings",
                        Icons.display_settings,
                        const DisplaySettingsScreen(),
                        context,
                        Colors.teal,
                        ds,
                      ),
                    ],
                  ),

                  // ROW 3 - Security & Data Management
                  Row(
                    children: [
                      _quickButton(
                        "Security",
                        Icons.security,
                        const SecuritySettingsScreen(),
                        context,
                        Colors.red,
                        ds,
                      ),
                      _quickButton(
                        "Data Management",
                        Icons.cleaning_services_outlined,
                        const ClearDataScreen(),
                        context,
                        Colors.orange,
                        ds,
                      ),
                    ],
                  ),

                  // ROW 4 - Permissions & User Management (Super Admin Only)
                  if (_currentUser != null && _currentUser!['userType'] == 'super_admin')
                    Row(
                      children: [
                        _quickButton(
                          "Permissions",
                          Icons.admin_panel_settings,
                          PermissionManagementScreen(currentUser: _currentUser!),
                          context,
                          Colors.purple,
                          ds,
                        ),
                        _quickButton(
                          "User Management",
                          Icons.people_outline,
                          UserManagementScreen(currentUser: _currentUser!),
                          context,
                          Colors.deepOrange,
                          ds,
                        ),
                      ],
                    ),
                ],
              ),
            ),
      ),
    );
  }
}