// lib/screens/backup/sync_dsm_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../utils/google_drive_backup_helper.dart';
import '../../utils/db_backup_helper.dart';

class SyncDsmScreen extends StatefulWidget {
  const SyncDsmScreen({super.key});

  @override
  State<SyncDsmScreen> createState() => _SyncDsmScreenState();
}

class _SyncDsmScreenState extends State<SyncDsmScreen> {
  // Tables that must never be overwritten from a foreign backup
  static const _excludedTables = {'licenses', 'users', 'permissions'};

  bool _checkingAuth = false;
  bool _isSignedIn = false;
  String? _email;

  bool _loadingBackups = false;
  List<Map<String, dynamic>> _backups = [];
  String? _selectedBackupId;
  String? _selectedBackupName;

  bool _syncing = false;
  bool _autoSyncFetching = false;
  String _syncStep = '';
  bool? _syncSuccess;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  // ── Auth ─────────────────────────────────────────────────────

  Future<void> _checkAuth() async {
    setState(() => _checkingAuth = true);
    final signedIn = await GoogleDriveBackupHelper.isSignedIn();
    final email = GoogleDriveBackupHelper.getCurrentUserEmail();
    if (mounted) {
      setState(() {
        _isSignedIn = signedIn;
        _email = email;
        _checkingAuth = false;
      });
      if (signedIn) _loadBackups();
    }
  }

  Future<void> _signIn() async {
    setState(() => _checkingAuth = true);
    final result = await GoogleDriveBackupHelper.signIn();
    setState(() => _checkingAuth = false);
    if (!mounted) return;
    if (result['success'] == true) {
      _snack(result['message'] as String, Colors.green);
      await _checkAuth();
    } else {
      _snack(result['message'] as String, Colors.red);
    }
  }

  Future<void> _signOut() async {
    await GoogleDriveBackupHelper.signOut();
    if (mounted) {
      setState(() {
        _isSignedIn = false;
        _email = null;
        _backups = [];
        _selectedBackupId = null;
        _selectedBackupName = null;
        _syncSuccess = null;
        _syncMessage = null;
      });
    }
  }

  // ── Backup list ──────────────────────────────────────────────

  Future<void> _loadBackups() async {
    setState(() { _loadingBackups = true; _backups = []; _selectedBackupId = null; });
    final list = await GoogleDriveBackupHelper.listDsmBackups();
    if (!mounted) return;
    setState(() {
      _backups = list;
      _loadingBackups = false;
      if (list.isNotEmpty) {
        _selectedBackupId = list.first['id'] as String?;
        _selectedBackupName = list.first['name'] as String?;
      }
    });
  }

  // ── Sync ─────────────────────────────────────────────────────

