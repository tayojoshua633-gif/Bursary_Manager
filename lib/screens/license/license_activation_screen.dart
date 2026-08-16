// lib/screens/license/license_activation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/license_helper.dart';
import '../../widgets/developer_auth_dialog.dart';
import '../auth/mode_selection_screen.dart';
import '../auth/welcome_screen.dart';
import 'license_generator_screen.dart';

class LicenseActivationScreen extends StatefulWidget {
  final bool canSkip;

  const LicenseActivationScreen({
    super.key,
    this.canSkip = false,
  });

  @override
  State<LicenseActivationScreen> createState() =>
      _LicenseActivationScreenState();
}

class _LicenseActivationScreenState extends State<LicenseActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _licenseKeyController = TextEditingController();
  final _db = DatabaseHelperWrapper();

  bool _isActivating = false;
  String? _deviceId;
  Map<String, dynamic>? _licenseData;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
  }

  @override
  void dispose() {
    _licenseKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceId() async {
    final deviceId = await LicenseHelper.getDeviceId();
    setState(() => _deviceId = deviceId);
  }

  Future<void> _validateLicenseKey() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isActivating = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final licenseKey = _licenseKeyController.text.trim();

      // Validate license key format
      final licenseData = LicenseHelper.validateLicenseKey(licenseKey);

      if (licenseData == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Invalid license key format'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isActivating = false);
        return;
      }

      // Check if expired
      if (licenseData['isExpired'] == true) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('This license key has expired'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isActivating = false);
        return;
      }

      // Skip device binding checks for master license key
      final isMasterKey = licenseData['isMasterKey'] == true;

      if (!isMasterKey) {
        // Check if already activated (only for regular licenses, not master key)
        final exists = await _db.licenseKeyExists(licenseKey);
        if (exists) {
          // Check if it's the same device trying to reactivate
          final existingLicense = await _db.getLicenseByKey(licenseKey);

          if (existingLicense != null &&
              existingLicense['deviceId'] == _deviceId &&
              existingLicense['isActive'] == 0) {
            // Same device, license was deactivated - allow reactivation
            messenger.showSnackBar(
              const SnackBar(
                content: Text('License reactivated! Please select app mode.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );

            // Reactivate the license
            await _db.reactivateLicense(existingLicense['id'] as int);

            messenger.showSnackBar(
              const SnackBar(
                content: Text('License reactivated successfully!'),
                backgroundColor: Colors.green,
              ),
            );

            // Set default app mode to standalone
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('app_mode', 'standalone');

            // Navigate to login screen
            await Future.delayed(const Duration(seconds: 1));

            if (mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            }
            return;
          } else {
            // Different device or already active
            messenger.showSnackBar(
              const SnackBar(
                content: Text('This license key has already been activated on another device'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
            setState(() => _isActivating = false);
            return;
          }
        }

        // Check if license is bound to a specific device
        if (licenseData.containsKey('deviceId') && licenseData['deviceId'] != null) {
          final boundDeviceId = licenseData['deviceId'] as String;

          // Verify this device matches the bound device
          if (_deviceId != null && boundDeviceId != _deviceId) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('This license is bound to a different device and cannot be activated here'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
            setState(() => _isActivating = false);
            return;
          }
        }
      }

      // Show license details and confirm
      setState(() {
        _licenseData = licenseData;
        _isActivating = false;
      });
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isActivating = false);
    }
  }

  Future<void> _activateLicense() async {
    if (_licenseData == null || _deviceId == null) return;

    setState(() => _isActivating = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final expiryDate = DateTime.parse(_licenseData!['expiry'] as String);

      await _db.activateLicense(
        licenseKey: _licenseKeyController.text.trim(),
        schoolName: _licenseData!['school'] as String,
        schoolCode: _licenseData!['code'] as String,
        deviceId: _deviceId!,
        expiryDate: expiryDate,
        maxStudents: _licenseData!['maxStudents'] as int?,
      );

      if (!mounted) return;

      messenger.showSnackBar(
        const SnackBar(
          content: Text('License activated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Set default app mode to standalone
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_mode', 'standalone');

      // Navigate to login screen
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Activation failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isActivating = false);
    }
  }

  Future<void> _openDeveloperMode() async {
    // Show authentication dialog
    final authenticated = await showDeveloperAuthDialog(context);

    if (authenticated && mounted) {
      // Navigate to license generator screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LicenseGeneratorScreen(),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activate License'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const ModeSelectionScreen(),
              ),
            );
          },
        ),
        actions: widget.canSkip
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Icon
            Icon(
              Icons.verified_user,
              size: 80,
              color: Colors.blue.shade700,
            ),

            const SizedBox(height: 16),

            // Title
            const Text(
              'Activate Bursary Manager',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            const Text(
              'Enter your license key to activate the app',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Device ID Display
            if (_deviceId != null)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.fingerprint, size: 18, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'This Device ID',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'Copy Device ID',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _deviceId!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Device ID copied to clipboard!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: SelectableText(
                          _deviceId!,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade800,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 12, color: Colors.blue.shade600),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'Share this ID with the license provider if needed',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // License Input Form
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _licenseKeyController,
                    decoration: InputDecoration(
                      labelText: 'License Key',
                      hintText: 'XXXXX-XXXXX-XXXXX-XXXXX',
                      prefixIcon: const Icon(Icons.vpn_key),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste),
                        tooltip: 'Paste',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _licenseKeyController.text = data!.text!;
                          }
                        },
                      ),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter license key';
                      }
                      return null;
                    },
                    onChanged: (_) {
                      // Clear license data when user edits
                      if (_licenseData != null) {
                        setState(() => _licenseData = null);
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Validate Button
                  if (_licenseData == null)
                    ElevatedButton.icon(
                      onPressed: _isActivating ? null : _validateLicenseKey,
                      icon: _isActivating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: const Text('Validate License'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                ],
              ),
            ),

            // License Details (after validation)
            if (_licenseData != null) ...[
              const SizedBox(height: 24),

              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Valid License',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const Divider(height: 24),

                      _buildDetailRow('School', _licenseData!['school']),
                      _buildDetailRow('School Code', _licenseData!['code']),
                      _buildDetailRow(
                        'Expiry Date',
                        _formatDate(DateTime.parse(_licenseData!['expiry'])),
                      ),
                      _buildDetailRow(
                        'Days Remaining',
                        '${_licenseData!['daysRemaining']} days',
                      ),
                      if (_licenseData!['maxStudents'] != null &&
                          _licenseData!['maxStudents'] > 0)
                        _buildDetailRow(
                          'Max Students',
                          '${_licenseData!['maxStudents']}',
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Activate Button
              ElevatedButton.icon(
                onPressed: _isActivating ? null : _activateLicense,
                icon: _isActivating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.verified_user),
                label: const Text('Activate License'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),

              TextButton(
                onPressed: () {
                  setState(() {
                    _licenseData = null;
                    _licenseKeyController.clear();
                  });
                },
                child: const Text('Enter Different Key'),
              ),
            ],

            const SizedBox(height: 32),

            // Help Text
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.help_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Text(
                          'Need Help?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '• Contact support to get your license key\n'
                      '• The license is bound to this device only\n'
                      '• Ensure you have a valid expiry date\n'
                      '• Keep your license key safe and secure',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Developer Access Button (hidden, tap 5 times to reveal)
            Center(
              child: TextButton.icon(
                onPressed: _openDeveloperMode,
                icon: Icon(Icons.code, size: 16, color: Colors.grey.shade600),
                label: Text(
                  'Developer Access',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
