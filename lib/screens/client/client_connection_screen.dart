// lib/screens/client/client_connection_screen.dart
// Client connection screen for entering server IP and PIN

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../client/server_discovery.dart';
import '../auth/mode_selection_screen.dart';
import 'client_login_screen.dart';

class ClientConnectionScreen extends StatefulWidget {
  const ClientConnectionScreen({super.key});

  @override
  State<ClientConnectionScreen> createState() => _ClientConnectionScreenState();
}

class _ClientConnectionScreenState extends State<ClientConnectionScreen> {
  final _ipController = TextEditingController();
  final _pinController = TextEditingController();

  bool _connecting = false;
  String? _errorMessage;
  String? _statusMessage;
  String? _clientIp;
  String? _clientSubnet;
  bool _loadingNetworkInfo = true;

  @override
  void initState() {
    super.initState();
    _getClientNetworkInfo();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  /// Get client device's IP address and subnet
  Future<void> _getClientNetworkInfo() async {
    try {
      final interfaces = await NetworkInterface.list();

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            setState(() {
              _clientIp = addr.address;

              // Extract subnet (e.g., "192.168.1" from "192.168.1.179")
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                _clientSubnet = '${parts[0]}.${parts[1]}.${parts[2]}';
              }

              _loadingNetworkInfo = false;
            });
            return;
          }
        }
      }

      // No network found
      setState(() {
        _loadingNetworkInfo = false;
      });
    } catch (e) {
      print('Error getting network info: $e');
      setState(() {
        _loadingNetworkInfo = false;
      });
    }
  }

  /// Check if client appears to be on a different network than server
  bool _isPotentialNetworkMismatch(String serverIp) {
    if (_clientSubnet == null) return false;

    // Extract server subnet
    final serverParts = serverIp.split('.');
    if (serverParts.length != 4) return false;

    final serverSubnet = '${serverParts[0]}.${serverParts[1]}.${serverParts[2]}';

    // Check if subnets match
    return _clientSubnet != serverSubnet;
  }

  Future<void> _connectToServer() async {
    final ip = _ipController.text.trim();
    final pin = _pinController.text.trim();

    if (ip.isEmpty || pin.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both server IP address and PIN';
      });
      return;
    }

    if (pin.length != 6 || int.tryParse(pin) == null) {
      setState(() {
        _errorMessage = 'PIN must be exactly 6 digits';
      });
      return;
    }

    // Basic IP validation
    final ipParts = ip.split('.');
    if (ipParts.length != 4 || !ipParts.every((part) => int.tryParse(part) != null)) {
      setState(() {
        _errorMessage = 'Please enter a valid IP address (e.g., 192.168.1.100)';
      });
      return;
    }

    // Check for network mismatch
    if (_isPotentialNetworkMismatch(ip)) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('Network Mismatch'),
            ],
          ),
          content: Text(
            'Your device is on subnet $_clientSubnet.x but the server is on ${ip.split('.').take(3).join('.')}.x\n\n'
            'This means you are on different networks. Connection may fail.\n\n'
            'Make sure both devices are connected to the same WiFi network.\n\n'
            'Do you want to try connecting anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Try Anyway'),
            ),
          ],
        ),
      );

      if (shouldContinue != true) return;
    }

    setState(() {
      _connecting = true;
      _errorMessage = null;
      _statusMessage = 'Connecting to $ip...';
    });

    try {
      final serverUrl = await ServerDiscovery.connectManual(ip, pin);

      if (serverUrl == null) {
        if (!mounted) return;
        setState(() {
          _connecting = false;
          _errorMessage = 'Connection failed. Please check:\n'
              '• Server IP address is correct\n'
              '• PIN is correct (check server screen)\n'
              '• Server is running\n'
              '• Both devices are on the same WiFi network';
          _statusMessage = null;
        });
        return;
      }

      // Save server URL and PIN
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', serverUrl);
      await prefs.setString('server_pin', pin);

      // Get server info
      final serverInfo = await ServerDiscovery.getServerInfo(serverUrl);

      if (!mounted) return;
      setState(() {
        _connecting = false;
        _statusMessage = 'Connected to server!';
      });

      // Navigate to client login screen
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ClientLoginScreen(
            serverUrl: serverUrl,
            serverInfo: serverInfo ?? {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _errorMessage = 'Connection failed: $e';
        _statusMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Server'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            // Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.devices,
                size: 80,
                color: Colors.indigo.shade700,
              ),
            ),

            const SizedBox(height: 32),

            // Title
            const Text(
              'Client Mode',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              'Connect to a server device to access the bursary system',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Network Info Card
            if (!_loadingNetworkInfo && _clientIp != null) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.wifi, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Your Network',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'IP Address: ',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            _clientIp!,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Subnet: ',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '$_clientSubnet.x',
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Connection Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.router, color: Colors.indigo),
                        SizedBox(width: 8),
                        Text(
                          'Server Connection',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the server IP address and PIN from the server device',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Server IP Address Input
                    TextField(
                      controller: _ipController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Server IP Address',
                        hintText: 'e.g., 192.168.1.100',
                        helperText: 'Find this on the server screen under "Server Management"',
                        prefixIcon: const Icon(Icons.router),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // PIN Input
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        fontFamily: 'monospace',
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Server PIN',
                        hintText: '------',
                        helperText: 'Find the 6-digit PIN on the server screen',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.indigo.shade50,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Connect Button
                    ElevatedButton.icon(
                      onPressed: _connecting ? null : _connectToServer,
                      icon: _connecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.link),
                      label: Text(_connecting ? 'Connecting...' : 'Connect to Server'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Status/Error Messages
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
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
                        _statusMessage!,
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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

            const SizedBox(height: 24),

            // Troubleshooting Tips
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.help_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'How to Connect',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTip('1. Open Server Management on the server device'),
                    _buildTip('2. Note the IP address and PIN displayed'),
                    _buildTip('3. Make sure this device is on the same WiFi network'),
                    _buildTip('4. Enter the IP address and PIN above'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
