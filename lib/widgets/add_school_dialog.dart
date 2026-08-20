// lib/widgets/add_school_dialog.dart
import 'package:flutter/material.dart';
import '../utils/school_sync_client.dart';

/// Prompts for a sync key and links the school it resolves to. Shared by
/// every screen that offers "Add School" — the Linked Schools page (adding
/// another school) and the Read-Only Access screen (a write device linking
/// its first school, switching itself into Read-Only mode).
Future<void> showAddSchoolDialog(BuildContext context, {VoidCallback? onAdded}) async {
  final ctrl = TextEditingController();
  bool submitting = false;
  String? errorText;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) => AlertDialog(
        title: const Text('Add School'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Paste the sync key from the school's Read-Only Access screen.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Sync Key',
                border: const OutlineInputBorder(),
                errorText: errorText,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: submitting
                ? null
                : () async {
                    final key = ctrl.text.trim();
                    if (key.isEmpty) {
                      setDialogState(() => errorText = 'Enter a sync key');
                      return;
                    }
                    setDialogState(() {
                      submitting = true;
                      errorText = null;
                    });
                    final result = await SchoolSyncClient.addSchool(key);
                    if (result['success'] == true) {
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      onAdded?.call();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(result['message'] as String? ?? 'School added.'),
                          backgroundColor: Colors.green,
                        ));
                      }
                    } else {
                      setDialogState(() {
                        submitting = false;
                        errorText = result['message'] as String?;
                      });
                    }
                  },
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
