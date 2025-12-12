// lib/screens/auth/user_management_screen.dart
import 'package:flutter/material.dart';
import '../../db/database_helper.dart';

class UserManagementScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const UserManagementScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _db = DatabaseHelper();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _bursarAccount;
  bool _isLoading = true;
  bool _obscurePassword = false;

  @override
  void initState() {
    super.initState();
    _loadBursarAccount();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadBursarAccount() async {
    setState(() => _isLoading = true);

    final account = await _db.getBursarAccount();

    if (mounted) {
      setState(() {
        _bursarAccount = account;
        _usernameController.text = account?['username'] ?? '';
        _passwordController.text = account?['password'] ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateCredentials() async {
    if (!_formKey.currentState!.validate()) return;

    // FIXED: Capture messenger before async operation
    final messenger = ScaffoldMessenger.of(context);

    final success = await _db.resetBursarCredentials(
      newUsername: _usernameController.text.trim(),
      newPassword: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Bursar credentials updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadBursarAccount();
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to update credentials'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _resetToDefault() async {
    // FIXED: Capture messenger BEFORE any async operation (including showDialog)
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset to Default'),
        content: const Text(
          'Are you sure you want to reset bursar credentials to default?\n\n'
          'Username: bursar\n'
          'Password: admin',
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

    if (confirmed != true) return;

    final success = await _db.resetBursarCredentials(
      newUsername: 'bursar',
      newPassword: 'admin',
    );

    if (!mounted) return;

    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Bursar credentials reset to default'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadBursarAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only super admin can access this
    if (widget.currentUser['userType'] != 'super_admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('Only Super Admin can access this page'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Super Admin Info Card
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.admin_panel_settings,
                                  color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              const Text(
                                'Super Admin Account',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _infoRow('Username', 'superadmin'),
                          _infoRow('Password', 'qwerty12345'),
                          _infoRow('Status', 'Fixed (Cannot be changed)'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Bursar Account Management
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.person,
                                    color: Colors.green[700]),
                                const SizedBox(width: 8),
                                const Text(
                                  'Bursar Account',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Username Field
                            TextFormField(
                              controller: _usernameController,
                              decoration: InputDecoration(
                                labelText: 'Username',
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter username';
                                }
                                if (value.trim().toLowerCase() == 'superadmin') {
                                  return 'Cannot use "superadmin" as username';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 16),

                            // Password Field
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter password';
                                }
                                if (value.length < 4) {
                                  return 'Password must be at least 4 characters';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 24),

                            // Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _updateCredentials,
                                    icon: const Icon(Icons.save),
                                    label: const Text('Update Credentials'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _resetToDefault,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Reset'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 16),
                                    backgroundColor: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Info Card
                  Card(
                    color: Colors.amber[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.amber[900]),
                              const SizedBox(width: 8),
                              const Text(
                                'Important Information',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '• Super Admin credentials are fixed and cannot be changed\n'
                            '• Bursar account can change their own credentials from settings\n'
                            '• Use this page to reset bursar credentials if they forget\n'
                            '• Both accounts have the same access level',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Current Bursar Info
                  if (_bursarAccount != null)
                    Card(
                      color: Colors.grey[100],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current Bursar Account Info',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Divider(),
                            _infoRow('User ID',
                                _bursarAccount!['id'].toString()),
                            _infoRow('Username',
                                _bursarAccount!['username'] ?? 'N/A'),
                            _infoRow('Can Change Credentials',
                                _bursarAccount!['canChangeCredentials'] == 1
                                    ? 'Yes'
                                    : 'No'),
                            _infoRow('Created At',
                                _bursarAccount!['createdAt'] ?? 'N/A'),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}