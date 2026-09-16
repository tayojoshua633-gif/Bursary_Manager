import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Shared "Download or Share" export flow, used by every PDF export button
/// in the app. Shows a choice dialog, runs [generate] with the chosen
/// destination, then either shows a "saved to Downloads" confirmation or
/// opens the OS share sheet.
class PdfExportHelper {
  static Future<void> exportPdf(
    BuildContext context, {
    required Future<String> Function({required bool saveToDownloads}) generate,
    required String shareSubject,
    String? shareText,
    String successMessage = 'PDF exported successfully!',
  }) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export PDF'),
        content: const Text('Download the PDF to your device, or share it via another app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'download'),
            icon: const Icon(Icons.download),
            label: const Text('Download'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'share'),
            icon: const Icon(Icons.share),
            label: const Text('Share'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (choice == null || !context.mounted) return;
    final saveToDownloads = choice == 'download';

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      // Let the progress dialog actually paint before the (possibly
      // blocking, on non-Android platforms) PDF build starts.
      await Future.delayed(const Duration(milliseconds: 100));

      final filePath = await generate(saveToDownloads: saveToDownloads);

      if (!context.mounted) return;
      Navigator.pop(context);

      if (saveToDownloads) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Downloads:\n$filePath'),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        await Share.shareXFiles([XFile(filePath)], subject: shareSubject, text: shareText ?? shareSubject);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting PDF: $e')),
      );
    }
  }
}

/// Resolves where a generated PDF should be written: the device's real
/// Downloads folder, or app-private storage (used for the Share flow, since
/// share sheets work fine from a temp/app directory).
class PdfExportDirectoryHelper {
  static Future<Directory> resolve({required bool saveToDownloads}) async {
    if (!saveToDownloads) return getApplicationDocumentsDirectory();

    if (Platform.isAndroid) {
      var dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) {
        dir = Directory('/storage/emulated/0/Downloads');
      }
      if (!await dir.exists()) {
        final external = await getExternalStorageDirectory();
        if (external != null) dir = external;
      }
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }

    final downloads = await getDownloadsDirectory();
    return downloads ?? await getApplicationDocumentsDirectory();
  }
}
