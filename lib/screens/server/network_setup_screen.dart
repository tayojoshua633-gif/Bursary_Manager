// lib/screens/server/network_setup_screen.dart
// Network setup screen for server mode - WiFi connection or hotspot creation

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkSetupScreen extends StatefulWidget {
  const NetworkSetupScreen({super.key});

  @override
  State<NetworkSetupScreen> createState() => _NetworkSetupScreenState();
}

class _NetworkSetupScreenState extends State<NetworkSetupScreen> {
  final NetworkInfo _networkInfo = NetworkInfo();

  bool _isLoading = false;
  bool _isHotspotEnabled = false;
  String? _currentSSID;
  String? _currentIP;
  String? _hotspotSSID;
  String? _hotspotPassword;
  List<WifiNetwork> _availableNetworks = [];

  NetworkMode _selectedMode = NetworkMode.none;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _checkCurrentNetwork();
  }

  Future<void> _checkCurrentNetwork() async {
    setState(() => _isLoading = true);

    try {
      // Check WiFi connection status
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        // Get current WiFi SSID
        try {
          _currentSSID = await _networkInfo.getWifiName();
          _currentIP = await _networkInfo.getWifiIP();
        } catch (e) {
          debugPrint('Error getting WiFi info: $e');
        }
      }

      // Check if hotspot is enabled
      try {
        _isHotspotEnabled = await WiFiForIoTPlugin.isWiFiAPEnabled() ?? false;
      } catch (e) {
        debugPrint('Error checking hotspot status: $e');
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to check network status: $e';
      });
    }
  }

  Future<void> _scanWiFiNetworks() async {
    // Request location permission (required for WiFi scanning on Android)
    final locationStatus = await Permission.location.request();

    if (!locationStatus.isGranted) {
      setState(() {
        _errorMessage = 'Location permission is required to scan WiFi networks';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedMode = NetworkMode.wifi;
    });

    try {
      // Scan for WiFi networks
      final networks = await WiFiForIoTPlugin.loadWifiList();

      setState(() {
        _availableNetworks = networks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to scan WiFi networks: $e';
      });
    }
  }

  Future<void> _connectToWiFi(WifiNetwork network) async {
    if (network.ssid == null) return;

    // Show password dialog
    final password = await _showPasswordDialog(network.ssid!);

    if (password == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final success = await WiFiForIoTPlugin.connect(
        network.ssid!,
        password: password,
        security: NetworkSecurity.WPA,
      );

      if (success) {
        // Wait for connection to establish
        await Future.delayed(const Duration(seconds: 2));

        // Get new IP
        _currentIP = await _networkInfo.getWifiIP();
        _currentSSID = network.ssid;

        setState(() {
          _isLoading = false;
          _successMessage = 'Connected to ${network.ssid}';
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to connect to ${network.ssid}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Connection failed: $e';
      });
    }
  }

  Future<String?> _showPasswordDialog(String ssid) async {
    final controller = TextEditingController();
    bool obscurePassword = true;

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Connect to $ssid'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter WiFi password:'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createHotspot() async {
    // Request location permission (required for WiFi operations on Android)
    final locationStatus = await Permission.location.request();

    if (!locationStatus.isGranted) {
      setState(() {
        _errorMessage = 'Location permission is required to create hotspot';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
      _selectedMode = NetworkMode.hotspot;
    });

    try {
      // Generate random hotspot credentials
      final ssid = 'BursaryServer-${Random().nextInt(9999).toString().padLeft(4, '0')}';
      final password = _generateRandomPassword(8);

      // Try to enable hotspot
      final success = await WiFiForIoTPlugin.setWiFiAPEnabled(true);

      if (success) {
        // Configure hotspot (may not work on all devices)
        try {
          await WiFiForIoTPlugin.setWiFiAPSSID(ssid);
          await WiFiForIoTPlugin.setWiFiAPPreSharedKey(password);
        } catch (e) {
          debugPrint('Warning: Could not configure hotspot: $e');
        }

        setState(() {
          _isLoading = false;
          _isHotspotEnabled = true;
          _hotspotSSID = ssid;
          _hotspotPassword = password;
          _successMessage = 'Hotspot created successfully';
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to enable hotspot. Please enable it manually from device settings.';
        });

        // Show manual instructions
        _showManualHotspotInstructions();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Hotspot creation failed: $e';
      });

      _showManualHotspotInstructions();
    }
  }

  String _generateRandomPassword(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(length, (index) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _disableHotspot() async {
    setState(() => _isLoading = true);

    try {
      await WiFiForIoTPlugin.setWiFiAPEnabled(false);

      setState(() {
        _isLoading = false;
        _isHotspotEnabled = false;
        _hotspotSSID = null;
        _hotspotPassword = null;
        _successMessage = 'Hotspot disabled';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to disable hotspot: $e';
      });
    }
  }

  void _showManualHotspotInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Manual Hotspot Setup'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Automatic hotspot creation is not supported on this device. Please follow these steps:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInstructionStep('1', 'Open device Settings'),
            _buildInstructionStep('2', 'Go to Network & Internet → Hotspot & Tethering'),
            _buildInstructionStep('3', 'Enable WiFi Hotspot'),
            _buildInstructionStep('4', 'Set a network name (SSID) and password'),
            _buildInstructionStep('5', 'Share the credentials with client devices'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Make sure to remember the credentials to share with client devices!',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
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
        title: const Text('Network Setup'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkCurrentNetwork,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Network Status
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.network_check, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Current Network Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildStatusRow(
                      'WiFi Connection',
                      _currentSSID ?? 'Not connected',
                      _currentSSID != null ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    _buildStatusRow(
                      'IP Address',
                      _currentIP ?? 'N/A',
                      _currentIP != null ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    _buildStatusRow(
                      'Hotspot',
                      _isHotspotEnabled ? 'Enabled' : 'Disabled',
                      _isHotspotEnabled ? Colors.orange : Colors.grey,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Network Mode Selection
            const Text(
              'Network Setup Options',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // WiFi Connection Option
            Card(
              elevation: 2,
              child: InkWell(
                onTap: _isLoading ? null : _scanWiFiNetworks,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.wifi,
                          color: Colors.blue,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connect to WiFi',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Use an existing WiFi network',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Hotspot Creation Option
            Card(
              elevation: 2,
              child: InkWell(
                onTap: _isLoading
                    ? null
                    : (_isHotspotEnabled ? _disableHotspot : _createHotspot),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.router,
                          color: Colors.orange,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isHotspotEnabled
                                  ? 'Disable Hotspot'
                                  : 'Create WiFi Hotspot',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isHotspotEnabled
                                  ? 'Turn off the WiFi hotspot'
                                  : 'Create a new WiFi network for clients',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _isHotspotEnabled ? Icons.close : Icons.arrow_forward_ios,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // WiFi Networks List
            if (_selectedMode == NetworkMode.wifi && _availableNetworks.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Available Networks',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ..._availableNetworks.map((network) {
                return Card(
                  child: ListTile(
                    leading: Icon(
                      _getSignalIcon(network.level ?? 0),
                      color: Colors.blue,
                    ),
                    title: Text(network.ssid ?? 'Unknown'),
                    subtitle: Text('Signal: ${network.level ?? 0}%'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _connectToWiFi(network),
                  ),
                );
              }),
            ],

            // Hotspot Info Display
            if (_isHotspotEnabled && _hotspotSSID != null) ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.router, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            'Hotspot Credentials',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildCredentialRow('Network Name (SSID)', _hotspotSSID!),
                      const SizedBox(height: 12),
                      _buildCredentialRow('Password', _hotspotPassword!),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Share these credentials with client devices to connect',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Status Messages
            if (_successMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Loading Indicator
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const Center(
                child: CircularProgressIndicator(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Row(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              tooltip: 'Copy',
            ),
          ],
        ),
      ],
    );
  }

  IconData _getSignalIcon(int level) {
    if (level >= 75) return Icons.signal_wifi_4_bar;
    if (level >= 50) return Icons.signal_wifi_4_bar;
    if (level >= 25) return Icons.network_wifi;
    return Icons.signal_wifi_off;
  }
}

enum NetworkMode {
  none,
  wifi,
  hotspot,
}
