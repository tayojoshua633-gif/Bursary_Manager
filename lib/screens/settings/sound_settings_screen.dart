// lib/screens/settings/sound_settings_screen.dart

import 'package:flutter/material.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/sound_service.dart';

class SoundSettingsScreen extends StatefulWidget {
  const SoundSettingsScreen({super.key});

  @override
  State<SoundSettingsScreen> createState() => _SoundSettingsScreenState();
}

class _SoundSettingsScreenState extends State<SoundSettingsScreen> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _enabled = SoundService.instance.isEnabled;
  }

  Future<void> _toggle(bool value) async {
    await SoundService.instance.setEnabled(value);
    setState(() => _enabled = value);
    if (value) {
      SoundService.instance.playSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound Effects'),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header / master toggle card
            Card(
              elevation: 2,
              color: Colors.teal.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.all(ds.cardPadding),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(ds.cardPadding * 0.75),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _enabled ? Icons.volume_up : Icons.volume_off,
                        size: ds.iconSize * 1.5,
                        color: Colors.teal.shade700,
                      ),
                    ),
                    SizedBox(width: ds.cardPadding),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sound Effects',
                            style: TextStyle(
                              fontSize: ds.titleFontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade900,
                            ),
                          ),
                          SizedBox(height: ds.cardPadding * 0.25),
                          Text(
                            'Clicks, popups, warnings and success chimes',
                            style: TextStyle(
                              fontSize: ds.bodyFontSize * 0.9,
                              color: Colors.teal.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _enabled,
                      activeThumbColor: Colors.teal.shade700,
                      onChanged: _toggle,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: ds.cardPadding * 1.5),

            Text(
              'Preview',
              style: TextStyle(
                fontSize: ds.titleFontSize * 0.9,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: ds.cardPadding * 0.5),
            Text(
              'Sounds are on by default. Tap a sound below to preview it.',
              style: TextStyle(
                fontSize: ds.bodyFontSize * 0.9,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: ds.cardPadding),

            Wrap(
              spacing: ds.cardPadding * 0.5,
              runSpacing: ds.cardPadding * 0.5,
              children: [
                _previewChip('Click', Icons.touch_app, SoundService.instance.playClick),
                _previewChip('Popup', Icons.open_in_new, SoundService.instance.playPopup),
                _previewChip('Success', Icons.check_circle, SoundService.instance.playSuccess),
                _previewChip('Warning', Icons.warning_amber, SoundService.instance.playWarning),
                _previewChip('App Open', Icons.login, SoundService.instance.playAppOpen),
                _previewChip('App Close', Icons.logout, SoundService.instance.playAppClose),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewChip(String label, IconData icon, Future<void> Function() onPlay) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: Colors.teal.shade700),
      label: Text(label),
      onPressed: _enabled ? onPlay : null,
    );
  }
}
