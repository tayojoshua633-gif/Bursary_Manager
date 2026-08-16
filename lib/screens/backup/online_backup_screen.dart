// lib/screens/backup/online_backup_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/db_backup_helper.dart';
import '../../utils/backup_reminder_helper.dart';
import '../../utils/google_drive_backup_helper.dart';
import '../../utils/storage_permission_helper.dart';
import 'selective_restore_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _checkGoogleSignIn();
  }

  /// Check Google Sign-In status
  Future<void> _checkGoogleSignIn() async {
    setState(() => _isLoading = true);

    final isSignedIn = await GoogleDriveBackupHelper.isSignedIn();
    final email = GoogleDriveBackupHelper.getCurrentUserEmail();

    if (mounted) {
      setState(() {
        _isSignedInToGoogle = isSignedIn;
        _googleUserEmail = email;
        _isLoading = false;
      });
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

    // First create a local backup
    final backupResult = await DBBackupHelper.backupDatabase();

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
      // Record backup
      await BackupReminderHelper.recordBackup();
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

    // Show selective restore dialog
    final selectedTables = await showDialog<List<String>>(
      context: context,
      builder: (context) => SelectiveRestoreDialog(
        backupFilePath: downloadPath,
        backupFileName: fileName,
      ),
    );

    if (selectedTables == null || selectedTables.isEmpty) return;

    // Perform selective restore
    setState(() => _isLoading = true);

    final restoreResult = await DBBackupHelper.selectiveRestoreDatabase(
      downloadPath,
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
  Widget build(BuildContext context) {
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
                            ? 'Upload your backups to Google Drive for cloud storage'
                            : 'Sign in to Google to enable cloud backup',
                        style: const TextStyle(color: Colors.grey),
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
