// lib/screens/license/license_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../utils/license_helper.dart';
import 'license_activation_screen.dart';

class LicenseManagementScreen extends StatefulWidget {
  const LicenseManagementScreen({super.key});

  @override
  State<LicenseManagementScreen> createState() => _LicenseManagementScreenState();
}

class _LicenseManagementScreenState extends State<LicenseManagementScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _licenseStatus;
  Map<String, dynamic>? _licenseInfo;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    _loadLicenseInfo();
  }

  Future<void> _loadLicenseInfo() async {
    setState(() => _isLoading = true);

    _licenseStatus = await LicenseHelper.checkLicenseStatus();
    _licenseInfo = await LicenseHelper.getLicenseInfo();
    _deviceId = await LicenseHelper.getDeviceId();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deactivateLicense() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate License?'),
        content: const Text(
          'Are you sure you want to deactivate the current license? '
          'You will need to re-activate to use the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await LicenseHelper.deactivateLicense();

    if (!mounted) return;

    // Navigate to activation screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LicenseActivationScreen(),
      ),
      (route) => false,
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _contactSupport() {
    final contact = LicenseHelper.getContactInfo();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.contact_support, color: Colors.blue),
            SizedBox(width: 8),
            Text('Contact Support'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'For license support, contact:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildContactRow(Icons.business, 'Company', contact['company']!),
            _buildContactRow(Icons.email, 'Email', contact['email']!),
            _buildContactRow(Icons.phone, 'Phone', contact['phone']!),
            _buildContactRow(Icons.language, 'Website', contact['website']!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String label, String value) {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('License Management'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLicenseInfo,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLicenseInfo,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // License Status Card
                    _buildLicenseStatusCard(),

                    const SizedBox(height: 16),

                    // License Details Card
                    _buildLicenseDetailsCard(),

                    const SizedBox(height: 16),

                    // Device Information Card
                    _buildDeviceInfoCard(),

                    const SizedBox(height: 24),

                    // Actions
                    const Text(
                      'Actions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Contact Support Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _contactSupport,
                        icon: const Icon(Icons.support_agent),
                        label: const Text('Contact Support'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Deactivate License Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _deactivateLicense,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Deactivate License'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLicenseStatusCard() {
    final isValid = _licenseStatus?['valid'] == true;
    final status = _licenseStatus?['status'] as LicenseStatus?;
    final isTrial = _licenseStatus?['isTrial'] == true;
    final isLifetime = _licenseStatus?['isLifetime'] == true;
    final daysRemaining = _licenseStatus?['daysRemaining'] as int?;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isValid) {
      if (isTrial) {
        statusColor = Colors.blue;
        statusIcon = Icons.timer;
        statusText = 'Trial Active';
      } else if (isLifetime) {
        statusColor = Colors.green;
        statusIcon = Icons.verified;
        statusText = 'Lifetime License';
      } else if (daysRemaining != null && daysRemaining <= 7) {
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        statusText = 'Expiring Soon';
      } else {
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Active';
      }
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.error;
      statusText = status == LicenseStatus.expired ? 'Expired' : 'Inactive';
    }

    return Card(
      elevation: 3,
      color: statusColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    statusIcon,
                    color: statusColor,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _licenseStatus?['message'] ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (daysRemaining != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.access_time,
                    size: 20,
                    color: statusColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$daysRemaining days remaining',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseDetailsCard() {
    final licenseKey = _licenseInfo?['licenseKey'];
    final activationDate = _licenseInfo?['activationDate'];
    final expiryDate = _licenseInfo?['expiryDate'];
    final schoolName = _licenseInfo?['schoolName'];
    final licenseTypeStr = _licenseInfo?['licenseType'];
    
    LicenseType? licenseType;
    if (licenseTypeStr != null) {
      try {
        licenseType = LicenseType.values.firstWhere(
          (e) => e.toString() == licenseTypeStr,
        );
      } catch (_) {}
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  'License Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (schoolName != null) ...[
              _buildInfoRow('School', schoolName),
              const Divider(),
            ],

            if (licenseType != null) ...[
              _buildInfoRow(
                'License Type',
                LicenseHelper.formatLicenseType(licenseType),
              ),
              const Divider(),
            ],

            if (activationDate != null) ...[
              _buildInfoRow(
                'Activated On',
                DateFormat('dd MMM yyyy').format(DateTime.parse(activationDate)),
              ),
              const Divider(),
            ],

            if (expiryDate != null) ...[
              _buildInfoRow(
                'Expires On',
                DateFormat('dd MMM yyyy').format(DateTime.parse(expiryDate)),
              ),
              const Divider(),
            ],

            if (licenseKey != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'License Key',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          licenseKey,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () => _copyToClipboard(licenseKey, 'License key'),
                    tooltip: 'Copy',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.devices, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  'Device Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Device ID',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _deviceId.substring(0, 32),
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copyToClipboard(_deviceId, 'Device ID'),
                  tooltip: 'Copy',
                ),
              ],
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your license is bound to this device. Provide this Device ID when purchasing or transferring a license.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}