// lib/screens/backup/online_backup_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/db_backup_helper.dart';
import '../../utils/backup_reminder_helper.dart';
import '../../utils/cloud_sync_helper.dart';
import '../../utils/google_drive_backup_helper.dart';
import '../../utils/storage_permission_helper.dart';
import 'selective_restore_dialog.dart';
import '../../widgets/quick_access_sidebar.dart';

class OnlineBackupScreen extends StatefulWidget {
  const OnlineBackupScreen({super.key});

  @override
  State<OnlineBackupScreen> createState() => _OnlineBackupScreenState();
}

class _OnlineBackupScreenState extends State<OnlineBackupScreen> {
  bool _isLoading = false;

  // Google Drive state
  bool _isSignedInToGoogle = false;
  String? _googleUserEmail;

  // Last successful online backup
  DateTime? _lastOnlineBackup;

  // Automatic backup settings
  bool _autoBackup = false;
  int _autoBackupInterval = 1;
  bool _isReadOnlyDevice = false;
  DateTime? _nextAutoBackup;

  @override
  void initState() {
    super.initState();
    _checkGoogleSignIn();
  }

  Future<void> _loadAutoBackupSettings() async {
    final results = await Future.wait([
      CloudSyncHelper.isAutoBackupEnabled(),
      CloudSyncHelper.getAutoBackupIntervalHours(),
      CloudSyncHelper.isReadOnlyMode(),
      CloudSyncHelper.getNextAutoBackupDue(),
    ]);
    if (!mounted) return;
    setState(() {
      _autoBackup = results[0] as bool;
      _autoBackupInterval = results[1] as int;
      _isReadOnlyDevice = results[2] as bool;
      _nextAutoBackup = results[3] as DateTime?;
    });
  }

  Future<void> _setAutoBackup(bool enabled) async {
    await CloudSyncHelper.setAutoBackupEnabled(enabled);
    await _loadAutoBackupSettings();
    // Restart the timer so a newly enabled periodic backup runs if already due.
    if (enabled) await CloudSyncHelper.startPeriodicAutoBackup();
  }

  Future<void> _setAutoBackupInterval(int hours) async {
    await CloudSyncHelper.setAutoBackupIntervalHours(hours);
    await _loadAutoBackupSettings();
    await CloudSyncHelper.startPeriodicAutoBackup();
  }

  /// Load the last online backup time: the locally recorded time, refreshed
  /// from the newest file on Google Drive (covers backups from other devices).
  Future<void> _loadLastOnlineBackup() async {
    final local = await BackupReminderHelper.getLastOnlineBackup();
    if (mounted) setState(() => _lastOnlineBackup = local);

    if (!_isSignedInToGoogle) return;
    final backups = await GoogleDriveBackupHelper.listBackupsInDrive();
    if (backups.isEmpty) return;
    final remote = (backups.first['modifiedTime'] as DateTime?)?.toLocal();
    if (remote == null) return;
    if (local == null || remote.isAfter(local)) {
      await BackupReminderHelper.recordOnlineBackup(remote);
      if (mounted) setState(() => _lastOnlineBackup = remote);
    }
  }

