// lib/widgets/whats_new_dialog.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_version.dart';

class _WhatsNewFeature {
  final IconData icon;
  final String title;
  final String description;

  const _WhatsNewFeature({
    required this.icon,
    required this.title,
    required this.description,
  });
}

/// Shows a "What's New" dialog once per app version, highlighting the
/// headline features shipped in [kAppVersion].
class WhatsNewDialog {
  static const _prefsKey = 'last_seen_whats_new_version';

  static const List<_WhatsNewFeature> _features = [
    _WhatsNewFeature(
      icon: Icons.receipt_long,
      title: 'View Term Bills',
      description:
          'New page under Bills & Payment — pick a class to see its full fee breakdown for the term, '
          'then export it as PDF, JPEG, SMS, or print via Bluetooth/USB thermal printer.',
    ),
  ];

  /// Shows the dialog if it hasn't been shown for the current app version yet.
  static Future<void> maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeenVersion = prefs.getString(_prefsKey);
    if (lastSeenVersion == kAppVersion) return;

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _WhatsNewDialogContent(features: _features),
    );

    await prefs.setString(_prefsKey, kAppVersion);
  }
}

class _WhatsNewDialogContent extends StatelessWidget {
  final List<_WhatsNewFeature> features;

  const _WhatsNewDialogContent({required this.features});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.new_releases, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          const Expanded(child: Text("What's New")),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version $kAppVersion',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            for (final feature in features) ...[
              _FeatureRow(feature: feature),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final _WhatsNewFeature feature;

  const _FeatureRow({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: Colors.blue.shade50,
          child: Icon(feature.icon, size: 16, color: Colors.blue.shade700),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feature.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                feature.description,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
