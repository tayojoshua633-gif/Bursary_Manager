// lib/screens/server/server_management_screen.dart
// Server management screen for superadmin - start/stop server, view status, manage clients

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../server/server.dart';
import 'network_setup_screen.dart';

class ServerManagementScreen extends StatefulWidget {
  const ServerManagementScreen({super.key});

  @override
  State<ServerManagementScreen> createState() => _ServerManagementScreenState();
}

class _ServerManagementScreenState extends State<ServerManagementScreen> {
  final BursaryServer _server = BursaryServer();

  bool _serverRunning = false;
  bool _isProcessing = false;
  String? _serverPin;
  String? _ipAddress;
  int? _port;
  String? _errorMessage;
  String _appMode = 'standalone';
  List<ConnectedClient> _connectedClients = [];

  @override
  void initState() {
    super.initState();
    _loadAppMode();
    _checkServerStatus();
  }

  @override
  void dispose() {
    // Don't stop server on dispose - it should keep running
    super.dispose();
  }

  Future<void> _loadAppMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _appMode = prefs.getString('app_mode') ?? 'standalone';
    });
  }

  Future<void> _checkServerStatus() async {
    setState(() => _isProcessing = true);

    try {
      // Check if server is running by checking if the instance has active state
      if (_server.isRunning) {
        setState(() {
          _serverRunning = true;
          _serverPin = _server.serverPin;
          _port = _server.port;
        });

        await _refreshNetworkInfo();
        await _loadConnectedClients();
      } else {
        setState(() {
          _serverRunning = false;
          _serverPin = null;
          _ipAddress = null;
          _connectedClients = [];
        });
      }
    } catch (e) {
      debugPrint('Error checking server status: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _loadConnectedClients() async {
    if (!_server.isRunning) return;

    try {
      setState(() {
        _connectedClients = _server.connectedClients;
      });
    } catch (e) {
      debugPrint('Error loading connected clients: $e');
    }
  }

  Future<void> _disconnectClient(ConnectedClient client) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Client?'),
        content: Text(
          'Disconnect ${client.username} (${client.ipAddress})?\n\n'
          'They will need to reconnect to continue using the system.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      _server.removeClient(client.ipAddress);
      await _loadConnectedClients();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${client.username} disconnected'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to disconnect client: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshNetworkInfo() async {
    try {
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

  Future<void> _startServer() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      await _server.start();

      setState(() {
        _serverRunning = true;
        _serverPin = _server.serverPin;
        _port = _server.port;
      });

      // Set app mode to server
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_mode', 'server');
      setState(() => _appMode = 'server');

      await _refreshNetworkInfo();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server started successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to start server: $e';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start server: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _stopServer() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Server?'),
        content: const Text(
          'This will disconnect all connected clients. Are you sure you want to stop the server?',
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
              foregroundColor: Colors.white,
            ),
            child: const Text('Stop Server'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    try {
      await _server.stop();

      setState(() {
        _serverRunning = false;
        _serverPin = null;
        _ipAddress = null;
      });

      // Revert app mode to standalone
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_mode', 'standalone');
      setState(() => _appMode = 'standalone');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server stopped'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to stop server: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _restartServer() async {
    setState(() => _isProcessing = true);

    try {
      await _server.stop();
      await Future.delayed(const Duration(milliseconds: 500));
      await _server.start();

      setState(() {
        _serverRunning = true;
        _serverPin = _server.serverPin;
        _port = _server.port;
      });

      await _refreshNetworkInfo();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server restarted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restart server: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Management'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (_serverRunning && !_isProcessing)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _restartServer,
              tooltip: 'Restart Server',
            ),
        ],
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processing...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Server Status Card
                  Card(
                    color: _serverRunning ? Colors.green.shade50 : Colors.grey.shade100,
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _serverRunning ? Colors.green : Colors.grey,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _serverRunning ? Icons.check_circle : Icons.cloud_off,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _serverRunning ? 'Server Running' : 'Server Stopped',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: _serverRunning ? Colors.green.shade700 : Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _serverRunning
                                          ? 'Clients can connect to this server'
                                          : 'Start the server to allow connections',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_serverRunning) ...[
                    const SizedBox(height: 20),

                    // Connection PIN Card
                    Card(
                      elevation: 4,
                      color: Colors.indigo.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
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
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

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

                            OutlinedButton.icon(
                              onPressed: () => _copyToClipboard(_serverPin ?? '', 'PIN'),
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copy PIN'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.indigo,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Network Information
                    Card(
                      elevation: 2,
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
                            _buildInfoRow('Mode', _appMode.toUpperCase(), Icons.settings, valueColor: Colors.green),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Connected Clients Card
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.devices, color: Colors.indigo),
                                    SizedBox(width: 8),
                                    Text(
                                      'Connected Clients',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _connectedClients.isEmpty ? Colors.grey : Colors.green,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_connectedClients.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(),
                            if (_connectedClients.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No clients connected',
                                        style: TextStyle(color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _connectedClients.length,
                                separatorBuilder: (_, _) => const Divider(),
                                itemBuilder: (context, index) {
                                  final client = _connectedClients[index];
                                  final duration = DateTime.now().difference(client.connectedAt);
                                  final durationText = duration.inMinutes < 1
                                      ? 'Just now'
                                      : duration.inHours < 1
                                          ? '${duration.inMinutes}m ago'
                                          : '${duration.inHours}h ${duration.inMinutes % 60}m ago';

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.indigo.shade100,
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.indigo.shade700,
                                      ),
                                    ),
                                    title: Text(
                                      client.username,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.badge, size: 14, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(
                                              client.userType,
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.router, size: 14, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(
                                              client.ipAddress,
                                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(
                                              durationText,
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.power_settings_new, color: Colors.orange),
                                      tooltip: 'Disconnect',
                                      onPressed: () => _disconnectClient(client),
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(height: 8),
                            if (_connectedClients.isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: _loadConnectedClients,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Refresh'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.indigo,
                                ),
                              ),
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
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Server Control Buttons
                  if (!_serverRunning)
                    ElevatedButton.icon(
                      onPressed: _startServer,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Server'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _stopServer,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Server'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),

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

                  const SizedBox(height: 24),

                  // Instructions
                  if (_serverRunning)
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
                                  'How Clients Connect',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildInstruction(1, 'Client device must be on the same WiFi network'),
                            _buildInstruction(2, 'Open the app on client device'),
                            _buildInstruction(3, 'Tap "Connect as Client"'),
                            _buildInstruction(4, 'Enter the IP address shown above'),
                            _buildInstruction(5, 'Enter the 6-digit PIN shown above'),
                            _buildInstruction(6, 'Login with their credentials'),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
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
                number.toString(),
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
