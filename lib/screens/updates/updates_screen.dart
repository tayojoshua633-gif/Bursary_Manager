import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/app_version.dart';
import '../../utils/update_checker.dart';
import '../web/web_view_screen.dart';

/// The dashboard "Updates" page: the product page from the website, with a
/// banner on top comparing the installed version against the latest release.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  UpdateInfo? _info = UpdateChecker.latest.value;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check(force: true);
  }

  Future<void> _check({bool force = false}) async {
    setState(() => _checking = true);
    final info = await UpdateChecker.check(force: force);
    if (!mounted) return;
    setState(() {
      _info = info;
      _checking = false;
    });
  }

  Future<void> _download(UpdateInfo info) async {
    final ok = await launchUrl(
      Uri.parse(info.downloadUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the download link.')),
      );
    }
  }

  Widget _buildBanner(BuildContext context) {
    final info = _info;
    final hasUpdate = info?.isUpdateAvailable ?? false;

    final Color color;
    final IconData icon;
    final String message;
    if (_checking && info == null) {
      color = Colors.blueGrey;
      icon = Icons.sync;
      message = 'Checking for updates…  (installed: v$kAppVersion)';
    } else if (info == null) {
      color = Colors.grey;
      icon = Icons.wifi_off;
      message =
          'Couldn\'t check for updates — you\'re on v$kAppVersion. Check your internet connection.';
    } else if (hasUpdate) {
      color = Colors.orange;
      icon = Icons.system_update;
      final extra = [
        if (info.size != null) info.size!,
        if (info.updated != null) 'released ${info.updated}',
      ].join(', ');
      message =
          'A new version is available: v${info.latestVersion}${extra.isEmpty ? '' : ' ($extra)'}. You\'re on v$kAppVersion.';
    } else {
      color = Colors.green;
      icon = Icons.check_circle;
      message = 'You\'re up to date — v$kAppVersion is the latest version.';
    }

    return Material(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontWeight: hasUpdate ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (hasUpdate)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _download(info!),
                ),
              ),
            if (_checking)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Check again',
                onPressed: () => _check(force: true),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewScreen(
      url: UpdateChecker.productPageUrl,
      title: 'Updates',
      header: _buildBanner(context),
    );
  }
}