  String _formatLastBackup(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    final String ago;
    if (diff.inMinutes < 1) {
      ago = 'just now';
    } else if (diff.inHours < 1) {
      ago = '${diff.inMinutes} min ago';
    } else if (diff.inDays < 1) {
      ago = '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    } else {
      ago = '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    return '${DateFormat('EEE, d MMM yyyy • h:mm a').format(dt)} ($ago)';
  }

  /// Check Google Sign-In status
  Future<void> _checkGoogleSignIn() async {
    setState(() => _isLoading = true);

    final isSignedIn = await GoogleDriveBackupHelper.isSignedIn();
    final email = await GoogleDriveBackupHelper.getEmailAsync();

    if (mounted) {
      setState(() {
        _isSignedInToGoogle = isSignedIn;
        _googleUserEmail = email;
        _isLoading = false;
      });
      _loadLastOnlineBackup();
      _loadAutoBackupSettings();
    }
  }

  /// Sign in to Google account
  Future<void> _signInToGoogle() async {
    setState(() => _isLoading = true);

    final result = await GoogleDriveBackupHelper.signIn();

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: result['success'] ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // Refresh sign-in status
    await _checkGoogleSignIn();
  }

  /// Sign out from Google account
  Future<void> _signOutFromGoogle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out from Google?'),
        content: const Text('You will need to sign in again to use Google Drive backup.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await GoogleDriveBackupHelper.signOut();
    await _checkGoogleSignIn();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signed out from Google'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  /// Backup to Google Drive
  Future<void> _backupToGoogleDrive() async {
    // Request storage permission before creating backup
    final hasPermission = await StoragePermissionHelper.requestWithExplanation(
      context,
      customMessage: 'Storage permission is required to create a backup file before uploading to Google Drive.\n\n'
          'A temporary backup file will be created on your device.',
    );

    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission is required to create backups'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    // First create a local backup archive (database + photos)
    final backupResult = await DBBackupHelper.createOnlineBackupArchive();

    if (!backupResult['success']) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(backupResult['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Upload to Google Drive
    final uploadResult = await GoogleDriveBackupHelper.uploadBackupToDrive(
      backupResult['filePath'],
    );

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(uploadResult['message']),
          backgroundColor: uploadResult['success'] ? Colors.green : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    if (uploadResult['success']) {
      // Record backup (also restarts the auto-backup countdown)
      await CloudSyncHelper.recordSuccessfulBackup();
      if (!mounted) return;
      setState(() => _lastOnlineBackup = DateTime.now());
      await _loadAutoBackupSettings();
    }
  }

  /// Show Google Drive backups and allow restore
  Future<void> _showGoogleDriveBackups() async {
    setState(() => _isLoading = true);

    // Fetch backups from Google Drive
    final backups = await GoogleDriveBackupHelper.listBackupsInDrive();

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No backups found in Google Drive'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show dialog with list of backups
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from Google Drive'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: backups.length,
            itemBuilder: (context, index) {
              final backup = backups[index];
              final fileName = backup['name'] as String;
              final fileSize = backup['size'] as String?;
              final modifiedTime = backup['modifiedTime'] as DateTime?;

              return Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud, color: Colors.blue),
                  title: Text(
                    fileName,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (fileSize != null)
                        Text('Size: ${DBBackupHelper.formatFileSize(int.tryParse(fileSize) ?? 0)}'),
                      if (modifiedTime != null)
                        Text('Modified: ${DateFormat('MMM d, yyyy h:mm a').format(modifiedTime)}'),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.download, color: Colors.green),
                    tooltip: 'Restore this backup',
                    onPressed: () {
                      Navigator.pop(context);
                      _restoreFromGoogleDrive(backup);
                    },
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Restore backup from Google Drive
  Future<void> _restoreFromGoogleDrive(Map<String, dynamic> backup) async {
    final fileName = backup['name'] as String;
    final fileId = backup['id'] as String;

    if (!mounted) return;

    // Request storage permission before proceeding
    final hasPermission = await StoragePermissionHelper.requestWithExplanation(
      context,
      customMessage: 'Storage permission is required to download and restore your backup from Google Drive.\n\n'
          'The backup file will be temporarily saved to your device storage during the restore process.',
    );

    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission is required to restore backups from Google Drive'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    // Download backup to temp location
    final backupFolder = await DBBackupHelper.getBackupFolderPath();
    final downloadPath = '$backupFolder/temp_restore_$fileName';

    final downloadResult = await GoogleDriveBackupHelper.downloadBackupFromDrive(
      fileId,
      downloadPath,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!downloadResult['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(downloadResult['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Newer backups are a zip archive (database.db + photos/). Extract the
    // database out (and restore any photos) before working with it; legacy
    // backups are already a raw .db file and can be used as-is.
    String restoreDbPath = downloadPath;
    if (fileName.toLowerCase().endsWith('.zip')) {
      final extractedDbPath = '$downloadPath.db';
      final extracted = await DBBackupHelper.extractDatabaseFromArchive(
        downloadPath,
        extractedDbPath,
      );
      if (extracted == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Backup archive is missing a database'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      restoreDbPath = extractedDbPath;
    }

    if (!mounted) return;

    // Show selective restore dialog
    final selectedTables = await showDialog<List<String>>(
      context: context,
      builder: (context) => SelectiveRestoreDialog(
        backupFilePath: restoreDbPath,
        backupFileName: fileName,
      ),
    );

    if (selectedTables == null || selectedTables.isEmpty) return;

    // Perform selective restore
    setState(() => _isLoading = true);

    final restoreResult = await DBBackupHelper.selectiveRestoreDatabase(
      restoreDbPath,
      selectedTables,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (restoreResult['success']) {
      final tablesRestored = restoreResult['tablesRestored'] as int;
      final recordsRestored = restoreResult['recordsRestored'] as int;

      // Show success dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Restore Complete'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Selective restore completed successfully!',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tables Restored:', style: TextStyle(fontSize: 13)),
                        Text(
                          '$tablesRestored',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Records Restored:', style: TextStyle(fontSize: 13)),
                        Text(
                          NumberFormat('#,###').format(recordsRestored),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please restart the app to complete the restore process.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Close online backup screen
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      // Show error dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Restore Failed'),
            ],
          ),
          content: Text(restoreResult['message']),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => QuickAccessScaffold(
        group: QuickAccessGroup.backup,
        currentId: 'online',
        child: _buildScreenContent(context),
      );

  Widget _buildAutoBackupSection() {
    final canEdit = !_isReadOnlyDevice;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Automatic Backup',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Auto-Backup to Google Drive',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Backs up your data and photos to Google Drive automatically.',
              style: TextStyle(fontSize: 12),
            ),
            value: _autoBackup && canEdit,
            activeThumbColor: Colors.green.shade700,
            onChanged: canEdit ? _setAutoBackup : null,
          ),
          if (_isReadOnlyDevice)
            Text(
              '⚠ This device is in Read-Only mode (linked schools), so it does not back up to Drive.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          if (_autoBackup && canEdit) ...[
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              initialValue: _autoBackupInterval,
              decoration: const InputDecoration(
                labelText: 'Backup frequency',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.timer_outlined),
                isDense: true,
              ),
              items: [
                for (final h in CloudSyncHelper.autoBackupIntervalOptions)
                  DropdownMenuItem(
                    value: h,
                    child: Text(CloudSyncHelper.describeInterval(h)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) _setAutoBackupInterval(v);
              },
            ),
            const SizedBox(height: 8),
            Text(
              _nextAutoBackup == null || !_nextAutoBackup!.isAfter(DateTime.now())
                  ? 'Next backup: due now (runs while the app is open).'
                  : 'Next backup: ${DateFormat('EEE, d MMM yyyy • h:mm a').format(_nextAutoBackup!)}'
                      ' (runs while the app is open).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScreenContent(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Backup'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(Icons.cloud, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Google Drive Backup',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isSignedInToGoogle
                            ? 'Upload your data and photos to Google Drive for cloud storage'
                            : 'Sign in to Google to enable cloud backup',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      // Last online backup
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _lastOnlineBackup == null
                              ? Colors.orange.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _lastOnlineBackup == null
                                ? Colors.orange.shade200
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.history,
                              size: 20,
                              color: _lastOnlineBackup == null
                                  ? Colors.orange.shade700
                                  : Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Last online backup:',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    _lastOnlineBackup == null
                                        ? 'Never backed up to Google Drive'
                                        : _formatLastBackup(_lastOnlineBackup!),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sign-in status
                      if (_isSignedInToGoogle) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Signed in as:',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      _googleUserEmail ?? 'Unknown',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _signOutFromGoogle,
                                icon: const Icon(Icons.logout, size: 20),
                                tooltip: 'Sign Out',
                                color: Colors.red.shade700,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Backup to Drive button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _backupToGoogleDrive,
                            icon: const Icon(Icons.cloud_upload),
                            label: const Text('Backup to Google Drive'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Restore from Drive button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _showGoogleDriveBackups,
                            icon: const Icon(Icons.cloud_download),
                            label: const Text('Restore from Google Drive'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        _buildAutoBackupSection(),
                      ] else ...[
                        // Sign in button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _signInToGoogle,
                            icon: const Icon(Icons.login),
                            label: const Text('Sign in with Google'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Info box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cloud Backup Benefits',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '• Includes your database, staff/student photos and school logo\n'
                                    '• Access backups from anywhere\n'
                                    '• Automatic organization in "Bursary Backups" folder\n'
                                    '• Free with your Google account\n'
                                    '• Secure cloud storage',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
