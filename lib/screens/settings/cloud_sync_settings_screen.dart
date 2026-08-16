// lib/screens/settings/cloud_sync_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/cloud_sync_helper.dart';
import '../../utils/google_drive_backup_helper.dart';

class CloudSyncSettingsScreen extends StatefulWidget {
  const CloudSyncSettingsScreen({super.key});

  @override
  State<CloudSyncSettingsScreen> createState() => _CloudSyncSettingsScreenState();
}

class _CloudSyncSettingsScreenState extends State<CloudSyncSettingsScreen> {
  bool _loading = true;
  bool _actionLoading = false;

  // State
  String _syncMode = 'write'; // 'write' | 'readonly'
  bool _autoBackup = false;
  bool _autoRestore = false;
  bool _isSignedIn = false;
  String? _googleEmail;
  bool _hasInternet = true;
  DateTime? _lastBackup;
  DateTime? _lastRestore;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      CloudSyncHelper.getSyncMode(),
      CloudSyncHelper.isAutoBackupEnabled(),
      CloudSyncHelper.isAutoRestoreEnabled(),
      GoogleDriveBackupHelper.isSignedIn(),
      CloudSyncHelper.hasInternetConnection(),
      CloudSyncHelper.getLastBackupTime(),
      CloudSyncHelper.getLastRestoreTime(),
    ]);
    if (!mounted) return;
    setState(() {
      _syncMode    = results[0] as String;
      _autoBackup  = results[1] as bool;
      _autoRestore = results[2] as bool;
      _isSignedIn  = results[3] as bool;
      _hasInternet = results[4] as bool;
      _lastBackup  = results[5] as DateTime?;
      _lastRestore = results[6] as DateTime?;
      _googleEmail = GoogleDriveBackupHelper.getCurrentUserEmail();
      _loading     = false;
    });
  }

  // ── Google account ────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    setState(() => _actionLoading = true);
    final result = await GoogleDriveBackupHelper.signIn();
    setState(() => _actionLoading = false);
    if (!mounted) return;
    _showSnack(result['message'], success: result['success'] == true);
    await _loadAll();
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out from Google?'),
        content: const Text(
          'Auto-sync will be disabled until you sign in again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await GoogleDriveBackupHelper.signOut();
    await CloudSyncHelper.setAutoBackupEnabled(false);
    await CloudSyncHelper.setAutoRestoreEnabled(false);
    await _loadAll();
  }

  // ── Mode switching ────────────────────────────────────────────────────────

  Future<void> _promptSwitchMode(String targetMode) async {
    final label = targetMode == 'readonly' ? 'Read-Only' : 'Write';
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              targetMode == 'readonly' ? Icons.lock : Icons.edit,
              color: targetMode == 'readonly' ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: 8),
            Text('Switch to $label Mode'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              targetMode == 'readonly'
                  ? 'This device will only download data from Drive. '
                    'Any local changes will be overwritten on next sync.\n\n'
                    'Enter the CloudSync password to confirm:'
                  : 'This device will be the primary device that uploads '
                    'data to Drive.\n\nEnter the CloudSync password to confirm:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CloudSync Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: targetMode == 'readonly' ? Colors.orange : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text('Switch to $label'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    bool success;
    if (targetMode == 'readonly') {
      success = await CloudSyncHelper.switchToReadOnly(ctrl.text);
    } else {
      success = await CloudSyncHelper.switchToWriteMode(ctrl.text);
    }

    if (!mounted) return;
    if (success) {
      _showSnack('Switched to $label Mode', success: true);
      await _loadAll();
    } else {
      _showSnack('Incorrect password', success: false);
    }
  }

  // ── Manual actions ────────────────────────────────────────────────────────

  Future<void> _manualBackup() async {
    if (!_isSignedIn) { _showSnack('Sign in to Google first', success: false); return; }
    if (!_hasInternet) { _showSnack('No internet connection', success: false); return; }
    setState(() => _actionLoading = true);
    final result = await CloudSyncHelper.manualBackup();
    setState(() => _actionLoading = false);
    if (!mounted) return;
    _showSnack(result['message'], success: result['success'] == true);
    if (result['success'] == true) await _loadAll();
  }

  Future<void> _manualRestore() async {
    if (!_isSignedIn) { _showSnack('Sign in to Google first', success: false); return; }
    if (!_hasInternet) { _showSnack('No internet connection', success: false); return; }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_download, color: Colors.blue),
            SizedBox(width: 8),
            Text('Restore from Drive'),
          ],
        ),
        content: const Text(
          'This will replace ALL local data (except your licence) with '
          'the latest CloudSync backup from Google Drive.\n\n'
          'This cannot be undone. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _actionLoading = true);
    final result = await CloudSyncHelper.manualRestore();
    setState(() => _actionLoading = false);
    if (!mounted) return;
    _showSnack(result['message'], success: result['success'] == true);
    if (result['success'] == true) await _loadAll();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnack(String message, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: success ? Colors.green : Colors.red,
      duration: const Duration(seconds: 3),
    ));
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return DateFormat('h:mm a').format(dt);
    if (diff.inDays < 7) return DateFormat('EEE, h:mm a').format(dt);
    return DateFormat('MMM d, yyyy').format(dt);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isReadOnly = _syncMode == 'readonly';

    return Scaffold(
      appBar: AppBar(
        title: const Text('CloudSync'),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (_actionLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _actionLoading ? null : _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Offline banner ────────────────────────────────────────
                  if (!_hasInternet && (_autoBackup || _autoRestore))
                    _buildOfflineBanner(),

                  // ── What is CloudSync ─────────────────────────────────────
                  _buildInfoCard(),
                  const SizedBox(height: 16),

                  // ── Current mode ──────────────────────────────────────────
                  _buildModeCard(isReadOnly),
                  const SizedBox(height: 16),

                  // ── Google account ────────────────────────────────────────
                  _buildAccountCard(),
                  const SizedBox(height: 16),

                  // ── Write mode settings ───────────────────────────────────
                  if (!isReadOnly) ...[
                    _buildWriteCard(),
                    const SizedBox(height: 16),
                  ],

                  // ── Read-only settings ────────────────────────────────────
                  if (isReadOnly) ...[
                    _buildReadOnlyCard(),
                    const SizedBox(height: 16),
                  ],

                  // ── Sync status ───────────────────────────────────────────
                  _buildStatusCard(),
                  const SizedBox(height: 16),

                  // ── Manual actions ────────────────────────────────────────
                  _buildActionsCard(isReadOnly),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        border: Border.all(color: Colors.amber.shade400),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No internet connection — CloudSync is paused. '
              'The app works normally in offline mode.',
              style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_sync, color: Colors.teal.shade700, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CloudSync — Backup & Multi-Device Access',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  SizedBox(height: 4),
                  Text(
                    'Automatically backs up data to Google Drive and lets '
                    'another device with the same Google account stay '
                    'in sync.\n\n'
                    '• Write device: uploads after every change\n'
                    '• Read-Only device: downloads on app launch\n'
                    '• Licence key is never included in sync',
                    style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard(bool isReadOnly) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                const Text('Device Mode',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),

            // Mode tiles
            _modeTile(
              label: 'Write Mode',
              subtitle: 'This device enters data and backs up to Drive',
              icon: Icons.edit,
              color: Colors.green,
              selected: !isReadOnly,
              onTap: isReadOnly ? () => _promptSwitchMode('write') : null,
            ),
            const SizedBox(height: 8),
            _modeTile(
              label: 'Read-Only Mode',
              subtitle: 'This device views data downloaded from Drive',
              icon: Icons.lock,
              color: Colors.orange,
              selected: isReadOnly,
              onTap: !isReadOnly ? () => _promptSwitchMode('readonly') : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Switching mode requires the CloudSync password.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeTile({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.2) : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: selected ? color : Colors.grey, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: selected ? color.withValues(alpha: 0.9) : Colors.black87,
                      )),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: color, size: 22)
            else
              Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_circle, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                const Text('Google Account',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            if (_isSignedIn) ...[
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Signed in as',
                              style: TextStyle(fontSize: 11, color: Colors.black54)),
                          Text(_googleEmail ?? 'Unknown',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _actionLoading ? null : _signOut,
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Sign Out'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _actionLoading ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sign in to enable CloudSync. Use the same Google account on all devices.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWriteCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload, color: Colors.green.shade700),
                const SizedBox(width: 8),
                const Text('Auto-Backup Settings',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Write Mode — this device uploads to Drive',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-Backup to Google Drive',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Backs up automatically after payments, bills & student changes.\n'
                'Licence key is never included.',
                style: TextStyle(fontSize: 12),
              ),
              value: _autoBackup,
              activeThumbColor: Colors.green.shade700,
              onChanged: _isSignedIn && !_actionLoading
                  ? (v) async {
                      await CloudSyncHelper.setAutoBackupEnabled(v);
                      setState(() => _autoBackup = v);
                    }
                  : null,
            ),
            if (!_isSignedIn)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⚠ Sign in to Google to enable auto-backup.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_download, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Auto-Restore Settings',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Read-Only Mode — this device downloads from Drive',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-Restore on App Launch',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Downloads the latest backup from Drive each time the app opens.\n'
                'Licence key is never overwritten.',
                style: TextStyle(fontSize: 12),
              ),
              value: _autoRestore,
              activeThumbColor: Colors.orange.shade700,
              onChanged: _isSignedIn && !_actionLoading
                  ? (v) async {
                      await CloudSyncHelper.setAutoRestoreEnabled(v);
                      setState(() => _autoRestore = v);
                    }
                  : null,
            ),
            if (!_isSignedIn)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⚠ Sign in to Google to enable auto-restore.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This device is in Read-Only Mode. Data will be '
                      'overwritten from Drive on each restore.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
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

  Widget _buildStatusCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                const Text('Sync Status',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),
            _statusRow(
              icon: Icons.cloud_upload,
              label: 'Last Backup',
              value: _formatTime(_lastBackup),
              color: Colors.green.shade700,
            ),
            const SizedBox(height: 8),
            _statusRow(
              icon: Icons.cloud_download,
              label: 'Last Restore',
              value: _formatTime(_lastRestore),
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 8),
            _statusRow(
              icon: Icons.wifi,
              label: 'Internet',
              value: _hasInternet ? 'Connected' : 'Offline',
              color: _hasInternet ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text('$label:', style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _buildActionsCard(bool isReadOnly) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                const Text('Manual Actions',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            if (!isReadOnly)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _actionLoading ? null : _manualBackup,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Backup Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            if (!isReadOnly) const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _actionLoading ? null : _manualRestore,
                icon: const Icon(Icons.cloud_download),
                label: const Text('Restore from Drive'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal.shade700,
                  side: BorderSide(color: Colors.teal.shade700),
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
