// lib/client/server_discovery.dart
// Server discovery via mDNS and PIN matching
// Falls back to manual IP entry if mDNS fails

import 'dart:async';
import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ServerDiscovery {
  static const String _serviceType = '_bursary._tcp';
  static const int _serverPort = 8080;
  static const Duration _discoveryTimeout = Duration(seconds: 15);

  /// Discover server by PIN
  /// Returns server URL (e.g., "http://192.168.1.100:8080") or null if not found
  static Future<String?> discoverServerByPin(String pin) async {
    print('🔍 Starting server discovery for PIN: $pin');

    // Try mDNS discovery first
    final mdnsUrl = await _discoverViaMdns(pin);
    if (mdnsUrl != null) {
      print('✅ Server found via mDNS: $mdnsUrl');
      return mdnsUrl;
    }

    // Fallback: scan local network
    print('⚠️ mDNS discovery failed, trying network scan...');
    final scanUrl = await _scanLocalNetwork(pin);
    if (scanUrl != null) {
      print('✅ Server found via network scan: $scanUrl');
      return scanUrl;
    }

    print('❌ Server not found');
    return null;
  }

  /// Verify server by checking if it responds with the correct PIN
  static Future<bool> verifyServer(String url, String pin) async {
    try {
      final response = await http.get(
        Uri.parse('$url/api/server-info'),
      ).timeout(Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['pin'] == pin;
      }
      return false;
    } catch (e) {
      print('❌ Error verifying server at $url: $e');
      return false;
    }
  }

  /// Get server info from URL
  static Future<Map<String, dynamic>?> getServerInfo(String url) async {
    try {
      final response = await http.get(
        Uri.parse('$url/api/server-info'),
      ).timeout(Duration(seconds: 3));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('❌ Error getting server info: $e');
      return null;
    }
  }

  /// Discover server via mDNS
  static Future<String?> _discoverViaMdns(String pin) async {
    MDnsClient? client;

    try {
      client = MDnsClient();
      await client.start();

      print('📡 mDNS client started, searching for $_serviceType services...');

      // Query for bursary service
      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceType),
          )
          .timeout(_discoveryTimeout)) {
        print('📡 Found service: ${ptr.domainName}');

        // Get service details (SRV record for port, A record for IP)
        await for (final SrvResourceRecord srv in client
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )
            .timeout(Duration(seconds: 2))) {
          print('📡 Service details: ${srv.target}:${srv.port}');

          // Get IP address
          await for (final IPAddressResourceRecord ip in client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              )
              .timeout(Duration(seconds: 2))) {
            final serverUrl = 'http://${ip.address.address}:${srv.port}';
            print('📡 Checking server at $serverUrl');

            // Verify PIN matches
            if (await verifyServer(serverUrl, pin)) {
              return serverUrl;
            }
          }
        }
      }

      print('⚠️ No matching server found via mDNS');
      return null;
    } catch (e) {
      print('⚠️ mDNS discovery error: $e');
      return null;
    } finally {
      client?.stop();
    }
  }

  /// Scan local network for server
  /// This is a fallback when mDNS fails
  static Future<String?> _scanLocalNetwork(String pin) async {
    try {
      // Get local IP to determine subnet
      final interfaces = await NetworkInterface.list();
      String? localIp;

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            localIp = addr.address;
            break;
          }
        }
        if (localIp != null) break;
      }

      if (localIp == null) {
        print('⚠️ Could not determine local IP address');
        return null;
      }

      print('📡 Local IP: $localIp, scanning subnet...');

      // Extract subnet (e.g., "192.168.1" from "192.168.1.179")
      final parts = localIp.split('.');
      if (parts.length != 4) return null;
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

      // Common IP addresses to check first (router, common server IPs)
      final priorityIps = [
        '$subnet.1', // Router
        localIp, // This device (in case server is running locally)
        '$subnet.100',
        '$subnet.101',
        '$subnet.10',
        '$subnet.2',
      ];

      // Check priority IPs first
      for (final ip in priorityIps) {
        final url = 'http://$ip:$_serverPort';
        if (await verifyServer(url, pin)) {
          return url;
        }
      }

      // If not found in priority IPs, scan full range (async, limited concurrency)
      final futures = <Future<String?>>[];
      for (int i = 1; i <= 254; i++) {
        final ip = '$subnet.$i';
        if (priorityIps.contains(ip)) continue; // Already checked

        final url = 'http://$ip:$_serverPort';
        futures.add(_checkServerQuick(url, pin));

        // Process in batches of 20 to avoid overwhelming the network
        if (futures.length >= 20) {
          final results = await Future.wait(futures);
          final found = results.firstWhere((r) => r != null, orElse: () => null);
          if (found != null) return found;
          futures.clear();
        }
      }

      // Check remaining
      if (futures.isNotEmpty) {
        final results = await Future.wait(futures);
        final found = results.firstWhere((r) => r != null, orElse: () => null);
        if (found != null) return found;
      }

      return null;
    } catch (e) {
      print('⚠️ Network scan error: $e');
      return null;
    }
  }

  /// Quick server check with very short timeout
  static Future<String?> _checkServerQuick(String url, String pin) async {
    try {
      final response = await http.get(
        Uri.parse('$url/api/server-info'),
      ).timeout(Duration(milliseconds: 1000));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['pin'] == pin) {
          return url;
        }
      }
      return null;
    } catch (e) {
      // Timeout or connection refused - expected for most IPs
      return null;
    }
  }

  /// Manual server connection by IP address
  /// Returns server URL if valid and PIN matches
  static Future<String?> connectManual(String ipAddress, String pin) async {
    try {
      // Clean up IP address (remove http://, trailing slashes, etc.)
      String cleanIp = ipAddress.trim();
      cleanIp = cleanIp.replaceAll('http://', '').replaceAll('https://', '');
      cleanIp = cleanIp.split(':').first; // Remove port if included
      cleanIp = cleanIp.split('/').first; // Remove path if included

      final url = 'http://$cleanIp:$_serverPort';
      print('🔌 Attempting manual connection to $url');

      if (await verifyServer(url, pin)) {
        print('✅ Manual connection successful');
        return url;
      } else {
        print('❌ Server found but PIN does not match');
        return null;
      }
    } catch (e) {
      print('❌ Manual connection failed: $e');
      return null;
    }
  }
}
