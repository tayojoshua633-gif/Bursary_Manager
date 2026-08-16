// lib/screens/permissions/permission_management_screen.dart
import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/permission.dart';
import '../../utils/permission_helper.dart';

class PermissionManagementScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const PermissionManagementScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<PermissionManagementScreen> createState() =>
      _PermissionManagementScreenState();
}

class _PermissionManagementScreenState extends State<PermissionManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _db = DatabaseHelperWrapper();

  final Map<String, Map<String, bool>> _permissions = {
    'admin': {},
    'bursar': {},
  };

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPermissions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    setState(() => _isLoading = true);

    // Load permissions for both admin and bursar roles
    for (var role in ['admin', 'bursar']) {
      final perms = await _db.getPermissionsByRole(role);

      // Initialize all modules from PermissionModule
      _permissions[role] = {};
      for (var module in PermissionModule.getAllModules()) {
        // Find if this module has a permission entry
        final permEntry = perms.firstWhere(
          (p) => p['module'] == module,
          orElse: () => {'canAccess': 0},
        );
        _permissions[role]![module] = permEntry['canAccess'] == 1;
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePermissions(String role) async {
    setState(() => _isSaving = true);

    try {
      await _db.updateRolePermissions(role, _permissions[role]!);
      PermissionHelper.clearCache(); // Clear cache so changes take effect

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_capitalizeRole(role)} permissions updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating permissions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _resetToDefaults(String role) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: Text(
          'Are you sure you want to reset ${_capitalizeRole(role)} permissions to default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      // Reset permissions in database by clearing and reseeding
      final db = await _db.database;
      await db.delete('permissions', where: 'role = ?', whereArgs: [role]);
      await _db.database.then((db) async {
        // Reseed using the same logic from _seedDefaultPermissions
        if (role == 'admin') {
          final adminPermissions = [
            'dashboard',
            'session_term',
            'students_view',
            'students_add',
            'students_edit',
            'students_batch_upload',
            'students_promote',
            'students_deactivate',
            'students_inactive',
            'students_statement',
            'classes_arms',
            'fee_items_view',
            'fee_items_manage',
            'fee_class_assignment',
            'billing_generate',
            'billing_print',
            'payments_record',
            'payments_edit',
            'payments_receipt',
            'payments_history',
            'reports_daily',
            'reports_debtors',
            'reports_termly',
            'reports_overpayment',
            'reports_fees_balance',
            'audit_log_view',
            'expenses',
            'school_profile',
            'license_management',
            'thermal_printer',
            'backup',
          ];
          for (var module in adminPermissions) {
            await db.insert('permissions', {
              'role': 'admin',
              'module': module,
              'canAccess': 1,
            });
          }
        } else if (role == 'bursar') {
          final bursarPermissions = [
            'dashboard',
            'students_view',
            'students_statement',
            'billing_generate',
            'billing_print',
            'payments_record',
            'payments_receipt',
            'payments_history',
            'reports_daily',
            'reports_debtors',
            'reports_termly',
            'reports_overpayment',
            'reports_fees_balance',
            'expenses',
          ];
          for (var module in bursarPermissions) {
            await db.insert('permissions', {
              'role': 'bursar',
              'module': module,
              'canAccess': 1,
            });
          }
        }
      });

      PermissionHelper.clearCache();
      await _loadPermissions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_capitalizeRole(role)} permissions reset to defaults'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }

  String _capitalizeRole(String role) {
    return role[0].toUpperCase() + role.substring(1);
  }

  Widget _buildPermissionTab(String role) {
    final rolePermissions = _permissions[role]!;
    final enabledCount = rolePermissions.values.where((v) => v).length;
    final totalCount = rolePermissions.length;

    return Column(
      children: [
        // Summary card
        Card(
          color: Colors.blue[50],
          margin: const EdgeInsets.all(16),
          child: ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.blue, size: 32),
            title: Text(
              '$enabledCount of $totalCount features enabled',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text('Configure what ${_capitalizeRole(role)} users can access'),
          ),
        ),

        // Permission list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: PermissionModule.displayNames.entries.map((entry) {
              final module = entry.key;
              final displayName = entry.value;
              final isEnabled = rolePermissions[module] ?? false;
              final isUserManagement = module == 'user_management';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: CheckboxListTile(
                  title: Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: isEnabled ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: isUserManagement
                      ? const Text(
                          'Super Admin Only',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        )
                      : null,
                  value: isEnabled,
                  enabled: !isUserManagement, // Disable user_management checkbox
                  onChanged: isUserManagement
                      ? null
                      : (value) {
                          setState(() {
                            rolePermissions[module] = value!;
                          });
                        },
                  activeColor: Colors.green,
                ),
              );
            }).toList(),
          ),
        ),

        // Save and Reset buttons
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : () => _savePermissions(role),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text('Save ${_capitalizeRole(role)} Permissions'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : () => _resetToDefaults(role),
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Access check - only super_admin can access this screen
    if (widget.currentUser['userType'] != 'super_admin') {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Access Denied'),
          backgroundColor: Colors.red,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Only Super Admin can manage permissions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permission Management'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.admin_panel_settings),
              text: 'Admin Permissions',
            ),
            Tab(
              icon: Icon(Icons.account_balance_wallet),
              text: 'Bursar Permissions',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPermissionTab('admin'),
                _buildPermissionTab('bursar'),
              ],
            ),
    );
  }
}
