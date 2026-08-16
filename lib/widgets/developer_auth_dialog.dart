// lib/widgets/developer_auth_dialog.dart
import 'package:flutter/material.dart';
import '../utils/developer_auth_helper.dart';

class DeveloperAuthDialog extends StatefulWidget {
  const DeveloperAuthDialog({super.key});

  @override
  State<DeveloperAuthDialog> createState() => _DeveloperAuthDialogState();
}

class _DeveloperAuthDialogState extends State<DeveloperAuthDialog> {
  final _secretCodeController = TextEditingController();
  bool _obscureCode = true;
  bool _isVerifying = false;
  int _attempts = 0;
  static const int _maxAttempts = 3;

  @override
  void dispose() {
    _secretCodeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (_secretCodeController.text.trim().isEmpty) {
      _showError('Please enter the secret code');
      return;
    }

    setState(() => _isVerifying = true);

    // Add a small delay to prevent brute force
    await Future.delayed(const Duration(milliseconds: 500));

    final isValid = DeveloperAuthHelper.verifySecretCode(
      _secretCodeController.text.trim(),
    );

    setState(() => _isVerifying = false);

    if (isValid) {
      // Success - return true to caller
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      _attempts++;

      if (_attempts >= _maxAttempts) {
        // Too many attempts - close dialog
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Too many failed attempts. Access denied.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.of(context).pop(false);
        }
      } else {
        _showError(
          'Invalid secret code. ${_maxAttempts - _attempts} attempt(s) remaining.',
        );
        _secretCodeController.clear();
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          const Text('Developer Access'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the developer secret code to access the license generator.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _secretCodeController,
            obscureText: _obscureCode,
            decoration: InputDecoration(
              labelText: 'Secret Code',
              hintText: 'Enter secret code',
              prefixIcon: const Icon(Icons.vpn_key),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCode ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() => _obscureCode = !_obscureCode);
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            enabled: !_isVerifying,
            onSubmitted: (_) => _verifyCode(),
          ),
          const SizedBox(height: 12),
          Text(
            'Attempts: $_attempts/$_maxAttempts',
            style: TextStyle(
              fontSize: 12,
              color: _attempts >= 2 ? Colors.red : Colors.grey,
              fontWeight: _attempts >= 2 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isVerifying ? null : () {
            Navigator.of(context).pop(false);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isVerifying ? null : _verifyCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
          ),
          child: _isVerifying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Verify'),
        ),
      ],
    );
  }
}

/// Show developer authentication dialog
/// Returns true if authentication was successful, false otherwise
Future<bool> showDeveloperAuthDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const DeveloperAuthDialog(),
  );
  return result ?? false;
}
