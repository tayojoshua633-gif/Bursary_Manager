// lib/navigation/sidebar_state_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the state of the sidebar navigation
class SidebarState extends ChangeNotifier {
  // Collapse/expand state for the entire sidebar
  bool _isCollapsed = false;
  bool get isCollapsed => _isCollapsed;

  // Currently selected page ID (e.g., 'student_management/students')
  String? _selectedPageId;
  String? get selectedPageId => _selectedPageId;

  // Set of expanded parent IDs
  final Set<String> _expandedParents = {};

  // Persist state keys
  static const String _collapsedKey = 'sidebar_collapsed';
  static const String _expandedKey = 'sidebar_expanded_parents';

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  SidebarState() {
    _loadState();
  }

  /// Load persisted state from SharedPreferences
  /// Note: Expanded parents are NOT loaded - sidebar starts with all collapsed
  /// Only the current page's parent hierarchy expands when navigating
  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isCollapsed = prefs.getBool(_collapsedKey) ?? false;
      // Don't load expanded parents - start with all collapsed by default
      // _expandedParents will only be populated when a page is selected
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading sidebar state: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Toggle the sidebar collapsed/expanded state
  Future<void> toggleCollapsed() async {
    _isCollapsed = !_isCollapsed;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_collapsedKey, _isCollapsed);
    } catch (e) {
      debugPrint('Error saving collapsed state: $e');
    }
  }

  /// Set the collapsed state directly
  Future<void> setCollapsed(bool collapsed) async {
    if (_isCollapsed == collapsed) return;
    _isCollapsed = collapsed;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_collapsedKey, _isCollapsed);
    } catch (e) {
      debugPrint('Error saving collapsed state: $e');
    }
  }

  /// Set the currently selected page and auto-expand its parents
  void setSelectedPage(String pageId) {
    _selectedPageId = pageId;
    _autoExpandParentsForPage(pageId);
    notifyListeners();
  }

  /// Auto-expand only the parent categories for the current page
  /// Collapses all other parents first so only active page's hierarchy is shown
  void _autoExpandParentsForPage(String pageId) {
    // Clear all expanded parents first - only show current page's hierarchy
    _expandedParents.clear();

    // Expand only parents of the current page
    final parts = pageId.split('/');
    String path = '';
    for (int i = 0; i < parts.length - 1; i++) {
      path += (path.isEmpty ? '' : '/') + parts[i];
      _expandedParents.add(path);
    }
    _persistExpandedState();
  }

  /// Check if a parent category is expanded
  bool isExpanded(String parentId) => _expandedParents.contains(parentId);

  /// Toggle the expanded state of a parent category
  void toggleExpanded(String parentId) {
    if (_expandedParents.contains(parentId)) {
      _expandedParents.remove(parentId);
    } else {
      _expandedParents.add(parentId);
    }
    _persistExpandedState();
    notifyListeners();
  }

  /// Expand a parent category
  void expand(String parentId) {
    if (!_expandedParents.contains(parentId)) {
      _expandedParents.add(parentId);
      _persistExpandedState();
      notifyListeners();
    }
  }

  /// Collapse a parent category
  void collapse(String parentId) {
    if (_expandedParents.contains(parentId)) {
      _expandedParents.remove(parentId);
      _persistExpandedState();
      notifyListeners();
    }
  }

  /// Collapse all parent categories
  void collapseAll() {
    _expandedParents.clear();
    _persistExpandedState();
    notifyListeners();
  }

  /// Persist expanded parents state
  Future<void> _persistExpandedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_expandedKey, _expandedParents.toList());
    } catch (e) {
      debugPrint('Error saving expanded state: $e');
    }
  }

  /// Get all expanded parent IDs
  Set<String> get expandedParents => Set.unmodifiable(_expandedParents);
}

/// InheritedNotifier widget to provide SidebarState throughout the app
class SidebarStateProvider extends InheritedNotifier<SidebarState> {
  const SidebarStateProvider({
    super.key,
    required SidebarState state,
    required super.child,
  }) : super(notifier: state);

  static SidebarState of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<SidebarStateProvider>();
    return provider!.notifier!;
  }

  static SidebarState? maybeOf(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<SidebarStateProvider>();
    return provider?.notifier;
  }
}
