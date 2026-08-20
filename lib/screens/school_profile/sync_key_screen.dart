// lib/screens/school_profile/sync_key_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/sync_key_client.dart';
import '../../widgets/add_school_dialog.dart';
import '../../widgets/auto_sync_settings_card.dart';

class SyncKeyScreen extends StatefulWidget {
  const SyncKeyScreen({super.key});

  @override
  State<SyncKeyScreen> createState() => _SyncKeyScreenState();
}

class _SyncKeyScreenState extends State<SyncKeyScreen> {
  bool _loading = true;
  bool _actionLoading = false;
  String? _cachedKey;
  String? _cachedPrefix;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final key = await SyncKeyClient.getCachedKey();
    final prefix = await SyncKeyClient.getCachedKeyPrefix();
    if (!mounted) return;
    setState(() {
      _cachedKey = key;
      _cachedPrefix = prefix;
      _loading = false;
    });
  }

  Future<void> _generate({required bool isRegenerate}) async {
    if (isRegenerate) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Regenerate Key?'),
          content: const Text(
            'This will disconnect every device currently using the old key. '
            "They'll need the new key to keep reading this school's data.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: const Text('Regenerate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _actionLoading = true);
    final result = await SyncKeyClient.generate();
    setState(() => _actionLoading = false);
    if (!mounted) return;
    if (result['success'] == true) {
      await _load();
      _showSnack('Sync key generated.', success: true);
    } else {
      _showSnack(result['message'] as String? ?? 'Failed to generate key.', success: false);
    }
  }

  Future<void> _revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revoke Key?'),
        content: const Text(
          'Every device currently using this key will lose read access to '
          "this school's data immediately. This cannot be undone — you can "
          'always generate a new key afterward.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    final result = await SyncKeyClient.revoke();
    setState(() => _actionLoading = false);
    if (!mounted) return;
    if (result['success'] == true) {
      await _load();
      _showSnack('Read-only access disabled.', success: true);
    } else {
      _showSnack(result['message'] as String? ?? 'Failed to revoke key.', success: false);
    }
  }

  void _copyKey() {
    if (_cachedKey == null) return;
    Clipboard.setData(ClipboardData(text: _cachedKey!));
    _showSnack('Key copied to clipboard.', success: true);
  }

  void _shareKey() {
    if (_cachedKey == null) return;
    Share.share(
      'Bursary Manager Read-Only sync key:\n${_cachedKey!}\n\n'
      'Paste this into "Add School" on a Read-Only device to view this '
      "school's data.",
    );
  }

  void _showSnack(String message, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: success ? Colors.green : Colors.red,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Read-Only Access'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildInfoCard(),
                const SizedBox(height: 16),
                if (_cachedKey != null) _buildKeyCard() else _buildEmptyCard(),
                const SizedBox(height: 16),
                _buildActionsCard(),
                const SizedBox(height: 16),
                _buildAddSchoolCard(),
                const SizedBox(height: 16),
                const AutoSyncSettingsCard(),
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
            Icon(Icons.key, color: Colors.deepPurple.shade700, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Read-Only Access',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  SizedBox(height: 4),
                  Text(
                    'A sync key lets another device (e.g. a head office '
                    'install) view this school\'s data as a read-only tab — '
                    'it cannot make any changes here. Revoke or regenerate '
                    'at any time to cut off access.',
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

  Widget _buildEmptyCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.vpn_key_off, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('No sync key generated yet',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Generate one to allow read-only access to this school.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyCard() {
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
                Icon(Icons.vpn_key, color: Colors.deepPurple.shade700),
                const SizedBox(width: 8),
                const Text('Current Sync Key',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                _cachedKey ?? '',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyKey,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareKey,
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Only shown on this device — the server cannot show it to you '
              'again. Copy or share it now if a Read-Only device needs it.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            if (_cachedPrefix != null) ...[
              const SizedBox(height: 4),
              Text(
                'Key ID: $_cachedPrefix… (use this to confirm a device is on the right key)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddSchoolCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz, color: Colors.deepPurple.shade700),
                const SizedBox(width: 8),
                const Text('Or View Another School',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Have a sync key from a different school instead? Add it here to '
              'switch this device into Read-Only mode.',
              style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => showAddSchoolDialog(
                  context,
                  onAdded: () {
                    if (mounted) Navigator.pop(context);
                  },
                ),
                icon: const Icon(Icons.add_link),
                label: const Text('Add School'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurple.shade700,
                  side: BorderSide(color: Colors.deepPurple.shade700),
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

  Widget _buildActionsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _actionLoading ? null : () => _generate(isRegenerate: _cachedKey != null),
                icon: const Icon(Icons.autorenew),
                label: Text(_cachedKey != null ? 'Regenerate Key' : 'Generate Key'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            if (_cachedKey != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _actionLoading ? null : _revoke,
                  icon: const Icon(Icons.block),
                  label: const Text('Revoke Key'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
