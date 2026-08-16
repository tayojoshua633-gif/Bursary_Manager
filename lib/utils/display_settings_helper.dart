// lib/utils/display_settings_helper.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display mode enum for different screen sizes
enum DisplayMode {
  auto,        // Auto-detect based on screen size
  largeTablet, // 12"+ tablets, large screens
  tablet,      // 10-11" tablets
  smallTablet, // 7-9" tablets
  smartphone,  // Small phones, POS devices (< 7")
}

/// Display settings configuration
class DisplaySettings {
  final DisplayMode mode;
  final String name;
  final double titleFontSize;
  final double bodyFontSize;
  final double subtitleFontSize;
  final double cardPadding;
  final double buttonHeight;
  final double iconSize;
  final double gridMaxExtent;
  final double gridMaxExtentLandscape;
  final double childAspectRatio;
  final double childAspectRatioLandscape;

  const DisplaySettings({
    required this.mode,
    required this.name,
    required this.titleFontSize,
    required this.bodyFontSize,
    required this.subtitleFontSize,
    required this.cardPadding,
    required this.buttonHeight,
    required this.iconSize,
    required this.gridMaxExtent,
    required this.gridMaxExtentLandscape,
    required this.childAspectRatio,
    required this.childAspectRatioLandscape,
  });

  /// Get description for this display mode
  String get description {
    switch (mode) {
      case DisplayMode.auto:
        return 'Automatically adjusts based on screen size';
      case DisplayMode.largeTablet:
        return 'For large tablets 12" and above';
      case DisplayMode.tablet:
        return 'For standard tablets (10-11")';
      case DisplayMode.smallTablet:
        return 'For small tablets (7-9")';
      case DisplayMode.smartphone:
        return 'For phones and POS devices (< 7")';
    }
  }

  /// Get icon for this display mode
  IconData get icon {
    switch (mode) {
      case DisplayMode.auto:
        return Icons.auto_fix_high;
      case DisplayMode.largeTablet:
        return Icons.tablet;
      case DisplayMode.tablet:
        return Icons.tablet_mac;
      case DisplayMode.smallTablet:
        return Icons.tablet_android;
      case DisplayMode.smartphone:
        return Icons.smartphone;
    }
  }
}

class DisplaySettingsHelper {
  static const String _displayModeKey = 'display_mode';

  // PRESET CONFIGURATIONS FOR DISPLAY MODES
  // ========================================

  /// Auto Mode (placeholder - actual settings determined at runtime)
  static const DisplaySettings autoMode = DisplaySettings(
    mode: DisplayMode.auto,
    name: 'Auto',
    titleFontSize: 18,  // Default values, overridden by auto-detect
    bodyFontSize: 14,
    subtitleFontSize: 12,
    cardPadding: 16,
    buttonHeight: 48,
    iconSize: 24,
    gridMaxExtent: 250,
    gridMaxExtentLandscape: 400,
    childAspectRatio: 0.85,
    childAspectRatioLandscape: 1.4,
  );

  /// Large Tablet Mode (12"+)
  /// - Largest fonts and spacing
  /// - Very spacious layout
  static const DisplaySettings largeTabletMode = DisplaySettings(
    mode: DisplayMode.largeTablet,
    name: 'Large Tablet',
    titleFontSize: 20,
    bodyFontSize: 16,
    subtitleFontSize: 14,
    cardPadding: 20,
    buttonHeight: 52,
    iconSize: 28,
    gridMaxExtent: 300,
    gridMaxExtentLandscape: 450,
    childAspectRatio: 0.8,
    childAspectRatioLandscape: 1.5,
  );

  /// Tablet Mode (10-11")
  /// - Standard tablet layout
  static const DisplaySettings tabletMode = DisplaySettings(
    mode: DisplayMode.tablet,
    name: 'Tablet',
    titleFontSize: 18,
    bodyFontSize: 14,
    subtitleFontSize: 12,
    cardPadding: 16,
    buttonHeight: 48,
    iconSize: 24,
    gridMaxExtent: 250,
    gridMaxExtentLandscape: 400,
    childAspectRatio: 0.85,
    childAspectRatioLandscape: 1.4,
  );

  /// Small Tablet Mode (7-9")
  /// - Slightly smaller layout
  static const DisplaySettings smallTabletMode = DisplaySettings(
    mode: DisplayMode.smallTablet,
    name: 'Small Tablet',
    titleFontSize: 16,
    bodyFontSize: 13,
    subtitleFontSize: 11,
    cardPadding: 14,
    buttonHeight: 44,
    iconSize: 22,
    gridMaxExtent: 220,
    gridMaxExtentLandscape: 340,
    childAspectRatio: 0.88,
    childAspectRatioLandscape: 1.3,
  );

  /// Smartphone Mode (< 7")
  /// - Compact layout for small screens
  static const DisplaySettings smartphoneMode = DisplaySettings(
    mode: DisplayMode.smartphone,
    name: 'Smartphone',
    titleFontSize: 15,
    bodyFontSize: 12,
    subtitleFontSize: 10,
    cardPadding: 10,
    buttonHeight: 40,
    iconSize: 20,
    gridMaxExtent: 180,
    gridMaxExtentLandscape: 280,
    childAspectRatio: 0.9,
    childAspectRatioLandscape: 1.2,
  );

