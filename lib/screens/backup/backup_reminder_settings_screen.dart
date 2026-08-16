// lib/screens/backup/backup_reminder_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/backup_reminder_helper.dart';

class BackupReminderSettingsScreen extends StatefulWidget {
  const BackupReminderSettingsScreen({super.key});

  @override
  State<BackupReminderSettingsScreen> createState() => _BackupReminderSettingsScreenState();
}

class _BackupReminderSettingsScreenState extends State<BackupReminderSettingsScreen> {
  bool _isLoading = true;

  // Reminder settings
  bool _remindersEnabled = true;
  int _transactionThreshold = 50;
  int _warningDays = 7;
  int _criticalDays = 14;

  // Text editing controllers for persistent cursor position
  late final TextEditingController _transactionController;
  late final TextEditingController _warningDaysController;
  late final TextEditingController _criticalDaysController;

  @override
  void initState() {
    super.initState();
    _transactionController = TextEditingController();
    _warningDaysController = TextEditingController();
    _criticalDaysController = TextEditingController();
    _loadReminderSettings();
  }

  @override
  void dispose() {
    _transactionController.dispose();
    _warningDaysController.dispose();
    _criticalDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadReminderSettings() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _remindersEnabled = prefs.getBool('backup_reminders_enabled') ?? true;
        _transactionThreshold = prefs.getInt('backup_transaction_threshold') ?? 50;
        _warningDays = prefs.getInt('backup_warning_days') ?? 7;
        _criticalDays = prefs.getInt('backup_critical_days') ?? 14;

        // Update text controllers
        _transactionController.text = _transactionThreshold.toString();
        _warningDaysController.text = _warningDays.toString();
        _criticalDaysController.text = _criticalDays.toString();

        _isLoading = false;
      });
    }
  }

  Future<void> _saveReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('backup_reminders_enabled', _remindersEnabled);
    await prefs.setInt('backup_transaction_threshold', _transactionThreshold);
    await prefs.setInt('backup_warning_days', _warningDays);
    await prefs.setInt('backup_critical_days', _criticalDays);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder settings saved successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Reminder Settings'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with toggle
                      Row(
                        children: [
                          const Icon(Icons.notifications_active, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Backup Reminder Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Switch(
                            value: _remindersEnabled,
                            onChanged: (value) {
                              setState(() => _remindersEnabled = value);
                              _saveReminderSettings();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _remindersEnabled
                            ? 'Automatic backup reminders are enabled'
                            : 'Automatic backup reminders are disabled',
                        style: TextStyle(
                          color: _remindersEnabled ? Colors.green : Colors.grey,
                          fontSize: 13,
                        ),
                      ),

                      if (_remindersEnabled) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 16),

                        // Transaction Threshold
                        Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Transaction Threshold',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Remind after this many transactions',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _transactionController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                ),
                                onChanged: (value) {
                                  final intValue = int.tryParse(value);
                                  if (intValue != null && intValue > 0) {
                                    setState(() => _transactionThreshold = intValue);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Warning Days
                        Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.warning, size: 16, color: Colors.orange),
                                      SizedBox(width: 4),
                                      Text(
                                        'Warning Days',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Show warning after this many days',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _warningDaysController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                ),
                                onChanged: (value) {
                                  final intValue = int.tryParse(value);
                                  if (intValue != null && intValue > 0) {
                                    setState(() => _warningDays = intValue);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Critical Days
                        Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.error, size: 16, color: Colors.red),
                                      SizedBox(width: 4),
                                      Text(
                                        'Critical Days',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Force backup after this many days',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _criticalDaysController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                ),
                                onChanged: (value) {
                                  final intValue = int.tryParse(value);
                                  if (intValue != null && intValue > 0) {
                                    setState(() => _criticalDays = intValue);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Current Status Info
                        FutureBuilder<int>(
                          future: BackupReminderHelper.getDaysSinceLastBackup(),
                          builder: (context, daysSnapshot) {
                            return FutureBuilder<int>(
                              future: BackupReminderHelper.getTransactionsSinceBackup(),
                              builder: (context, transSnapshot) {
                                final days = daysSnapshot.data ?? 0;
                                final transactions = transSnapshot.data ?? 0;

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.shade200),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Days since last backup:',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                          Text(
                                            days == 999 ? 'Never' : '$days days',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: days >= _criticalDays
                                                  ? Colors.red
                                                  : days >= _warningDays
                                                      ? Colors.orange
                                                      : Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Transactions since backup:',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                          Text(
                                            '$transactions',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: transactions >= _transactionThreshold
                                                  ? Colors.orange
                                                  : Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        // Save Settings Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _saveReminderSettings,
                            icon: const Icon(Icons.save),
                            label: const Text('Save Reminder Settings'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
