// lib/screens/settings/display_settings_screen.dart

import 'package:flutter/material.dart';
import '../../utils/display_settings_helper.dart';

class DisplaySettingsScreen extends StatefulWidget {
  const DisplaySettingsScreen({super.key});

  @override
  State<DisplaySettingsScreen> createState() => _DisplaySettingsScreenState();
}

class _DisplaySettingsScreenState extends State<DisplaySettingsScreen> {
  DisplayMode _selectedMode = DisplayMode.auto;
  DisplayMode _originalMode = DisplayMode.auto;
  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentMode();
  }

  Future<void> _loadCurrentMode() async {
    final mode = await DisplaySettingsHelper.getCurrentMode();
    setState(() {
      _selectedMode = mode;
      _originalMode = mode;
      _isLoading = false;
    });
  }

  void _selectMode(DisplayMode mode) {
    setState(() {
      _selectedMode = mode;
      _hasChanges = mode != _originalMode;
    });
  }

  Future<void> _saveAndApply() async {
    await DisplaySettingsHelper.setCurrentMode(_selectedMode);

    if (!mounted) return;

    // Notify the app to rebuild with new settings
    final onModeChanged = DisplaySettingsProvider.onModeChangedOf(context);
    if (onModeChanged != null) {
      onModeChanged(_selectedMode);
    }

    setState(() {
      _originalMode = _selectedMode;
      _hasChanges = false;
    });

    if (mounted) {
      final settings = DisplaySettingsHelper.getSettingsByMode(_selectedMode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('Display mode saved: ${settings.name}'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Get the effective settings for preview (handles auto mode)
  DisplaySettings _getEffectiveSettings() {
    if (_selectedMode == DisplayMode.auto) {
      return DisplaySettingsHelper.autoDetectSettings(context);
    }
    return DisplaySettingsHelper.getSettingsByMode(_selectedMode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Display Settings'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Card(
                    color: Colors.teal.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.display_settings,
                              size: 32, color: Colors.teal.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Screen Size Optimization',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Choose a display mode that fits your device',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Display Mode Selection
                  const Text(
                    'Select Display Mode',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Auto Mode Card (Recommended)
                  _buildModeCard(
                    mode: DisplayMode.auto,
                    settings: DisplaySettingsHelper.autoMode,
                    isSelected: _selectedMode == DisplayMode.auto,
                    onTap: () => _selectMode(DisplayMode.auto),
                    isRecommended: true,
                    detectedMode: _selectedMode == DisplayMode.auto
                        ? DisplaySettingsHelper.autoDetectSettings(context)
                        : null,
                  ),

                  const SizedBox(height: 16),

                  // Divider with label
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Or choose manually',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Large Tablet Mode
                  _buildModeCard(
                    mode: DisplayMode.largeTablet,
                    settings: DisplaySettingsHelper.largeTabletMode,
                    isSelected: _selectedMode == DisplayMode.largeTablet,
                    onTap: () => _selectMode(DisplayMode.largeTablet),
                  ),

                  const SizedBox(height: 12),

                  // Tablet Mode
                  _buildModeCard(
                    mode: DisplayMode.tablet,
                    settings: DisplaySettingsHelper.tabletMode,
                    isSelected: _selectedMode == DisplayMode.tablet,
                    onTap: () => _selectMode(DisplayMode.tablet),
                  ),

                  const SizedBox(height: 12),

                  // Small Tablet Mode
                  _buildModeCard(
                    mode: DisplayMode.smallTablet,
                    settings: DisplaySettingsHelper.smallTabletMode,
                    isSelected: _selectedMode == DisplayMode.smallTablet,
                    onTap: () => _selectMode(DisplayMode.smallTablet),
                  ),

                  const SizedBox(height: 12),

                  // Smartphone Mode
                  _buildModeCard(
                    mode: DisplayMode.smartphone,
                    settings: DisplaySettingsHelper.smartphoneMode,
                    isSelected: _selectedMode == DisplayMode.smartphone,
                    onTap: () => _selectMode(DisplayMode.smartphone),
                  ),

                  const SizedBox(height: 24),

                  // Preview Section
                  const Text(
                    'Preview',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewCard(),

                  const SizedBox(height: 24),

                  // Info Section
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Select a display mode and tap Save to apply changes. Auto mode detects your screen size automatically.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _hasChanges ? _saveAndApply : null,
                      icon: const Icon(Icons.save),
                      label: Text(
                        _hasChanges ? 'Save Changes' : 'No Changes',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade500,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  // Unsaved changes indicator
                  if (_hasChanges)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info, size: 16, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'You have unsaved changes',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildModeCard({
    required DisplayMode mode,
    required DisplaySettings settings,
    required bool isSelected,
    required VoidCallback onTap,
    bool isRecommended = false,
    DisplaySettings? detectedMode,
  }) {
    final isAutoMode = mode == DisplayMode.auto;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal.shade50 : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.teal : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.teal.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.teal.shade100
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                settings.icon,
                size: 32,
                color: isSelected ? Colors.teal : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 16),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        settings.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.teal.shade700 : Colors.black87,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Recommended',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    settings.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  // Show detected mode for auto
                  if (isAutoMode && detectedMode != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: Colors.amber.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'Detected: ${detectedMode.name}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Show specs for non-auto modes
                  if (!isAutoMode) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildSpecChip('Font: ${settings.bodyFontSize.toInt()}px'),
                        _buildSpecChip('Padding: ${settings.cardPadding.toInt()}px'),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Selection indicator
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? Colors.teal : Colors.grey.shade400,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    final settings = _getEffectiveSettings();

    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(settings.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show which mode is being previewed
            if (_selectedMode == DisplayMode.auto)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Previewing: ${settings.name} (auto-detected)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.teal.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            // Preview header
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(settings.cardPadding / 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.preview,
                    size: settings.iconSize,
                    color: Colors.blue.shade700,
                  ),
                ),
                SizedBox(width: settings.cardPadding),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sample Card Title',
                        style: TextStyle(
                          fontSize: settings.titleFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: settings.cardPadding / 4),
                      Text(
                        'This is how body text will appear',
                        style: TextStyle(
                          fontSize: settings.bodyFontSize,
                        ),
                      ),
                      SizedBox(height: settings.cardPadding / 4),
                      Text(
                        'Subtitle or secondary text',
                        style: TextStyle(
                          fontSize: settings.subtitleFontSize,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: settings.cardPadding),
            // Preview button
            SizedBox(
              height: settings.buttonHeight,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: Icon(Icons.check, size: settings.iconSize * 0.8),
                label: Text(
                  'Sample Button',
                  style: TextStyle(fontSize: settings.bodyFontSize),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