  Future<void> _autoSyncNow() async {
    setState(() => _autoSyncFetching = true);

    List<Map<String, dynamic>> backups;
    try {
      backups = await GoogleDriveBackupHelper.listDsmBackups();
    } catch (e) {
      if (mounted) {
        setState(() => _autoSyncFetching = false);
        _snack('Failed to fetch backups: $e', Colors.red);
      }
      return;
    }

    if (!mounted) return;
    setState(() => _autoSyncFetching = false);

    if (backups.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.cloud_off, color: Colors.grey),
            SizedBox(width: 8),
            Text('No Backups Found'),
          ]),
          content: const Text(
            'No backups were found in the "DSM CloudSync" folder.\n\n'
            'Run CloudSync on the DSM desktop app first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final latest = backups.first;
    setState(() {
      _backups = backups;
      _selectedBackupId = latest['id'] as String?;
      _selectedBackupName = latest['name'] as String?;
    });

    final name = latest['name'] as String? ?? 'backup.db';
    final modified = _formatDate(latest['modifiedTime']);
    final size = _formatFileSize(latest['size']);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.bolt, color: Colors.orange),
          SizedBox(width: 8),
          Text('Auto Sync Now'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Restore from the latest backup?',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('File: $name',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  if (modified.isNotEmpty)
                    Text('Date: $modified',
                        style: const TextStyle(fontSize: 12)),
                  if (size.isNotEmpty)
                    Text('Size: $size',
                        style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tables kept (not overwritten):',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800)),
                  const SizedBox(height: 4),
                  for (final t in _excludedTables)
                    Text('• $t',
                        style: TextStyle(
                            fontSize: 12, color: Colors.green.shade700)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.bolt),
            label: const Text('Auto Sync Now'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _runSync();
  }

  Future<void> _confirmAndSync() async {
    if (_selectedBackupId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.sync, color: Colors.indigo),
          SizedBox(width: 8),
          Text('Sync from DSM?'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backup: $_selectedBackupName',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'This will overwrite your current data with records from the '
              'selected DSM backup.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tables kept (not overwritten):',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold,
                          color: Colors.green.shade800)),
                  const SizedBox(height: 4),
                  for (final t in _excludedTables)
                    Text('• $t',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.sync),
            label: const Text('Sync Now'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _runSync();
  }

  Future<void> _runSync() async {
    setState(() {
      _syncing = true;
      _syncStep = 'Downloading backup from Google Drive…';
      _syncSuccess = null;
      _syncMessage = null;
    });

    String? tempPath;
    try {
      // 1. Download to temp file
      final tempDir = await getTemporaryDirectory();
      tempPath = p.join(
        tempDir.path,
        'dsm_sync_${DateTime.now().millisecondsSinceEpoch}.db',
      );
      final dlResult = await GoogleDriveBackupHelper.downloadBackupFromDrive(
          _selectedBackupId!, tempPath);
      if (dlResult['success'] != true) {
        throw Exception(dlResult['message']);
      }

      // 2. Read table names from the downloaded backup
      setState(() => _syncStep = 'Reading backup tables…');
      final tablesToRestore = await _getTablesFromBackup(tempPath);
      if (tablesToRestore.isEmpty) {
        throw Exception('No tables found in the backup file.');
      }

      // 3. Selective restore (excluded tables are not in tablesToRestore)
      setState(() =>
          _syncStep = 'Restoring ${tablesToRestore.length} tables…');
      final result = await DBBackupHelper.selectiveRestoreDatabase(
          tempPath, tablesToRestore);

      if (mounted) {
        setState(() {
          _syncing = false;
          _syncSuccess = result['success'] == true;
          _syncMessage = result['message'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncSuccess = false;
          _syncMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      // Clean up temp file
      if (tempPath != null) {
        try { File(tempPath).deleteSync(); } catch (_) {}
      }
    }
  }

  /// Opens the backup .db file with sqflite, reads table names, and
  /// returns all that are NOT in [_excludedTables].
  Future<List<String>> _getTablesFromBackup(String dbPath) async {
    Database? db;
    try {
      db = await openDatabase(dbPath, readOnly: true);
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      return rows
          .map((r) => r['name'] as String)
          .where((name) => !_excludedTables.contains(name))
          .toList();
    } finally {
      await db?.close();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color,
          duration: const Duration(seconds: 3)),
    );
  }

  String _formatFileSize(dynamic size) {
    if (size == null) return '';
    final bytes = (size is String) ? int.tryParse(size) ?? 0 : (size as num).toInt();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(dynamic dt) {
    if (dt == null) return '';
    try {
      final d = dt is DateTime ? dt : DateTime.parse(dt.toString());
      return DateFormat('dd MMM yyyy  HH:mm').format(d.toLocal());
    } catch (_) {
      return dt.toString();
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync with DSM'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildAuthCard(),
          const SizedBox(height: 16),
          if (_isSignedIn) ...[
            _buildInfoBanner(),
            const SizedBox(height: 16),
            _buildAutoSyncCard(),
            const SizedBox(height: 16),
            _buildBackupList(),
            const SizedBox(height: 16),
            _buildSyncButton(),
            if (_syncSuccess != null) ...[
              const SizedBox(height: 16),
              _buildResultCard(),
            ],
          ],
        ]),
      ),
    );
  }

  // ── Auth card ─────────────────────────────────────────────────

  Widget _buildAuthCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _checkingAuth
            ? const Row(children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Checking sign-in…'),
              ])
            : _isSignedIn
                ? Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.green.shade50, shape: BoxShape.circle),
                      child: Icon(Icons.check_circle,
                          color: Colors.green.shade700, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Signed in to Google',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        if (_email != null)
                          Text(_email!,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600)),
                      ]),
                    ),
                    TextButton(
                      onPressed: _signOut,
                      child: const Text('Sign Out',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ])
                : Row(children: [
                    Icon(Icons.account_circle_outlined,
                        size: 36, color: Colors.grey.shade400),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Sign in with the same Google account used on the '
                        'DSM desktop app.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _signIn,
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('Sign In'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white),
                    ),
                  ]),
      ),
    );
  }

  // ── Auto Sync card ────────────────────────────────────────────

  Widget _buildAutoSyncCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.bolt, color: Colors.orange.shade700, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto Sync Now',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.orange.shade800)),
                    Text(
                      'Automatically picks the latest backup and restores it.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: _autoSyncFetching
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.orange.shade700)),
                            const SizedBox(width: 10),
                            const Text('Finding latest backup…'),
                          ],
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _syncing ? null : _autoSyncNow,
                      icon: const Icon(Icons.bolt),
                      label: const Text('Auto Sync Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Info banner ───────────────────────────────────────────────

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.info_outline, color: Colors.indigo.shade700, size: 18),
          const SizedBox(width: 8),
          Text('How it works',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade800,
                  fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Text(
          'Selects the latest backup from the "DSM CloudSync" Google Drive '
          'folder (auto-created by the DSM desktop app when CloudSync runs) '
          'and restores it into this app with one click.',
          style: TextStyle(fontSize: 13, color: Colors.indigo.shade700),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.lock_outline, size: 15, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text('Always kept (never overwritten):',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold,
                  color: Colors.green.shade800)),
        ]),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final t in _excludedTables)
              Chip(
                label: Text(t,
                    style: TextStyle(
                        fontSize: 11, color: Colors.green.shade800)),
                backgroundColor: Colors.green.shade50,
                side: BorderSide(color: Colors.green.shade200),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ]),
    );
  }

  // ── Backup list ───────────────────────────────────────────────

  Widget _buildBackupList() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.folder_open, size: 16, color: Colors.indigo),
        const SizedBox(width: 6),
        Text(
          _loadingBackups
              ? 'Loading backups…'
              : 'DSM CloudSync on Google Drive (${_backups.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _loadingBackups ? null : _loadBackups,
          icon: _loadingBackups
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh, size: 16),
          label: Text(_loadingBackups ? 'Loading…' : 'Refresh'),
          style: TextButton.styleFrom(foregroundColor: Colors.indigo),
        ),
      ]),
      const SizedBox(height: 8),
      if (_loadingBackups)
        const Center(
          child: Padding(padding: EdgeInsets.all(24),
              child: CircularProgressIndicator()),
        )
      else if (_backups.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('"DSM CloudSync" folder not found on this Google account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            // Step-by-step hint
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.tips_and_updates,
                        size: 15, color: Colors.amber.shade800),
                    const SizedBox(width: 6),
                    Text('Check these steps:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    '1. On the DSM desktop app, go to\n'
                    '   Settings → CloudSync → tap "Backup Now" at least once.\n\n'
                    '2. Sign Out here, then Sign In again — the app needs\n'
                    '   updated Google permissions to read the sync folder.',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout, size: 14),
              label: const Text('Sign Out & Re-authenticate',
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.indigo,
                side: BorderSide(color: Colors.indigo.shade300),
              ),
            ),
          ]),
        )
      else
        for (int i = 0; i < _backups.length; i++)
          _backupTile(_backups[i], isLatest: i == 0),
    ]);
  }

  Widget _backupTile(Map<String, dynamic> backup, {bool isLatest = false}) {
    final id = backup['id'] as String? ?? '';
    final name = backup['name'] as String? ?? 'backup.db';
    final size = _formatFileSize(backup['size']);
    final modified = _formatDate(backup['modifiedTime']);
    final isSelected = _selectedBackupId == id;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? BorderSide(color: Colors.indigo.shade400, width: 1.5)
            : BorderSide.none,
      ),
      color: isSelected ? Colors.indigo.shade50 : null,
      child: ListTile(
        onTap: _syncing
            ? null
            : () => setState(() {
                  _selectedBackupId = id;
                  _selectedBackupName = name;
                }),
        leading: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? Colors.indigo : Colors.transparent,
            border: Border.all(
              color: isSelected ? Colors.indigo : Colors.grey.shade400,
              width: 2,
            ),
          ),
          child: isSelected
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
        title: Row(children: [
          Expanded(
            child: Text(name,
                style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13)),
          ),
          if (isLatest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.indigo.shade700,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Latest',
                  style: TextStyle(fontSize: 10, color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
        ]),
        subtitle: Text(
          [if (modified.isNotEmpty) modified, if (size.isNotEmpty) size]
              .join('  ·  '),
          style: const TextStyle(fontSize: 11),
        ),
        dense: true,
      ),
    );
  }

  // ── Sync button & progress ────────────────────────────────────

  Widget _buildSyncButton() {
    if (_syncing) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_syncStep,
                style: const TextStyle(fontWeight: FontWeight.w500),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Please wait, do not close the app…',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ]),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: (_selectedBackupId == null) ? null : _confirmAndSync,
        icon: const Icon(Icons.sync),
        label: Text(_selectedBackupId == null
            ? 'Select a backup above'
            : 'Sync from DSM'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ── Result card ───────────────────────────────────────────────

  Widget _buildResultCard() {
    final ok = _syncSuccess == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: ok ? Colors.green.shade300 : Colors.red.shade300),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          color: ok ? Colors.green.shade700 : Colors.red.shade700,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _syncMessage ?? (ok ? 'Sync completed successfully.' : 'Sync failed.'),
            style: TextStyle(
                fontSize: 13,
                color: ok ? Colors.green.shade800 : Colors.red.shade800),
          ),
        ),
      ]),
    );
  }
}
