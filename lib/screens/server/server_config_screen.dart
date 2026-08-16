// lib/screens/server/server_config_screen.dart
// Server configuration and management screen

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../server/server.dart';
import '../auth/welcome_screen.dart';
import 'network_setup_screen.dart';

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final BursaryServer _server = BursaryServer();

  bool _serverRunning = false;
  bool _starting = false;
  String? _serverPin;
  String? _ipAddress;
  int? _port;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeServer();
  }

  @override
  void dispose() {
    // Don't stop server on dispose - it should keep running
    // Server should only be stopped explicitly by user action or logout
    super.dispose();
  }

  Future<void> _initializeServer() async {
    setState(() {
      _starting = true;
      _errorMessage = null;
    });

    try {
      // Start the server
      await _server.start();

      setState(() {
        _serverRunning = true;
        _serverPin = _server.serverPin;
        _port = _server.port;
        _starting = false;
      });

      // Get network info
      await _refreshNetworkInfo();
    } catch (e) {
      setState(() {
        _serverRunning = false;
        _starting = false;
        _errorMessage = 'Failed to start server: $e';
      });
    }
  }

  Future<void> _refreshNetworkInfo() async {
    try {
      // Get IP address from network interfaces
      final interfaces = await NetworkInterface.list();
      String? ip;

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ip = addr.address;
            break;
          }
        }
        if (ip != null) break;
      }

      setState(() {
        _ipAddress = ip ?? 'Unknown';
      });
    } catch (e) {
      setState(() {
        _ipAddress = 'Error getting IP';
      });
    }
  }

  Future<void> _stopServer() async {
    try {
      await _server.stop();
      setState(() {
        _serverRunning = false;
        _serverPin = null;
        _ipAddress = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to stop server: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _restartServer() async {
    await _stopServer();
    await Future.delayed(const Duration(milliseconds: 500));
    await _initializeServer();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _continueToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Configuration'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_serverRunning)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _restartServer,
              tooltip: 'Restart Server',
            ),
        ],
      ),
      body: _starting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Starting server...'),
                ],
              ),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : _serverRunning
                  ? _buildServerRunning()
                  : _buildServerStopped(),
      bottomNavigationBar: _serverRunning
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: _continueToLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Continue to Login',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Server Failed to Start',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initializeServer,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerStopped() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dns_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Server Stopped',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Start the server to allow client devices to connect',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initializeServer,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Server'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerRunning() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Server Status Card
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.check_circle, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Server Running',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Ready to accept client connections',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Connection PIN Card
          Card(
            elevation: 4,
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.vpn_key, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Connection PIN',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Large PIN Display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo, width: 2),
                    ),
                    child: SelectableText(
                      _serverPin ?? '------',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 12,
                        fontFamily: 'monospace',
                        color: Colors.indigo,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Copy Button
                  OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(_serverPin ?? '', 'PIN'),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy PIN'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Share this PIN with clients to connect',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Network Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.network_check, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Network Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  _buildInfoRow('IP Address', _ipAddress ?? 'Loading...', Icons.router),
                  _buildInfoRow('Port', _port?.toString() ?? '8080', Icons.settings_ethernet),
                  _buildInfoRow('Protocol', 'HTTP', Icons.http),
                  _buildInfoRow('Status', 'Active', Icons.circle, valueColor: Colors.green),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Network Setup Button
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NetworkSetupScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings_ethernet),
            label: const Text('Network Setup'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 16),

          // Instructions Card
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
                        'How to Connect Clients',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInstruction(1, 'Ensure client device is on the same WiFi network'),
                  _buildInstruction(2, 'Open the app on the client device'),
                  _buildInstruction(3, 'Select "Client Mode"'),
                  _buildInstruction(4, 'Enter the 6-digit PIN shown above'),
                  _buildInstruction(5, 'Login with your credentials'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Server Actions
          OutlinedButton.icon(
            onPressed: _stopServer,
            icon: const Icon(Icons.stop),
            label: const Text('Stop Server'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 80), // Space for bottom button
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontWeight: valueColor != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () => _copyToClipboard(value, label),
            tooltip: 'Copy',
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildInstruction(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
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
}
