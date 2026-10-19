// lib/screens/auth/force_change_password_screen.dart
// Mandatory password change (ported from Digital School Manager): shown after
// login while the account is still on the old shared default password.
//
// The login is only remembered ([saveLogin]) once the new password is set, so
// closing the app here doesn't skip the change on the next start.

import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../home_screen.dart';
import 'create_super_admin_screen.dart';

class ForceChangePasswordScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  /// Persists the session (SharedPreferences) — called after a successful change.
  final Future<void> Function() saveLogin;

  const ForceChangePasswordScreen({super.key, required this.currentUser, required this.saveLogin});

  @override
  State<ForceChangePasswordScreen> createState() => _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState extends State<ForceChangePasswordScreen> {
  final _db = DatabaseHelperWrapper();
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = (widget.currentUser['id'] ?? widget.currentUser['userId']) as int?;
    if (userId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    bool success;
    try {
      success = await _db.changePassword(userId, _passwordController.text);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    if (!success) {
      setState(() {
        _saving = false;
        _error = 'Could not update your password. Please try again.';
      });
      return;
    }

    await widget.saveLogin();
    if (!mounted) return;
    final user = Map<String, dynamic>.from(widget.currentUser)..['mustChangePassword'] = false;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SidebarScaffold(
          currentUser: user,
          currentPageId: 'home',
          child: HomeScreen(currentUser: user),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.lock_reset, size: 48, color: Colors.indigo.shade700),
                        const SizedBox(height: 12),
                        const Text(
                          'Set a New Password',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You are using the default password. Please choose a new password before continuing.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: validateNewAdminPassword,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                            labelText: 'Confirm New Password',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _saving ? null : _submit,
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: _saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
