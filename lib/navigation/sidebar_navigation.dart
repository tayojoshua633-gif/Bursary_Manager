// lib/navigation/sidebar_navigation.dart
import 'package:flutter/material.dart';
import '../data/database_helper_wrapper.dart';
import '../main.dart' show appRouteObserver;
import '../utils/active_session_term_notifier.dart';
import '../utils/display_settings_helper.dart';
import '../utils/permission_helper.dart';
import 'menu_data.dart';
import 'sidebar_state_provider.dart';

/// The main sidebar navigation widget
class SidebarNavigation extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  final String? currentPageId;
  final Function(String pageId, Widget page)? onNavigate;

  const SidebarNavigation({
    super.key,
    required this.currentUser,
    this.currentPageId,
    this.onNavigate,
  });

  @override
  State<SidebarNavigation> createState() => _SidebarNavigationState();
}

class _SidebarNavigationState extends State<SidebarNavigation> with RouteAware {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  String? _lastScrolledPageId;

  String? _activeSession;
  String? _activeTerm;

  @override
  void initState() {
    super.initState();
    _loadActiveSessionTerm();
    // Covers the case where the screen that changes the term sits in the
    // same route as this sidebar (e.g. Session/Term Management pushed
    // alongside it) — a plain RouteAware pop/push never fires there.
    ActiveSessionTermNotifier.listenable.addListener(_loadActiveSessionTerm);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    appRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  /// Called when a page pushed above this one is popped — refresh so the
  /// session/term stays in sync with changes made on the popped page (e.g.
  /// switching the active term in Session/Term Management).
  @override
  void didPopNext() {
    _loadActiveSessionTerm();
  }

  Future<void> _loadActiveSessionTerm() async {
    final db = DatabaseHelperWrapper();
    final results = await Future.wait([
      db.getActiveSession(),
      db.getActiveTerm(),
    ]);
    if (!mounted) return;
    setState(() {
      final session = results[0] as Map<String, dynamic>?;
      _activeSession = session?['sessionName'] as String?;
      _activeTerm = results[1] as String?;
    });
  }

  @override
  void dispose() {
    ActiveSessionTermNotifier.listenable.removeListener(_loadActiveSessionTerm);
    appRouteObserver.unsubscribe(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SidebarNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll when currentPageId changes
    if (widget.currentPageId != null &&
        widget.currentPageId != _lastScrolledPageId) {
      _scrollToSelectedItem();
    }
  }

  void _scrollToSelectedItem() {
    if (widget.currentPageId == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[widget.currentPageId];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.3, // Position item 30% from top
        );
        _lastScrolledPageId = widget.currentPageId;
      }
    });
  }

  GlobalKey _getKeyForItem(String itemId) {
    if (!_itemKeys.containsKey(itemId)) {
      _itemKeys[itemId] = GlobalKey();
    }
    return _itemKeys[itemId]!;
  }

  @override
  Widget build(BuildContext context) {
    final sidebarState = SidebarStateProvider.maybeOf(context);
    if (sidebarState == null) {
      return const SizedBox.shrink();
    }

    final isCollapsed = sidebarState.isCollapsed;
    final ds = DisplaySettingsProvider.of(context);

    // Trigger scroll on first build if page is selected
    if (widget.currentPageId != null && _lastScrolledPageId == null) {
      _scrollToSelectedItem();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: isCollapsed ? 72 : 280,
      decoration: BoxDecoration(
        // Modern slate/charcoal gradient background
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1E293B), // Slate 800
            const Color(0xFF0F172A), // Slate 900
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with app name and collapse toggle
          _buildHeader(context, sidebarState, ds, isCollapsed),

          // Current session/term — mirrors the strip on the home screen so
          // it stays visible no matter where the user is in the app.
          if (!isCollapsed && (_activeSession != null || _activeTerm != null))
            _buildSessionTermStrip(),

          // Scrollable menu items
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(
                vertical: ds.cardPadding * 0.5,
                horizontal: isCollapsed ? 8 : 12,
              ),
              children: _buildMenuItems(context, sidebarState, isCollapsed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    SidebarState state,
    DisplaySettings ds,
    bool isCollapsed,
  ) {
    return Container(
      padding: EdgeInsets.all(isCollapsed ? 12 : ds.cardPadding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF3B82F6), // Blue 500
            const Color(0xFF1D4ED8), // Blue 700
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (!isCollapsed) ...[
              // Make header clickable to go to home
              Expanded(
                child: InkWell(
                  onTap: () => _navigateToHome(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.account_balance, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bursary Manager',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: ds.titleFontSize,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            fontFamily: 'Segoe UI',
                            decoration: TextDecoration.none,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  isCollapsed ? Icons.chevron_right : Icons.chevron_left,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              onPressed: () => state.toggleCollapsed(),
              tooltip: isCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionTermStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today,
            size: 13,
            color: Colors.blue.shade200,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                if (_activeSession != null) _activeSession!,
                if (_activeTerm != null) _activeTerm!,
              ].join('  •  '),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade100,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToHome(BuildContext context) {
    // Update sidebar state to show home as selected
    final sidebarState = SidebarStateProvider.maybeOf(context);
    sidebarState?.setSelectedPage('home');

    // Pop back to the root HomeScreen instead of pushing a new one.
    // This avoids disposing all intermediate routes + SidebarScaffolds at once,
    // which caused freezing when navigating from deep pages like receipts.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  List<Widget> _buildMenuItems(
    BuildContext context,
    SidebarState state,
    bool isCollapsed,
  ) {
    final menuItems = MenuData.getMenuItems();
    final userType = widget.currentUser['userType'] ?? 'bursar';
    final isSuperAdmin = userType == 'super_admin' || userType == 'developer';

    return menuItems.where((item) {
      if (item.isSuperAdminOnly && !isSuperAdmin) return false;
      return true;
    }).map((item) {
      return _SidebarMenuItemWidget(
        key: _getKeyForItem(item.id),
        item: item,
        currentUser: widget.currentUser,
        depth: 0,
        isCollapsed: isCollapsed,
        selectedPageId: widget.currentPageId,
        sidebarState: state,
        onNavigate: widget.onNavigate,
        getKeyForItem: _getKeyForItem,
      );
    }).toList();
  }
}

/// Widget for rendering individual menu items
class _SidebarMenuItemWidget extends StatelessWidget {
  final SidebarMenuItem item;
  final Map<String, dynamic> currentUser;
  final int depth;
  final bool isCollapsed;
  final String? selectedPageId;
  final SidebarState sidebarState;
  final Function(String pageId, Widget page)? onNavigate;
  final GlobalKey Function(String itemId)? getKeyForItem;

  const _SidebarMenuItemWidget({
    super.key,
    required this.item,
    required this.currentUser,
    required this.depth,
    required this.isCollapsed,
    required this.selectedPageId,
    required this.sidebarState,
    this.onNavigate,
    this.getKeyForItem,
  });

  @override
  Widget build(BuildContext context) {
    // Check permission if required
    if (item.permissionModule != null) {
      return FutureBuilder<bool>(
        future: PermissionHelper.hasPermission(currentUser, item.permissionModule!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox.shrink();
          }
          if (snapshot.data != true) {
            return const SizedBox.shrink();
          }
          return _buildMenuItem(context);
        },
      );
    }

    return _buildMenuItem(context);
  }

  Widget _buildMenuItem(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    final isDirectlySelected = selectedPageId == item.id;
    // Check if this item or any of its children is selected (for parent highlighting)
    final isChildSelected = item.hasChildren && _isAnyChildSelected(item, selectedPageId);
    final isSelected = isDirectlySelected || isChildSelected;
    final isExpanded = sidebarState.isExpanded(item.id);
    final hasChildren = item.hasChildren;

    // For collapsed sidebar, show icons only
    if (isCollapsed) {
      return Tooltip(
        message: item.title,
        preferBelow: false,
        child: InkWell(
          onTap: () => _handleCollapsedNavigate(context),
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.1),
          splashColor: item.color.withValues(alpha: 0.3),
          child: Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: isSelected
                  ? item.color.withValues(alpha: 0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? Border.all(color: item.color.withValues(alpha: 0.6), width: 2)
                  : null,
            ),
            child: Icon(
              item.icon,
              size: ds.iconSize,
              color: isSelected ? item.color : Colors.grey[400],
            ),
          ),
        ),
      );
    }

    // Expanded sidebar - show full menu items
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? item.color.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: item.color.withValues(alpha: 0.5), width: 1.5)
                : null,
          ),
          child: Row(
            children: [
              // Icon and Title - clickable to navigate
              Expanded(
                child: InkWell(
                  onTap: () => _handleNavigate(context),
                  borderRadius: BorderRadius.circular(10),
                  hoverColor: Colors.white.withValues(alpha: 0.08),
                  splashColor: item.color.withValues(alpha: 0.2),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 14 + (depth * 16.0),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? item.color.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            item.icon,
                            size: ds.iconSize * 0.85,
                            color: isSelected ? item.color : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: ds.bodyFontSize,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected ? Colors.white : Colors.grey[300],
                              letterSpacing: 0.3,
                              fontFamily: 'Segoe UI',
                              decoration: TextDecoration.none,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Chevron - clickable to expand/collapse (only for items with children)
              if (hasChildren)
                InkWell(
                  onTap: () => sidebarState.toggleExpanded(item.id),
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: Colors.white.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 150),
                      turns: isExpanded ? 0.25 : 0,
                      child: Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Children (expandable)
        if (hasChildren)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 150),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: item.children.map((child) {
                return _SidebarMenuItemWidget(
                  key: getKeyForItem?.call(child.id),
                  item: child,
                  currentUser: currentUser,
                  depth: depth + 1,
                  isCollapsed: isCollapsed,
                  selectedPageId: selectedPageId,
                  sidebarState: sidebarState,
                  onNavigate: onNavigate,
                  getKeyForItem: getKeyForItem,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  /// Navigate to the item's page, or just expand if it has children
  void _handleNavigate(BuildContext context) {
    if (item.hasChildren) {
      // For parent items, toggle expand/collapse (don't navigate to menu page)
      // Menu page navigation only happens when sidebar is collapsed
      sidebarState.toggleExpanded(item.id);
    } else if (item.pageBuilder != null) {
      // For leaf items (no children), navigate to the page
      sidebarState.setSelectedPage(item.id);
      final page = item.pageBuilder!(currentUser);
      if (onNavigate != null) {
        onNavigate!(item.id, page);
      }
    }
  }

  /// Handle navigation when sidebar is collapsed
  /// Navigates directly to the menu page for the category
  void _handleCollapsedNavigate(BuildContext context) {
    if (item.pageBuilder != null) {
      // Navigate to the item's own page (menu page for parent items)
      sidebarState.setSelectedPage(item.id);
      final page = item.pageBuilder!(currentUser);
      if (onNavigate != null) {
        onNavigate!(item.id, page);
      }
    }
  }

}

/// Helper function to check if any child (or nested child) is selected
bool _isAnyChildSelected(SidebarMenuItem parent, String? selectedPageId) {
  if (selectedPageId == null) return false;

  for (final child in parent.children) {
    // Check if this child is selected
    if (child.id == selectedPageId) {
      return true;
    }
    // Check if selectedPageId starts with this child's id (for nested pages)
    if (selectedPageId.startsWith('${child.id}/')) {
      return true;
    }
    // Recursively check nested children
    if (child.hasChildren && _isAnyChildSelected(child, selectedPageId)) {
      return true;
    }
  }
  return false;
}

