// lib/screens/auth/user_management_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/user.dart';

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
  final _db = DatabaseHelperWrapper();
  List<User> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);

    final data = await _db.getAllUsers();
    final users = data.map((m) => User.fromMap(m)).toList();

    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  bool _canDeleteUser(User user) {
    // NEVER delete developer users - they are system-level
    if (user.isDeveloper) return false;

    // Cannot delete default superadmin (id=1)
    if (user.id == 1) return false;

    // Cannot delete currently logged-in user
    if (user.id == widget.currentUser['id']) return false;

    // Cannot delete last super_admin
    if (user.isSuperAdmin) {
      final superAdminCount = _users.where((u) => u.isSuperAdmin).length;
      return superAdminCount > 1;
    }

    return true;
  }

  bool _canEditUser(User user) {
    // NEVER edit developer users - they are system-level and fixed
    if (user.isDeveloper) return false;

    // Cannot edit default superadmin (id=1) if not developer
    if (user.id == 1 && widget.currentUser['userType'] != 'developer') {
      return false;
    }

    return true;
  }

  Future<void> _deleteUser(User user) async {
    // Show confirmation dialog
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this user?'),
            const SizedBox(height: 12),
            Card(
              color: Colors.red[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Username: ${user.username}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Role: ${user.roleDisplayName}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone!',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Delete user
    final result = await _db.deleteUser(user.id!);

    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );

      if (result['success']) {
        _loadUsers(); // Refresh list
      }
    }
  }

  Future<void> _showAddUserDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _UserFormDialog(mode: 'add'),
    );

    if (result != null) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final userId = await _db.createUser(
        username: result['username'],
        password: result['password'],
        userType: result['userType'],
        canChangeCredentials: result['canChangeCredentials'],
      );

      if (mounted) {
        if (userId != null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('User created successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadUsers();
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                  'Failed to create user. Username may already exist or is reserved.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editUser(User user) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UserFormDialog(mode: 'edit', existingUser: user),
    );

    if (result != null) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final success = await _db.updateUser(
        userId: user.id!,
        username: result['username'],
        password: result['password'],
        userType: result['userType'],
        canChangeCredentials: result['canChangeCredentials'],
      );

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(success
                ? 'User updated successfully'
                : 'Failed to update user. Username may be taken by another user.'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );

        if (success) _loadUsers();
      }
    }
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only developer and super admin can access this
    final userType = widget.currentUser['userType'] as String;
    if (userType != 'developer' && userType != 'super_admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('Only Developer and Super Admin can access this page'),
        ),
      );
    }

    final developerCount = _users.where((u) => u.isDeveloper).length;
    final superAdminCount = _users.where((u) => u.isSuperAdmin).length;
    final adminCount = _users.where((u) => u.isAdmin).length;
    final bursarCount = _users.where((u) => u.isBursar).length;

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
                  // Summary Card
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.people_outline, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              const Text(
                                'User Summary',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _summaryItem('Total Users', _users.length.toString()),
                              _summaryItem('Developers', developerCount.toString(), Colors.purple),
                              _summaryItem('Super Admins', superAdminCount.toString()),
                              _summaryItem('Admins', adminCount.toString()),
                              _summaryItem('Bursars', bursarCount.toString()),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Users List Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'All Users',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _showAddUserDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Add User'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Users List
                  if (_users.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No users found',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return _buildUserCard(user);
                      },
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddUserDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _summaryItem(String label, String value, [Color? color]) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.blue,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildUserCard(User user) {
    final bool isFixed = user.isDeveloper || user.id == 1;
    final bool canDelete = _canDeleteUser(user);
    final bool canEdit = _canEditUser(user);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: user.isDeveloper
                  ? Colors.purple
                  : (user.isSuperAdmin ? Colors.blue : Colors.green),
              child: Icon(
                user.isDeveloper
                    ? Icons.code
                    : (user.isSuperAdmin
                        ? Icons.admin_panel_settings
                        : Icons.person),
                color: Colors.white,
              ),
            ),

            const SizedBox(width: 16),

            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user.username,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (user.id == widget.currentUser['id'])
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(fontSize: 10, color: Colors.purple),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: user.isDeveloper
                              ? Colors.purple[100]
                              : (user.isSuperAdmin
                                  ? Colors.blue[100]
                                  : Colors.green[100]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          user.roleDisplayName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: user.isDeveloper ? FontWeight.bold : FontWeight.normal,
                            color: user.isDeveloper
                                ? Colors.purple[900]
                                : (user.isSuperAdmin
                                    ? Colors.blue[900]
                                    : Colors.green[900]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (user.isDeveloper)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple[900],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.lock, size: 10, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'System',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isFixed ? Colors.orange[100] : Colors.teal[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isFixed ? 'Fixed' : 'Editable',
                            style: TextStyle(
                              fontSize: 11,
                              color: isFixed ? Colors.orange[900] : Colors.teal[900],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Created: ${_formatDate(user.createdAt)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),

            // Action Buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    color: canEdit ? Colors.blue : Colors.grey,
                  ),
                  onPressed: canEdit ? () => _editUser(user) : null,
                  tooltip: canEdit
                      ? 'Edit User'
                      : (user.isDeveloper
                          ? 'Developer accounts are system-level and cannot be edited'
                          : 'Cannot edit this user'),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete,
                    color: canDelete ? Colors.red : Colors.grey,
                  ),
                  onPressed: canDelete ? () => _deleteUser(user) : null,
                  tooltip: canDelete
                      ? 'Delete User'
                      : (user.isDeveloper
                          ? 'Developer accounts are system-level and cannot be deleted'
                          : 'Cannot delete this user'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// USER FORM DIALOG
// ============================================================================

class _UserFormDialog extends StatefulWidget {
  final String mode; // 'add' or 'edit'
  final User? existingUser;

  const _UserFormDialog({
    required this.mode,
    this.existingUser,
  });

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _selectedRole = 'bursar'; // default
  bool _canChangeCredentials = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();

    if (widget.mode == 'edit' && widget.existingUser != null) {
      _usernameController.text = widget.existingUser!.username;
      _passwordController.text = widget.existingUser!.password;
      _confirmPasswordController.text = widget.existingUser!.password;
      _selectedRole = widget.existingUser!.userType;
      _canChangeCredentials = widget.existingUser!.canChange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.mode == 'add' ? 'Add New User' : 'Edit User'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Username field
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter username';
                  }
                  if (value.trim().toLowerCase() == 'superadmin' &&
                      widget.existingUser?.id != 1) {
                    return 'Cannot use "superadmin" as username';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Password field
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
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

              const SizedBox(height: 16),

              // Confirm Password field
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(
                        () => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Role dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: InputDecoration(
                  labelText: 'Role',
                  prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'super_admin', child: Text('Super Admin')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'bursar', child: Text('Bursar')),
                ],
                onChanged: (value) {
                  setState(() => _selectedRole = value!);
                },
              ),

              const SizedBox(height: 16),

              // Can change credentials switch
              Card(
                color: Colors.grey[100],
                child: SwitchListTile(
                  title: const Text('Can Change Credentials'),
                  subtitle: Text(
                    _canChangeCredentials
                        ? 'User can change their own credentials'
                        : 'Only super admin can change this user\'s credentials',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: _canChangeCredentials,
                  onChanged: (value) {
                    setState(() => _canChangeCredentials = value);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'username': _usernameController.text.trim(),
                'password': _passwordController.text,
                'userType': _selectedRole,
                'canChangeCredentials': _canChangeCredentials ? 1 : 0,
              });
            }
          },
          child: Text(widget.mode == 'add' ? 'Add User' : 'Update User'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
