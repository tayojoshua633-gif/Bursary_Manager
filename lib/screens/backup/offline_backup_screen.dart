// lib/screens/backup/offline_backup_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/db_backup_helper.dart';
import '../../utils/storage_permission_helper.dart';
import 'selective_restore_dialog.dart';

class OfflineBackupScreen extends StatefulWidget {
  const OfflineBackupScreen({super.key});

  @override
  State<OfflineBackupScreen> createState() => _OfflineBackupScreenState();
}

class _OfflineBackupScreenState extends State<OfflineBackupScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _backups = [];
  String _backupFolderPath = '';

  @override
  void initState() {
    super.initState();
    _loadBackups();
    _loadBackupPath();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    final backups = await DBBackupHelper.getAllBackups();
    if (mounted) {
      setState(() {
        _backups = backups;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBackupPath() async {
    final path = await DBBackupHelper.getBackupFolderPath();
    if (mounted) {
      setState(() => _backupFolderPath = path);
    }
  }

  Future<void> _createBackup() async {
    // Request storage permission before creating backup
    final hasPermission = await StoragePermissionHelper.requestWithExplanation(
      context,
      customMessage: 'Storage permission is required to create and save backup files.\n\n'
          'Your backup files will be stored in the Downloads folder for easy access.',
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

    final result = await DBBackupHelper.backupDatabase();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      _loadBackups();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _backupAndEmail() async {
    // Request storage permission before creating backup
    final hasPermission = await StoragePermissionHelper.requestWithExplanation(
      context,
      customMessage: 'Storage permission is required to create a backup file for emailing.\n\n'
          'The backup file will be created in the Downloads folder.',
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

    final result = await DBBackupHelper.backupAndEmail();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      // Show dialog with instructions
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.email, color: Colors.blue),
              SizedBox(width: 8),
              Text('Email Backup'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Backup created successfully!',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text('File: ${result['filename']}'),
              const SizedBox(height: 12),
              if (result['emailOpened'] == true)
                const Text(
                  'Your email app has been opened. Please attach the backup file manually and send.',
                  style: TextStyle(fontSize: 13),
                )
              else
                const Text(
                  'Could not open email app. You can find the backup file in Downloads/BursaryBackups folder.',
                  style: TextStyle(fontSize: 13, color: Colors.orange),
                ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'To: tysolutionsmultimediatech@gmail.com',
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      'File: ${result['filename']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      _loadBackups();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _restoreBackup(String backupPath, String backupName) async {
    // Show selective restore dialog
    final selectedTables = await showDialog<List<String>>(
      context: context,
      builder: (context) => SelectiveRestoreDialog(
        backupFilePath: backupPath,
        backupFileName: backupName,
      ),
    );

    if (selectedTables == null || selectedTables.isEmpty) return;

    // Perform selective restore
    setState(() => _isLoading = true);

    final restoreResult = await DBBackupHelper.selectiveRestoreDatabase(
      backupPath,
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
                'Please restart the app for changes to take effect.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Close offline backup screen
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

  /// Selective restore from file picker
  Future<void> _pickAndRestoreBackup() async {
    setState(() => _isLoading = true);

    // Step 1: Pick file
    final pickResult = await DBBackupHelper.pickAndRestoreBackup();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!pickResult['success']) {
      if (pickResult['cancelled'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pickResult['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Step 2: Show selective restore dialog
    final filePath = pickResult['filePath'] as String;
    final fileName = pickResult['fileName'] as String;

    final selectedTables = await showDialog<List<String>>(
      context: context,
      builder: (context) => SelectiveRestoreDialog(
        backupFilePath: filePath,
        backupFileName: fileName,
      ),
    );

    if (selectedTables == null || selectedTables.isEmpty) return;

    // Step 3: Perform selective restore
    setState(() => _isLoading = true);

    final restoreResult = await DBBackupHelper.selectiveRestoreDatabase(
      filePath,
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
                'Please restart the app for changes to take effect.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Close offline backup screen
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

  Future<void> _deleteBackup(String backupPath, String backupName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Backup?'),
        content: Text('Are you sure you want to delete:\n\n$backupName'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await DBBackupHelper.deleteBackupFile(backupPath);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      _loadBackups();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete backup'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Change backup directory
  Future<void> _changeBackupDirectory() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Use FilePicker to select a directory
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Backup Directory',
      );

      if (selectedDirectory == null) {
        // User cancelled
        return;
      }

      // Save custom directory to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_backup_directory', selectedDirectory);

      // Reload backup path
      await _loadBackupPath();

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Backup directory changed to:\n$selectedDirectory'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error changing directory: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Reset to default backup directory
  Future<void> _resetToDefaultDirectory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Default Directory?'),
        content: const Text('This will change the backup location back to the default directory.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Remove custom directory from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_backup_directory');

    // Reload backup path
    await _loadBackupPath();
    await _loadBackups();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup directory reset to default'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Backup'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadBackups,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Create Backup Section
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.backup, color: Colors.teal),
                                SizedBox(width: 8),
                                Text(
                                  'Create Backup',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Back up your data to protect against data loss',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),

                            // Create Backup Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _createBackup,
                                icon: const Icon(Icons.save),
                                label: const Text('Create Backup'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Backup & Email Button
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _backupAndEmail,
                                icon: const Icon(Icons.email),
                                label: const Text('Backup & Email'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.teal,
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Backup Location Info with Change Directory buttons
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.folder, size: 20, color: Colors.blue.shade700),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Backup Location:',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              _backupFolderPath,
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _changeBackupDirectory,
                                          icon: const Icon(Icons.folder_open, size: 16),
                                          label: const Text(
                                            'Change Directory',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.blue.shade700,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FutureBuilder<String?>(
                                        future: SharedPreferences.getInstance().then(
                                          (prefs) => prefs.getString('custom_backup_directory'),
                                        ),
                                        builder: (context, snapshot) {
                                          final hasCustomDir = snapshot.data != null;
                                          if (!hasCustomDir) return const SizedBox.shrink();

                                          return Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: _resetToDefaultDirectory,
                                              icon: const Icon(Icons.refresh, size: 16),
                                              label: const Text(
                                                'Reset Default',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.orange.shade700,
                                                padding: const EdgeInsets.symmetric(vertical: 8),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Restore Section
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.restore, color: Colors.orange),
                                SizedBox(width: 8),
                                Text(
                                  'Restore Backup',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Restore your data from a backup file',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),

                            // Restore from File Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _pickAndRestoreBackup,
                                icon: const Icon(Icons.folder_open),
                                label: const Text('Restore from File'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Info box
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, size: 20, color: Colors.orange.shade700),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Select any .db backup file from your device',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Use this to restore from files received via email or downloaded from cloud storage',
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

                    const SizedBox(height: 20),

                    // Existing Backups List
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Available Backups',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_backups.isNotEmpty)
                          Text(
                            '${_backups.length} backup(s)',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    if (_backups.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.backup,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No backups found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Create your first backup to get started',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _backups.length,
                        itemBuilder: (context, index) {
                          final backup = _backups[index];
                          final name = backup['name'] as String;
                          final path = backup['path'] as String;
                          final size = backup['size'] as int;
                          final date = backup['date'] as DateTime;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.teal.shade100,
                                child: const Icon(
                                  Icons.file_present,
                                  color: Colors.teal,
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        DateFormat('dd MMM yyyy, h:mm a').format(date),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.data_usage,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        DBBackupHelper.formatFileSize(size),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  if (value == 'restore') {
                                    _restoreBackup(path, name);
                                  } else if (value == 'delete') {
                                    _deleteBackup(path, name);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'restore',
                                    child: Row(
                                      children: [
                                        Icon(Icons.restore, size: 20),
                                        SizedBox(width: 8),
                                        Text('Restore'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 20, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
