import 'package:flutter/material.dart';
import 'package:bursary_manager/utils/db_backup_helper.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _loading = false;

  Future<void> _performBackup() async {
    setState(() => _loading = true);

    final success = await DBBackupHelper.backupDatabase();

    if (!mounted) return; // FIX 1 — async safe

    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? "Backup saved successfully" : "Backup failed"),
      ),
    );
  }

  Future<void> _performRestore() async {
    setState(() => _loading = true);

    final success = await DBBackupHelper.restoreDatabase();

    if (!mounted) return; // FIX 2 — async safe

    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? "Database restored!" : "Restore failed"),
      ),
    );
  }

  Future<void> _deleteBackup() async {
    setState(() => _loading = true);

    final success = await DBBackupHelper.deleteBackupFile();

    if (!mounted) return; // FIX 3 — async safe

    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? "Backup deleted" : "Delete failed"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Database Backup & Restore")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: _performBackup,
                    icon: const Icon(Icons.backup),
                    label: const Text("Backup Database"),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    onPressed: _performRestore,
                    icon: const Icon(Icons.restore),
                    label: const Text("Restore Database"),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    onPressed: _deleteBackup,
                    icon: const Icon(Icons.delete),
                    label: const Text("Delete Backup File"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
