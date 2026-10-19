// lib/screens/auth/forgot_password_screen.dart
// "Forgot password?" from the login page on the main device
// (ported from Digital School Manager).
//
// Everyone except super admins asks a super admin to reset their password
// (User Management). A super admin who forgot theirs proves ownership of the
// school with its license key (the most recently activated one, even if
// expired), picks their account and sets a new password — so nobody can be
// permanently locked out, and no built-in "master" account is needed.

import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import 'create_super_admin_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _db = DatabaseHelperWrapper();
  final _keyController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _resetFormKey = GlobalKey<FormState>();

  /// Number of wrong license keys entered on this screen; after a few the
  /// form pauses briefly so keys can't be guessed by rapid retrying.
  int _failedAttempts = 0;
  DateTime? _pausedUntil;

  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _verifiedKey;
  List<Map<String, dynamic>> _accounts = [];
  int? _selectedUserId;

  @override
  void dispose() {
    _keyController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _verifyKey() async {
    final paused = _pausedUntil;
    if (paused != null && DateTime.now().isBefore(paused)) {
      setState(() => _error = 'Too many attempts. Please wait a minute and try again.');
      return;
    }
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter the school\'s license key');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await _db.verifyRecoveryLicenseKey(key);
    if (!mounted) return;
    if (!ok) {
      _failedAttempts++;
      if (_failedAttempts >= 5) {
        _pausedUntil = DateTime.now().add(const Duration(minutes: 1));
        _failedAttempts = 0;
      }
      setState(() {
        _busy = false;
        _error = 'That license key does not match this school\'s license.';
      });
      return;
    }

    final accounts = await _db.getSuperAdminAccounts();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _verifiedKey = key;
      _accounts = accounts;
      _selectedUserId = accounts.length == 1 ? accounts.first['id'] as int : null;
    });
  }

  Future<void> _reset() async {
    if (!_resetFormKey.currentState!.validate()) return;
    final userId = _selectedUserId;
    final key = _verifiedKey;
    if (userId == null || key == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await _db.resetSuperAdminPasswordWithLicense(
      licenseKey: key,
      userId: userId,
      newPassword: _passwordController.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Could not reset the password. Please try again.';
      });
      return;
    }
    final username = _accounts.firstWhere((a) => a['id'] == userId)['username'];
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Password reset for "$username". You can now log in.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: Colors.blue.shade50,
                  child: const ListTile(
                    leading: Icon(Icons.info_outline, color: Colors.blue),
                    title: Text('Admins, bursars and other staff'),
                    subtitle: Text('Please ask your school\'s super admin to reset your password.'),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _verifiedKey == null ? _buildKeyStep() : _buildResetStep(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.vpn_key_outlined, size: 44, color: Colors.indigo.shade700),
        const SizedBox(height: 12),
        const Text(
          'Super Admin Recovery',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the license key this school activated the app with.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _keyController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'License Key',
            prefixIcon: Icon(Icons.key),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _verifyKey(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy ? null : _verifyKey,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verify License Key'),
        ),
      ],
    );
  }

  Widget _buildResetStep() {
    if (_accounts.isEmpty) {
      return const Text(
        'No super admin account exists. Close this screen — the app will ask you to create one.',
        textAlign: TextAlign.center,
      );
    }
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Text('License key verified', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            initialValue: _selectedUserId,
            decoration: const InputDecoration(
              labelText: 'Super Admin Account',
              prefixIcon: Icon(Icons.admin_panel_settings_outlined),
              border: OutlineInputBorder(),
            ),
            items: [
              for (final a in _accounts)
                DropdownMenuItem<int>(value: a['id'] as int, child: Text(a['username'] as String)),
            ],
            onChanged: (v) => setState(() => _selectedUserId = v),
            validator: (v) => v == null ? 'Choose the account to reset' : null,
          ),
          const SizedBox(height: 16),
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
            onFieldSubmitted: (_) => _reset(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _reset,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Reset Password'),
          ),
        ],
      ),
    );
  }
}
