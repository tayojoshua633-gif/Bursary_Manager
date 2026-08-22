// lib/screens/license/license_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/license_helper.dart';
import '../../utils/license_checker.dart';
import '../../utils/license_tier_helper.dart';
import 'license_activation_screen.dart';

class LicenseManagementScreen extends StatefulWidget {
  const LicenseManagementScreen({super.key});

  @override
  State<LicenseManagementScreen> createState() =>
      _LicenseManagementScreenState();
}

class _LicenseManagementScreenState extends State<LicenseManagementScreen> {
  final _db = DatabaseHelperWrapper();
  Map<String, dynamic>? _activeLicense;
  List<Map<String, dynamic>> _allLicenses = [];
  bool _isLoading = true;
  String? _deviceId;
  LicenseStatus? _licenseStatus;
  LicenseTier? _currentTier;
  int _activeStudentCount = 0;
  int? _licenseMaxStudents;
  bool _isMasterKey = false;

  @override
  void initState() {
    super.initState();
    _loadLicenseData();
  }

  Future<void> _loadLicenseData() async {
    setState(() => _isLoading = true);

    try {
      final activeLicense = await _db.getActiveLicense();
      final allLicenses = await _db.getAllLicenses();
      final deviceId = await LicenseHelper.getDeviceId();
      final status = await LicenseChecker.checkLicense();
      final activeStudents = await _db.getActiveStudents();

      // Re-decode the stored key just to read the isMasterKey flag — that
      // flag isn't persisted on the licenses table itself.
      final decoded = activeLicense != null
          ? LicenseHelper.validateLicenseKey(
              activeLicense['licenseKey'] as String,
            )
          : null;
      final isMasterKey = decoded?['isMasterKey'] == true;

      final maxStudents = status.maxStudents;
      final licenseMaxStudents =
          (maxStudents != null && maxStudents > 0) ? maxStudents : null;

      setState(() {
        _activeLicense = activeLicense;
        _allLicenses = allLicenses;
        _deviceId = deviceId;
        _licenseStatus = status;
        _activeStudentCount = activeStudents.length;
        _licenseMaxStudents = licenseMaxStudents;
        _isMasterKey = isMasterKey;
        // Current tier reflects what was actually purchased (the license's
        // maxStudents cap), not the fluctuating active student count. A
        // master key isn't a real pricing tier, so it's shown separately.
        _currentTier = (!isMasterKey && licenseMaxStudents != null)
            ? tierForStudentCount(licenseMaxStudents)
            : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading license: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deactivateLicense(int licenseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate License'),
        content: const Text(
          'Are you sure you want to deactivate this license?\n\n'
          'This will:\n'
          '• Log you out of the app\n'
          '• Require license reactivation\n'
          '• Clear all user sessions',
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
            child: const Text('Deactivate & Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Deactivate the license
      await _db.deactivateLicense(licenseId);

      // Clear user session
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isLoggedIn');
      await prefs.remove('username');
      await prefs.remove('userType');
      await prefs.remove('userId');
      await prefs.remove('email');
      await prefs.remove('schoolId');

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('License deactivated. Redirecting to activation screen...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Wait a moment for the message to show
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          // Navigate to License Activation Screen and remove all previous routes
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const LicenseActivationScreen(canSkip: false),
            ),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deactivating license: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('License Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLicenseData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLicenseData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Device Info Card
                  if (_deviceId != null)
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.devices, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                const Text(
                                  'This Device',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text(
                                  'Device ID: ',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                                Expanded(
                                  child: Text(
                                    '${_deviceId!.substring(0, 16)}...',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: _deviceId!),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Device ID copied to clipboard'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  tooltip: 'Copy Device ID',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Active License Status
                  if (_licenseStatus != null)
                    Card(
                      color: _licenseStatus!.isValid
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _licenseStatus!.isValid
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: _licenseStatus!.isValid
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _licenseStatus!.isValid
                                      ? 'License Active'
                                      : 'License Issue',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(_licenseStatus!.message),
                            if (_licenseStatus!.isValid &&
                                _licenseStatus!.daysRemaining != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Expires in ${_licenseStatus!.daysRemaining} days',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _licenseStatus!.isExpiryApproaching
                                      ? Colors.orange.shade700
                                      : Colors.green.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Current Tier — reflects what's actually licensed (the
                  // license's maxStudents cap), not the fluctuating active
                  // student count. Licenses activated before the tier scheme
                  // existed, or master keys, don't map to a pricing tier.
                  if (_isMasterKey)
                    Card(
                      color: Colors.purple.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.sell, color: Colors.purple.shade700),
                                const SizedBox(width: 8),
                                const Text(
                                  'Current Tier',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '🔑 Master (${_licenseMaxStudents ?? 999999} students)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Master license key — not a purchased pricing tier',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_currentTier != null)
                    Card(
                      color: Colors.purple.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.sell, color: Colors.purple.shade700),
                                const SizedBox(width: 8),
                                const Text(
                                  'Current Tier',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${_currentTier!.emoji} ${_currentTier!.name} '
                              '(${_currentTier!.rangeLabel} students)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Licensed for up to $_licenseMaxStudents students '
                              '($_activeStudentCount active now)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            const Divider(height: 24),
                            _buildDetailRow(
                              'License Fee',
                              _formatNaira(_currentTier!.licensePrice),
                            ),
                            _buildDetailRow(
                              'Termly Support',
                              _formatNaira(_currentTier!.termlySupport),
                            ),
                            _buildDetailRow(
                              'Annual Support',
                              _formatNaira(_currentTier!.annualSupport),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Active License Details
                  if (_activeLicense != null) ...[
                    const Text(
                      'Active License Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(
                              'School',
                              _activeLicense!['schoolName'],
                            ),
                            _buildDetailRow(
                              'School Code',
                              _activeLicense!['schoolCode'],
                            ),
                            _buildDetailRow(
                              'License Key',
                              _formatLicenseKey(
                                _activeLicense!['licenseKey'].toString(),
                              ),
                            ),
                            _buildDetailRow(
                              'Activation Date',
                              _formatDate(DateTime.parse(
                                _activeLicense!['activationDate'],
                              )),
                            ),
                            _buildDetailRow(
                              'Expiry Date',
                              _formatDate(DateTime.parse(
                                _activeLicense!['expiryDate'],
                              )),
                            ),
                            if (_activeLicense!['maxStudents'] != null &&
                                _activeLicense!['maxStudents'] > 0)
                              _buildDetailRow(
                                'Max Students',
                                '${_activeLicense!['maxStudents']}',
                              ),
                            const Divider(height: 24),
                            ElevatedButton.icon(
                              onPressed: () => _deactivateLicense(
                                _activeLicense!['id'] as int,
                              ),
                              icon: const Icon(Icons.cancel),
                              label: const Text('Deactivate License'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                minimumSize: const Size(double.infinity, 48),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.warning,
                            size: 64,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No Active License',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Activate a license to use the app',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Activate New License Button
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LicenseActivationScreen(
                            canSkip: true,
                          ),
                        ),
                      );
                      _loadLicenseData();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Activate New License'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // License History
                  if (_allLicenses.length > 1) ...[
                    const Text(
                      'License History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._allLicenses.map((license) {
                      final isActive = license['isActive'] == 1;
                      final expiryDate = DateTime.parse(license['expiryDate']);
                      final isExpired = DateTime.now().isAfter(expiryDate);

                      return Card(
                        color: isActive
                            ? Colors.green.shade50
                            : Colors.grey.shade100,
                        child: ListTile(
                          leading: Icon(
                            isActive ? Icons.check_circle : Icons.history,
                            color: isActive
                                ? Colors.green.shade700
                                : Colors.grey.shade600,
                          ),
                          title: Text(
                            license['schoolName'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Code: ${license['schoolCode']}'),
                              Text(
                                isExpired
                                    ? 'Expired: ${_formatDate(expiryDate)}'
                                    : 'Expires: ${_formatDate(expiryDate)}',
                              ),
                            ],
                          ),
                          trailing: Chip(
                            label: Text(
                              isActive
                                  ? 'ACTIVE'
                                  : isExpired
                                      ? 'EXPIRED'
                                      : 'INACTIVE',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: isActive
                                ? Colors.green.shade700
                                : isExpired
                                    ? Colors.red.shade700
                                    : Colors.grey.shade600,
                            labelStyle: const TextStyle(color: Colors.white),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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

  String _formatNaira(int amount) => '₦${NumberFormat("#,##0").format(amount)}';

  String _formatLicenseKey(String key) {
    if (key.length > 20) {
      return '${key.substring(0, 20)}...';
    }
    return key;
  }
}
