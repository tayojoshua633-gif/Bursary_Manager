// lib/utils/write_guard.dart
import 'package:flutter/material.dart';
import 'school_sync_registry.dart';

/// Defense-in-depth against write actions on a Read-Only device, for the
/// handful of high-stakes mutating screens that can be reached directly
/// (e.g. a row's "Edit" icon) without going through a menu card already
/// gated by PermissionHelper.hasPermission(). A write here would only land
/// in the active linked school's cached copy and vanish on the next
/// refresh — confusing regardless of who triggered it.
class WriteGuard {
  /// Call from initState() of a mutating screen. If the device is
  /// Read-Only, pops the screen back off the stack after the first frame
  /// and shows an explanatory SnackBar instead of letting the form render.
  static Future<void> enforce(BuildContext context) async {
    final readOnly = await SchoolSyncRegistry.isReadOnlyMode();
    if (!readOnly) return;
    if (!context.mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Read-only mode — can't edit this school's data."),
        backgroundColor: Colors.red,
      ));
    });
  }
}
