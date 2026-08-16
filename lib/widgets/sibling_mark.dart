import 'package:flutter/material.dart';

/// Small inline marker shown after a student's name to flag that they
/// have a sibling also enrolled. Screen-only — do not use inside widgets
/// that are exported to PDF, thermal print, or captured as an image.
class SiblingMark extends StatelessWidget {
  final bool show;
  final double size;

  const SiblingMark({super.key, this.show = true, this.size = 15});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: 'Has a sibling in school',
        child: Icon(
          Icons.people_alt_rounded,
          size: size,
          color: const Color(0xFF00897B),
        ),
      ),
    );
  }
}
