// lib/utils/navigation_helper.dart

import 'package:flutter/material.dart';
import '../navigation/sidebar_scaffold.dart';

/// Helper class for navigation with sidebar support
class NavigationHelper {
  /// Navigate to a page with automatic sidebar support on large screens
  ///
  /// On screens with shortest side >= 700px, the page will be wrapped in SidebarScaffold.
  /// On smaller screens, the page will be shown without the sidebar.
  ///
  /// Parameters:
  /// - [context]: The BuildContext from which to navigate
  /// - [page]: The target page widget to navigate to
  /// - [currentUser]: The current user data map (required for sidebar)
  /// - [pageId]: Optional page ID for sidebar highlighting (e.g., 'student_management/students')
  static Future<T?> pushWithSidebar<T>(
    BuildContext context, {
    required Widget page,
    required Map<String, dynamic> currentUser,
    String? pageId,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;
    final showSidebar = shortestSide >= 700;

    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: currentUser,
                currentPageId: pageId,
                child: page,
              )
            : page,
      ),
    );
  }

  /// Replace current page with a new page with automatic sidebar support
  ///
  /// Similar to [pushWithSidebar] but uses pushReplacement instead of push
  static Future<T?> pushReplacementWithSidebar<T, TO>(
    BuildContext context, {
    required Widget page,
    required Map<String, dynamic> currentUser,
    String? pageId,
    TO? result,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;
    final showSidebar = shortestSide >= 700;

    return Navigator.pushReplacement<T, TO>(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: currentUser,
                currentPageId: pageId,
                child: page,
              )
            : page,
      ),
      result: result,
    );
  }
}
