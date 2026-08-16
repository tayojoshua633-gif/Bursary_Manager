// lib/navigation/sidebar_scaffold.dart
import 'package:flutter/material.dart';
import 'sidebar_navigation.dart';
import 'sidebar_state_provider.dart';

/// A scaffold wrapper that conditionally shows the sidebar on large screens
class SidebarScaffold extends StatelessWidget {
  final Widget child;
  final Map<String, dynamic> currentUser;
  final String? currentPageId;

  const SidebarScaffold({
    super.key,
    required this.child,
    required this.currentUser,
    this.currentPageId,
  });

  @override
  Widget build(BuildContext context) {
    // Check screen size using MediaQuery
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;

    // Show sidebar only on 10+ inch displays (shortestSide >= 700)
    final showSidebar = shortestSide >= 700;

    if (!showSidebar) {
      // On smaller screens, just return the child directly
      return child;
    }

    // On larger screens, show sidebar + content
    return Row(
      children: [
        // Sidebar
        SidebarNavigation(
          currentUser: currentUser,
          currentPageId: currentPageId,
          onNavigate: (pageId, page) {
            // Navigate to the selected page using push to maintain back stack
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SidebarScaffold(
                  currentUser: currentUser,
                  currentPageId: pageId,
                  child: page,
                ),
              ),
            );
          },
        ),

        // Main content area
        Expanded(
          child: child,
        ),
      ],
    );
  }
}

/// Navigation helper for sidebar-aware navigation
class SidebarNavigator {
  /// Navigate to a page with sidebar support
  static void push(
    BuildContext context,
    String pageId,
    Widget screen,
    Map<String, dynamic> currentUser,
  ) {
    // Update sidebar state if available
    final sidebarState = SidebarStateProvider.maybeOf(context);
    sidebarState?.setSelectedPage(pageId);

    // Check if we should show sidebar
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;
    final showSidebar = shortestSide >= 700;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: currentUser,
                currentPageId: pageId,
                child: screen,
              )
            : screen,
      ),
    );
  }

  /// Navigate and replace current page with sidebar support
  static void pushReplacement(
    BuildContext context,
    String pageId,
    Widget screen,
    Map<String, dynamic> currentUser,
  ) {
    // Update sidebar state if available
    final sidebarState = SidebarStateProvider.maybeOf(context);
    sidebarState?.setSelectedPage(pageId);

    // Check if we should show sidebar
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;
    final showSidebar = shortestSide >= 700;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: currentUser,
                currentPageId: pageId,
                child: screen,
              )
            : screen,
      ),
    );
  }

  /// Navigate and remove all previous routes
  static void pushAndRemoveUntil(
    BuildContext context,
    String pageId,
    Widget screen,
    Map<String, dynamic> currentUser,
  ) {
    // Update sidebar state if available
    final sidebarState = SidebarStateProvider.maybeOf(context);
    sidebarState?.setSelectedPage(pageId);

    // Check if we should show sidebar
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;
    final showSidebar = shortestSide >= 700;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: currentUser,
                currentPageId: pageId,
                child: screen,
              )
            : screen,
      ),
      (route) => false,
    );
  }
}
