// lib/screens/auth/create_super_admin_screen.dart
// First-run setup (ported from Digital School Manager): shown on the main device
// when no super admin exists yet
// (fresh install, right after license activation). There are no built-in
// accounts — the school creates its own super admin here, who then creates
// every other user from User Management. A forgotten super admin password is
// recovered later with the license key ("Forgot password?" on the login page).

import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import 'welcome_screen.dart';

/// Shared password rule for the setup and recovery screens.
String? validateNewAdminPassword(String? value) {
  if (value == null || value.length < 6) return 'Password must be at least 6 characters';
  if (value == '12345' || value == '123456') return 'Please choose a stronger password';
  return null;
}

class CreateSuperAdminScreen extends StatefulWidget {
  const CreateSuperAdminScreen({super.key});

  @override
  State<CreateSuperAdminScreen> createState() => _CreateSuperAdminScreenState();
}

class _CreateSuperAdminScreenState extends State<CreateSuperAdminScreen> {
  final _db = DatabaseHelperWrapper();
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final id = await _db.createInitialSuperAdmin(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;

    if (id == null) {
      // Someone already created one (e.g. another window) — go to login.
      if (!await _db.needsInitialSuperAdmin()) {
        if (!mounted) return;
        _goToLogin('A super admin account already exists. Please log in.');
        return;
      }
      setState(() {
        _saving = false;
        _error = 'Could not create the account. Please try a different username.';
      });
      return;
    }
    _goToLogin('Super admin account created. You can now log in.');
  }

  void _goToLogin(String message) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
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
              constraints: const BoxConstraints(maxWidth: 440),
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
                        Icon(Icons.admin_panel_settings, size: 52, color: Colors.indigo.shade700),
                        const SizedBox(height: 12),
                        const Text(
                          'Create Super Admin',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Set up the main administrator account for this school. '
                          'This account manages all other users.\n\n'
                          'If this password is ever forgotten, it can be reset on this '
                          'device with the school\'s license key — keep the license key safe.',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.length < 3) return 'Username must be at least 3 characters';
                            if (t.contains(' ')) return 'Username cannot contain spaces';
                            // Reserved, and the first names anyone would guess.
                            if (const {'superadmin', 'developer'}.contains(t.toLowerCase())) {
                              return 'Please choose a different username';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Password',
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
                            labelText: 'Confirm Password',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
                          onFieldSubmitted: (_) => _create(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _saving ? null : _create,
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: _saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
