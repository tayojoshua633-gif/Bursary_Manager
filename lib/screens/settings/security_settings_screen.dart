// lib/screens/settings/security_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/display_settings_helper.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  static const String _autoLogoutKey = 'auto_logout_minutes';
  static const int _defaultLogoutMinutes = 5;

  int _selectedMinutes = _defaultLogoutMinutes;
  bool _loading = true;

  // Preset duration options (0 = always logged in)
  final List<int> _durationOptions = [1, 2, 3, 5, 10, 15, 30, 60, 0];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMinutes = prefs.getInt(_autoLogoutKey) ?? _defaultLogoutMinutes;

    if (mounted) {
      setState(() {
        _selectedMinutes = savedMinutes;
        _loading = false;
      });
    }
  }

  Future<void> _saveSettings(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoLogoutKey, minutes);

    if (mounted) {
      setState(() {
        _selectedMinutes = minutes;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-logout set to ${_formatDuration(minutes)}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDuration(int minutes) {
    if (minutes == 0) return 'Always logged in';
    if (minutes == 1) return '1 minute';
    if (minutes < 60) return '$minutes minutes';
    if (minutes == 60) return '1 hour';
    return '${minutes ~/ 60} hours';
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Settings'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(ds.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Card
                  Card(
                    elevation: 2,
                    color: Colors.red.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(ds.cardPadding),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(ds.cardPadding * 0.75),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.security,
                              size: ds.iconSize * 1.5,
                              color: Colors.red.shade700,
                            ),
                          ),
                          SizedBox(width: ds.cardPadding),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Security Settings',
                                  style: TextStyle(
                                    fontSize: ds.titleFontSize,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                                SizedBox(height: ds.cardPadding * 0.25),
                                Text(
                                  'Configure app security and session management',
                                  style: TextStyle(
                                    fontSize: ds.bodyFontSize * 0.9,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: ds.cardPadding * 1.5),

                  // Auto-Logout Section
                  Text(
                    'Auto-Logout Duration',
                    style: TextStyle(
                      fontSize: ds.titleFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ds.cardPadding * 0.5),
                  Text(
                    'Automatically log out when the app is in the background for this duration',
                    style: TextStyle(
                      fontSize: ds.bodyFontSize * 0.9,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  SizedBox(height: ds.cardPadding),

                  // Current Selection Display
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(ds.cardPadding),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade50,
                            Colors.blue.shade100,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: ds.iconSize * 2,
                            color: Colors.blue.shade700,
                          ),
                          SizedBox(height: ds.cardPadding * 0.5),
                          Text(
                            _formatDuration(_selectedMinutes),
                            style: TextStyle(
                              fontSize: ds.titleFontSize * 1.3,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          SizedBox(height: ds.cardPadding * 0.25),
                          Text(
                            'Current auto-logout duration',
                            style: TextStyle(
                              fontSize: ds.bodyFontSize * 0.9,
                              color: Colors.blue.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: ds.cardPadding * 1.5),

                  // Duration Options
                  Text(
                    'Select Duration',
                    style: TextStyle(
                      fontSize: ds.titleFontSize * 0.9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: ds.cardPadding * 0.75),

                  Wrap(
                    spacing: ds.cardPadding * 0.5,
                    runSpacing: ds.cardPadding * 0.5,
                    children: _durationOptions.map((minutes) {
                      final isSelected = minutes == _selectedMinutes;
                      return ChoiceChip(
                        label: Text(
                          _formatDuration(minutes),
                          style: TextStyle(
                            fontSize: ds.bodyFontSize,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Colors.blue.shade600,
                        backgroundColor: Colors.grey.shade200,
                        onSelected: (selected) {
                          if (selected) {
                            _saveSettings(minutes);
                          }
                        },
                        padding: EdgeInsets.symmetric(
                          horizontal: ds.cardPadding * 0.5,
                          vertical: ds.cardPadding * 0.25,
                        ),
                      );
                    }).toList(),
                  ),

                  SizedBox(height: ds.cardPadding * 2),

                  // Info Card
                  Card(
                    elevation: 1,
                    color: Colors.amber.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(ds.cardPadding),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: ds.iconSize,
                            color: Colors.amber.shade800,
                          ),
                          SizedBox(width: ds.cardPadding * 0.75),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'How it works',
                                  style: TextStyle(
                                    fontSize: ds.bodyFontSize,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                                SizedBox(height: ds.cardPadding * 0.25),
                                Text(
                                  'When you switch to another app or lock your phone, the timer starts. If you return before the timer expires, you stay logged in. Otherwise, you\'ll be automatically logged out for security.',
                                  style: TextStyle(
                                    fontSize: ds.bodyFontSize * 0.85,
                                    color: Colors.amber.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: ds.cardPadding),

                  // Note about brief interruptions
                  Card(
                    elevation: 1,
                    color: Colors.green.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(ds.cardPadding),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: ds.iconSize,
                            color: Colors.green.shade700,
                          ),
                          SizedBox(width: ds.cardPadding * 0.75),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Brief interruptions',
                                  style: TextStyle(
                                    fontSize: ds.bodyFontSize,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                                SizedBox(height: ds.cardPadding * 0.25),
                                Text(
                                  'Opening file pickers, notifications, or receiving calls won\'t trigger the auto-logout timer.',
                                  style: TextStyle(
                                    fontSize: ds.bodyFontSize * 0.85,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
