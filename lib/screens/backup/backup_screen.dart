// lib/screens/backup/backup_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/cloud_sync_helper.dart';
import 'backup_reminder_settings_screen.dart';
import 'offline_backup_screen.dart';
import 'online_backup_screen.dart';
import 'sync_dsm_screen.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  Map<String, dynamic>? _currentUser;
  bool _isReadOnlyMode = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';
    final readOnly = await CloudSyncHelper.isReadOnlyMode();

    if (mounted) {
      setState(() {
        _currentUser = {
          'id': userId,
          'userType': userType,
          'username': username,
        };
        _isReadOnlyMode = readOnly;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Text(
              'Manage Your Backups',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Protect your data and configure backup settings',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // Navigation Cards
            Expanded(
              child: ListView(
                children: [
                  // Backup Reminder Settings Card
                  _NavigationCard(
                    title: 'Backup Reminder Settings',
                    description: 'Configure automatic backup reminders and alerts',
                    icon: Icons.notifications_active,
                    color: Colors.blue,
                    onTap: () {
                      NavigationHelper.pushWithSidebar(
                        context,
                        page: const BackupReminderSettingsScreen(),
                        currentUser: _currentUser ?? {},
                        pageId: 'preferences/backup',
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Offline Backup Card
                  _NavigationCard(
                    title: 'Offline Backup',
                    description: 'Create and restore backups on your device',
                    icon: Icons.backup,
                    color: Colors.teal,
                    onTap: () {
                      NavigationHelper.pushWithSidebar(
                        context,
                        page: const OfflineBackupScreen(),
                        currentUser: _currentUser ?? {},
                        pageId: 'preferences/backup',
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Online Backup Card — locked in Read-Only mode
                  _NavigationCard(
                    title: 'Online Backup',
                    description: _isReadOnlyMode
                        ? 'Not available in Read-Only Mode'
                        : 'Backup and restore using Google Drive cloud storage',
                    icon: Icons.cloud,
                    color: Colors.blue.shade700,
                    disabled: _isReadOnlyMode,
                    onTap: _isReadOnlyMode
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(Icons.lock, color: Colors.white, size: 16),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Online Backup is disabled in Read-Only Mode. '
                                        'Switch to Write Mode in Preferences → CloudSync.',
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: Colors.orange.shade700,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        : () {
                            NavigationHelper.pushWithSidebar(
                              context,
                              page: const OnlineBackupScreen(),
                              currentUser: _currentUser ?? {},
                              pageId: 'preferences/backup',
                            );
                          },
                  ),

                  const SizedBox(height: 16),

                  // Sync with DSM Card
                  _NavigationCard(
                    title: 'Sync with DSM',
                    description: 'Receive student, class and academic data from the DSM desktop app',
                    icon: Icons.sync_alt,
                    color: Colors.indigo,
                    onTap: () {
                      NavigationHelper.pushWithSidebar(
                        context,
                        page: const SyncDsmScreen(),
                        currentUser: _currentUser ?? {},
                        pageId: 'preferences/backup',
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;

  const _NavigationCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = disabled ? Colors.grey : color;

    return Card(
      elevation: disabled ? 0 : 2,
      color: disabled ? Colors.grey.shade100 : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Icon Container
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: effectiveColor,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),

              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: disabled ? Colors.grey : null,
                          ),
                        ),
                        if (disabled) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.lock, size: 14, color: Colors.orange.shade700),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: disabled ? Colors.orange.shade700 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow / Lock Icon
              Icon(
                disabled ? Icons.lock_outline : Icons.arrow_forward_ios,
                color: disabled ? Colors.orange.shade300 : Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
