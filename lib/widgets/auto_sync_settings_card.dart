// lib/widgets/auto_sync_settings_card.dart
import 'package:flutter/material.dart';
import '../utils/auto_sync_settings.dart';
import '../utils/auto_sync_service.dart';

/// Interval picker for background auto-sync, shared by the Read-Only Access
/// screen (write devices) and the Linked Schools screen (read-only devices)
/// — same underlying setting either way, since a device is only ever one
/// mode at a time.
class AutoSyncSettingsCard extends StatefulWidget {
  const AutoSyncSettingsCard({super.key});

  @override
  State<AutoSyncSettingsCard> createState() => _AutoSyncSettingsCardState();
}

class _AutoSyncSettingsCardState extends State<AutoSyncSettingsCard> {
  bool _loading = true;
  bool _saving = false;
  int _minutes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final minutes = await AutoSyncSettings.getIntervalMinutes();
    if (!mounted) return;
    setState(() {
      _minutes = minutes;
      _loading = false;
    });
  }

  Future<void> _onChanged(int? minutes) async {
    if (minutes == null || _saving) return;
    setState(() {
      _minutes = minutes;
      _saving = true;
    });
    await AutoSyncSettings.setIntervalMinutes(minutes);
    await AutoSyncService.restart();
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
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
                Icon(Icons.sync, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Text('Auto-Sync',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Automatically sync in the background while the app is open — '
              'no need to remember to tap "Sync Now". Stops if the app is '
              'fully closed.',
              style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 12),
            _loading
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ))
                : DropdownButtonFormField<int>(
                    initialValue: _minutes,
                    decoration: const InputDecoration(
                      labelText: 'Sync every',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: AutoSyncSettings.options
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(AutoSyncSettings.label(m)),
                            ))
                        .toList(),
                    onChanged: _saving ? null : _onChanged,
                  ),
          ],
        ),
      ),
    );
  }
}
