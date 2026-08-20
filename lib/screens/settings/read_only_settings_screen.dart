// lib/screens/settings/read_only_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/school_sync_registry.dart';
import '../../utils/school_sync_client.dart';
import '../../widgets/add_school_dialog.dart';
import '../../widgets/auto_sync_settings_card.dart';

class ReadOnlySettingsScreen extends StatefulWidget {
  const ReadOnlySettingsScreen({super.key});

  @override
  State<ReadOnlySettingsScreen> createState() => _ReadOnlySettingsScreenState();
}

class _ReadOnlySettingsScreenState extends State<ReadOnlySettingsScreen> {
  bool _loading = true;
  List<LinkedSchool> _schools = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final schools = await SchoolSyncRegistry.getAll();
    if (!mounted) return;
    setState(() {
      _schools = schools;
      _loading = false;
    });
  }

  Future<void> _removeSchool(LinkedSchool school) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove School?'),
        content: Text('This removes "${school.schoolName}" and its cached data from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await SchoolSyncClient.removeSchool(school.id);
    await _load();
  }

  Future<void> _switchToWriteMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Switch to Write Mode?'),
        content: const Text(
          'This removes every linked school from this device and switches it '
          'back to using its own local data. You can always add schools again later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Switch to Write Mode'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final school in _schools) {
      await SchoolSyncClient.removeSchool(school.id);
    }
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Switched to Write Mode.'),
      backgroundColor: Colors.green,
    ));
  }

  String _formatTime(String? iso) {
    if (iso == null) return 'Never';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return DateFormat('h:mm a').format(dt);
    if (diff.inDays < 7) return DateFormat('EEE, h:mm a').format(dt);
    return DateFormat('MMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Schools'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add School',
            onPressed: () => showAddSchoolDialog(context, onAdded: _load),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock, color: Colors.orange),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This device is in Read-Only mode — it can view but not '
                              'edit each linked school\'s data.',
                              style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const AutoSyncSettingsCard(),
                  const SizedBox(height: 16),
                  if (_schools.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('No schools linked.', style: TextStyle(color: Colors.grey.shade600)),
                      ),
                    )
                  else
                    ..._schools.map((school) => Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.school)),
                            title: Text(school.displayLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Last synced: ${_formatTime(school.lastSyncedAt)}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: 'Remove',
                              onPressed: () => _removeSchool(school),
                            ),
                          ),
                        )),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _switchToWriteMode,
                      icon: const Icon(Icons.edit),
                      label: const Text('Switch to Write Mode'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade700),
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
