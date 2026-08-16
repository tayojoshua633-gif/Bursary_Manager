// lib/widgets/network_status_indicator.dart
// Network status indicator for client mode
// Shows connection status and allows reconnection

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../client/server_discovery.dart';
import '../screens/client/client_connection_screen.dart';

enum NetworkStatus {
  connected,
  disconnected,
  checking,
}

class NetworkStatusIndicator extends StatefulWidget {
  final VoidCallback? onDisconnected;

  const NetworkStatusIndicator({
    super.key,
    this.onDisconnected,
  });

  @override
  State<NetworkStatusIndicator> createState() => _NetworkStatusIndicatorState();
}

class _NetworkStatusIndicatorState extends State<NetworkStatusIndicator> {
  NetworkStatus _status = NetworkStatus.checking;
  String? _serverUrl;
  String? _serverPin;
  Timer? _heartbeatTimer;
  Map<String, dynamic>? _serverInfo;

  @override
  void initState() {
    super.initState();
    _loadServerInfo();
    _startHeartbeat();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadServerInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('server_url');
    _serverPin = prefs.getString('server_pin');

    if (_serverUrl != null) {
      await _checkConnection();
    } else {
      setState(() {
        _status = NetworkStatus.disconnected;
      });
    }
  }

  void _startHeartbeat() {
    // Check connection every 10 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    if (_serverUrl == null) return;

    try {
      final info = await ServerDiscovery.getServerInfo(_serverUrl!);

      if (info != null) {
        setState(() {
          _status = NetworkStatus.connected;
          _serverInfo = info;
        });
      } else {
        setState(() {
          _status = NetworkStatus.disconnected;
          _serverInfo = null;
        });
        widget.onDisconnected?.call();
      }
    } catch (e) {
      setState(() {
        _status = NetworkStatus.disconnected;
        _serverInfo = null;
      });
      widget.onDisconnected?.call();
    }
  }

  Future<void> _reconnect() async {
    if (_serverPin == null) return;

    setState(() {
      _status = NetworkStatus.checking;
    });

    try {
      final newUrl = await ServerDiscovery.discoverServerByPin(_serverPin!);

      if (newUrl != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('server_url', newUrl);

        setState(() {
          _serverUrl = newUrl;
          _status = NetworkStatus.connected;
        });

        await _checkConnection();
      } else {
        setState(() {
          _status = NetworkStatus.disconnected;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not reconnect to server'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _status = NetworkStatus.disconnected;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reconnection failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 12),
            Text('Disconnect from Server?'),
          ],
        ),
        content: const Text(
          'This will disconnect you from the server and return you to the connection screen. '
          'You will need to log in again to reconnect.',
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
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Clear server connection data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server_url');
    await prefs.remove('server_pin');
    await prefs.remove('isLoggedIn');
    await prefs.remove('username');
    await prefs.remove('userType');
    await prefs.remove('userId');
    await prefs.setString('app_mode', 'standalone');

    // Navigate to connection screen
    if (!mounted) return;

    // Import needed for navigation
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const ClientConnectionScreen(),
      ),
      (route) => false,
    );
  }

  void _showStatusDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            _buildStatusIcon(),
            const SizedBox(width: 12),
            const Text('Server Connection'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Status', _getStatusText(), _getStatusColor()),
            if (_serverInfo != null) ...[
              const Divider(),
              _buildInfoRow('IP Address', _serverInfo!['ipAddress'] ?? 'Unknown'),
              _buildInfoRow('Port', _serverInfo!['port']?.toString() ?? '8080'),
              _buildInfoRow('Network', _serverInfo!['ssid'] ?? 'Unknown'),
              _buildInfoRow('Version', _serverInfo!['version'] ?? '1.0.0'),
            ],
          ],
        ),
        actions: [
          if (_status == NetworkStatus.disconnected)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _reconnect();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reconnect'),
            ),
          if (_status == NetworkStatus.connected)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _disconnect();
              },
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Disconnect', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
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
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontSize: 14,
                fontWeight: valueColor != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (_status) {
      case NetworkStatus.connected:
        return Colors.green;
      case NetworkStatus.disconnected:
        return Colors.red;
      case NetworkStatus.checking:
        return Colors.orange;
    }
  }

  String _getStatusText() {
    switch (_status) {
      case NetworkStatus.connected:
        return 'Connected';
      case NetworkStatus.disconnected:
        return 'Disconnected';
      case NetworkStatus.checking:
        return 'Checking...';
    }
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case NetworkStatus.connected:
        return Icons.cloud_done;
      case NetworkStatus.disconnected:
        return Icons.cloud_off;
      case NetworkStatus.checking:
        return Icons.cloud_sync;
    }
  }

  Widget _buildStatusIcon() {
    return Icon(
      _getStatusIcon(),
      color: _getStatusColor(),
      size: 20,
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _showStatusDialog,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getStatusColor().withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _getStatusColor().withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusIcon(),
            const SizedBox(width: 6),
            Text(
              _getStatusText(),
              style: TextStyle(
                color: _getStatusColor(),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple badge version for AppBar
class NetworkStatusBadge extends StatefulWidget {
  const NetworkStatusBadge({super.key});

  @override
  State<NetworkStatusBadge> createState() => _NetworkStatusBadgeState();
}

class _NetworkStatusBadgeState extends State<NetworkStatusBadge> {
  bool _isConnected = true;
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    _startChecking();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  void _startChecking() {
    _checkTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('server_url');

      if (serverUrl != null) {
        try {
          final info = await ServerDiscovery.getServerInfo(serverUrl);
          setState(() {
            _isConnected = info != null;
          });
        } catch (e) {
          setState(() {
            _isConnected = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _isConnected ? Colors.green : Colors.red,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
