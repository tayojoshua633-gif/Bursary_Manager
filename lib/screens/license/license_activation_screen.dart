// lib/screens/license/license_activation_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/license_helper.dart';
import '../../utils/license_checker.dart';
import '../../db/database_helper.dart';

class LicenseActivationScreen extends StatefulWidget {
  const LicenseActivationScreen({super.key});

  @override
  State<LicenseActivationScreen> createState() => _LicenseActivationScreenState();
}

class _LicenseActivationScreenState extends State<LicenseActivationScreen> {
  final _licenseKeyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper();
  
  bool _isLoading = false;
  bool _showTrialInfo = false;
  String _deviceId = '';
  String? _schoolName;
  Map<String, dynamic>? _licenseStatus;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _licenseKeyController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Get device ID
    _deviceId = await LicenseHelper.getDeviceId();
    
    // Get school name from database
    final schoolProfile = await _db.getSchoolProfile();
    _schoolName = schoolProfile?['name'] ?? 'School';
    
    // Check current license status
    _licenseStatus = await LicenseHelper.checkLicenseStatus();
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _activateLicense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_schoolName == null) {
      _showError('School name not set. Please set up school profile first.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await LicenseHelper.activateLicense(
        licenseKey: _licenseKeyController.text.trim(),
        schoolName: _schoolName!,
      );

      if (!mounted) return;

      // Check if activation was successful
      if (result['success'] == true) {
        _showSuccess(result['message'] ?? 'License activated successfully!');
        
        // Wait a bit then navigate to app
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          _navigateToApp();
        }
      } else {
        _showError(result['message'] ?? 'Activation failed');
      }
    } catch (e) {
      if (mounted) {
        _showError('Activation error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startTrial() async {
    if (_schoolName == null || _schoolName!.isEmpty) {
      _showError('School name not set. Please set up school profile first.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await LicenseHelper.startTrial(_schoolName!);

      if (!mounted) return;

      // Safely check the result
      bool success = false;
      bool isAlreadyActive = false;
      String message = 'Unknown error occurred';

      success = result['success'] == true;
      // Check if trial was already active
      isAlreadyActive = result['valid'] == true && result['isTrial'] == true;
      message = result['message'] ?? 'Trial operation completed';
    
      // If trial is active (new or existing), proceed to app
      if (success || isAlreadyActive) {
        if (success) {
          _showSuccess('Trial started! You have 30 days to evaluate the app.');
        } else {
          _showSuccess('Trial is already active. Proceeding to app...');
        }
        
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          _navigateToApp();
        }
      } else {
        _showError(message);
      }
    } catch (e) {
      if (mounted) {
        _showError('Trial start error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToApp() {
    if (!mounted) return;
    
    // Use the LicenseChecker helper to navigate properly
    LicenseChecker.navigateToApp(context);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _contactSupport() async {
    final contact = LicenseHelper.getContactInfo();
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.contact_support, color: Colors.blue),
            SizedBox(width: 8),
            Text('Purchase License'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Contact us to purchase a license:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildContactItem(Icons.business, 'Company', contact['company']!),
              _buildContactItem(Icons.email, 'Email', contact['email']!),
              _buildContactItem(Icons.phone, 'Phone', contact['phone']!),
              _buildContactItem(Icons.language, 'Website', contact['website']!),
              const SizedBox(height: 16),
              const Text(
                'Your Device ID (needed for activation):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _deviceId.length >= 16 ? _deviceId.substring(0, 16) : _deviceId,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _deviceId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Device ID copied'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              launchUrl(Uri.parse('mailto:${contact['email']}'));
            },
            icon: const Icon(Icons.email),
            label: const Text('Send Email'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasExpiredTrial = _licenseStatus != null &&
        _licenseStatus!['status'] == LicenseStatus.expired &&
        _licenseStatus!['isTrial'] == true;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.orange.shade700,
              Colors.orange.shade500,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Lock Icon
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 80,
                      color: Colors.orange,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  const Text(
                    'Activate Bursary Manager',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  if (_schoolName != null)
                    Text(
                      _schoolName!,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),

                  const SizedBox(height: 48),

                  // Activation Form Card
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Enter License Key',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 24),

                            // License Key Field
                            TextFormField(
                              controller: _licenseKeyController,
                              decoration: InputDecoration(
                                labelText: 'License Key',
                                hintText: 'XXXXX-XXX-XXXXX-XXXXXXXX-XXXXX',
                                prefixIcon: const Icon(Icons.vpn_key),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter license key';
                                }
                                return null;
                              },
                              textCapitalization: TextCapitalization.characters,
                            ),

                            const SizedBox(height: 24),

                            // Activate Button
                            ElevatedButton.icon(
                              onPressed: _isLoading ? null : _activateLicense,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle),
                              label: Text(
                                _isLoading ? 'Activating...' : 'Activate License',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Contact Support Button
                            OutlinedButton.icon(
                              onPressed: _contactSupport,
                              icon: const Icon(Icons.shopping_cart),
                              label: const Text('Purchase License'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Trial Option
                  if (!hasExpiredTrial)
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () => setState(() => _showTrialInfo = !_showTrialInfo),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.timer, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text(
                                        'Start 30-Day Free Trial',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Icon(
                                    _showTrialInfo
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                  ),
                                ],
                              ),
                              if (_showTrialInfo) ...[
                                const SizedBox(height: 12),
                                const Divider(),
                                const SizedBox(height: 12),
                                const Text(
                                  '• Full access to all features\n'
                                  '• 30 days evaluation period\n'
                                  '• No credit card required\n'
                                  '• Purchase anytime during trial',
                                  style: TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _isLoading ? null : _startTrial,
                                  icon: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.play_arrow),
                                  label: Text(_isLoading ? 'Starting...' : 'Start Trial Now'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(double.infinity, 45),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (hasExpiredTrial)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info, color: Colors.red),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your trial period has expired. Please purchase a license to continue.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Device Info (for support)
                  if (_deviceId.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Device ID: ${_deviceId.length >= 16 ? _deviceId.substring(0, 16) : _deviceId}...',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.8),
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '(Provide this when purchasing)',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}