  // AVAILABLE MODES (for display in settings)
  static const List<DisplaySettings> availableModes = [
    autoMode,
    largeTabletMode,
    tabletMode,
    smallTabletMode,
    smartphoneMode,
  ];

  /// Get current display mode setting
  static Future<DisplaySettings> getCurrentSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_displayModeKey);

    switch (savedMode) {
      case 'auto':
        return autoMode;
      case 'largeTablet':
        return largeTabletMode;
      case 'tablet':
        return tabletMode;
      case 'smallTablet':
        return smallTabletMode;
      case 'smartphone':
        return smartphoneMode;
      default:
        return autoMode; // Default to auto mode
    }
  }

  /// Save display mode setting
  static Future<void> setCurrentMode(DisplayMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayModeKey, mode.name);
  }

  /// Get display settings by mode (without auto-detect)
  static DisplaySettings getSettingsByMode(DisplayMode mode) {
    switch (mode) {
      case DisplayMode.auto:
        return autoMode;
      case DisplayMode.largeTablet:
        return largeTabletMode;
      case DisplayMode.tablet:
        return tabletMode;
      case DisplayMode.smallTablet:
        return smallTabletMode;
      case DisplayMode.smartphone:
        return smartphoneMode;
    }
  }

  /// Auto-detect appropriate settings based on screen size
  /// Call this with the BuildContext to get actual screen dimensions
  static DisplaySettings autoDetectSettings(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;

    // Estimate screen size category based on shortest side in logical pixels
    // These thresholds work well across different device densities
    if (shortestSide >= 900) {
      // Very large screens (12"+)
      return largeTabletMode;
    } else if (shortestSide >= 700) {
      // Standard tablets (10-11")
      return tabletMode;
    } else if (shortestSide >= 500) {
      // Small tablets (7-9")
      return smallTabletMode;
    } else {
      // Phones and small POS devices (< 7")
      return smartphoneMode;
    }
  }

  /// Get the effective display settings (handles auto mode)
  static DisplaySettings getEffectiveSettings(BuildContext context, DisplayMode mode) {
    if (mode == DisplayMode.auto) {
      return autoDetectSettings(context);
    }
    return getSettingsByMode(mode);
  }

  /// Get current display mode (just the enum)
  static Future<DisplayMode> getCurrentMode() async {
    final settings = await getCurrentSettings();
    return settings.mode;
  }

  /// Reset to default (auto mode)
  static Future<void> resetToDefault() async {
    await setCurrentMode(DisplayMode.auto);
  }
}

/// InheritedWidget to provide display settings throughout the app
class DisplaySettingsProvider extends InheritedWidget {
  final DisplaySettings settings;
  final DisplayMode selectedMode; // The user's selected mode (may be auto)
  final Function(DisplayMode) onModeChanged;

  const DisplaySettingsProvider({
    super.key,
    required this.settings,
    required this.selectedMode,
    required this.onModeChanged,
    required super.child,
  });

  static DisplaySettingsProvider? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DisplaySettingsProvider>();
  }

  static DisplaySettings of(BuildContext context) {
    final provider = maybeOf(context);
    if (provider == null) {
      // Fallback: auto-detect if no provider found
      return DisplaySettingsHelper.autoDetectSettings(context);
    }

    // If auto mode, detect based on screen size
    if (provider.selectedMode == DisplayMode.auto) {
      return DisplaySettingsHelper.autoDetectSettings(context);
    }

    return provider.settings;
  }

  static DisplayMode? selectedModeOf(BuildContext context) {
    final provider = maybeOf(context);
    return provider?.selectedMode;
  }

  static Function(DisplayMode)? onModeChangedOf(BuildContext context) {
    final provider = maybeOf(context);
    return provider?.onModeChanged;
  }

  @override
  bool updateShouldNotify(DisplaySettingsProvider oldWidget) {
    return settings.mode != oldWidget.settings.mode ||
           selectedMode != oldWidget.selectedMode;
  }
}

/// Extension methods for easy access to display settings
extension DisplaySettingsContext on BuildContext {
  DisplaySettings get displaySettings => DisplaySettingsProvider.of(this);

  double get titleFontSize => displaySettings.titleFontSize;
  double get bodyFontSize => displaySettings.bodyFontSize;
  double get subtitleFontSize => displaySettings.subtitleFontSize;
  double get cardPadding => displaySettings.cardPadding;
  double get buttonHeight => displaySettings.buttonHeight;
  double get iconSize => displaySettings.iconSize;

  /// Get grid max extent based on orientation
  double get gridMaxExtent {
    final isLandscape = MediaQuery.of(this).orientation == Orientation.landscape;
    return isLandscape
        ? displaySettings.gridMaxExtentLandscape
        : displaySettings.gridMaxExtent;
  }

  /// Get child aspect ratio based on orientation
  double get gridChildAspectRatio {
    final isLandscape = MediaQuery.of(this).orientation == Orientation.landscape;
    return isLandscape
        ? displaySettings.childAspectRatioLandscape
        : displaySettings.childAspectRatio;
  }
}
