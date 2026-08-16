// lib/server/server.dart
// HTTP server core for serving bursary manager API
// Runs on port 8080 and serves REST API to client devices

import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'auth_middleware.dart';
import 'routes/auth_routes.dart';
import 'routes/students_routes.dart';
import 'routes/payments_routes.dart';
import 'routes/classes_routes.dart';
import 'routes/fees_routes.dart';
import 'routes/bills_routes.dart';
import 'routes/sessions_routes.dart';
import 'routes/permissions_routes.dart';
import 'routes/school_routes.dart';
import 'routes/settings_routes.dart';
import 'routes/reports_routes.dart';
import 'routes/audit_log_routes.dart';
import 'routes/expenses_routes.dart';
import 'routes/staff_financial_routes.dart';
import 'routes/stock_routes.dart';
import 'routes/sales_routes.dart';
import 'routes/transport_routes.dart';

class ConnectedClient {
  final String ipAddress;
  final String username;
  final String userType;
  final DateTime connectedAt;

  ConnectedClient({
    required this.ipAddress,
    required this.username,
    required this.userType,
    required this.connectedAt,
  });

  Map<String, dynamic> toJson() => {
        'ipAddress': ipAddress,
        'username': username,
        'userType': userType,
        'connectedAt': connectedAt.toIso8601String(),
        'duration': DateTime.now().difference(connectedAt).inMinutes,
      };
}

class BursaryServer {
  // Singleton pattern - ensure only one server instance exists
  static final BursaryServer _instance = BursaryServer._internal();
  factory BursaryServer() => _instance;
  BursaryServer._internal();

  HttpServer? _server;
  final int _port = 8080;
  String? _serverPin;
  MDnsClient? _mdnsClient;
  final List<ConnectedClient> _connectedClients = [];

  bool get isRunning => _server != null;
  String? get serverPin => _serverPin;
  int get port => _port;
  List<ConnectedClient> get connectedClients => List.unmodifiable(_connectedClients);

  /// Add a connected client
  void addClient(String ipAddress, String username, String userType) {
    // Remove existing connection from same IP or username
    _connectedClients.removeWhere(
      (c) => c.ipAddress == ipAddress || c.username == username,
    );

    // Add new connection
    _connectedClients.add(ConnectedClient(
      ipAddress: ipAddress,
      username: username,
      userType: userType,
      connectedAt: DateTime.now(),
    ));

    print('👤 Client connected: $username ($ipAddress) - ${_connectedClients.length} total');
  }

  /// Remove a connected client by IP address
  void removeClient(String ipAddress) {
    final removed = _connectedClients.where((c) => c.ipAddress == ipAddress).toList();
    _connectedClients.removeWhere((c) => c.ipAddress == ipAddress);

    for (var client in removed) {
      print('👋 Client disconnected: ${client.username} ($ipAddress)');
    }
  }

  /// Clear all connected clients
  void clearAllClients() {
    _connectedClients.clear();
    print('🧹 All clients disconnected');
  }

  /// Start the HTTP server
  Future<void> start() async {
    if (_server != null) {
      print('⚠️ Server already running');
      return;
    }

    try {
      // Create router with all API routes
      final router = _createRouter();

      // Create handler pipeline with middleware
      final handler = Pipeline()
          .addMiddleware(logRequests())
          .addMiddleware(corsHeaders())
          .addHandler(router.call);

      // Start HTTP server with shared socket (allows graceful restart)
      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        _port,
        shared: true,
      );

      print('✅ Server started on port $_port');

      // Generate 6-digit PIN
      _serverPin = _generatePin();
      print('🔑 Server PIN: $_serverPin');

      // Start mDNS service discovery
      await _startServiceDiscovery();

      print('📡 mDNS service discovery started');
    } catch (e) {
      print('❌ Failed to start server: $e');
      _server = null;
      rethrow;
    }
  }

  /// Stop the HTTP server
  Future<void> stop() async {
    if (_server == null) {
      print('⚠️ Server not running');
      return;
    }

    try {
      await _stopServiceDiscovery();
      await _server?.close(force: true);
      _server = null;
      _serverPin = null;
      print('🛑 Server stopped');
    } catch (e) {
      print('❌ Error stopping server: $e');
      rethrow;
    }
  }

  /// Create router with all API routes
  Router _createRouter() {
    final router = Router();

    // Public routes (no authentication required)
    final authRoutes = AuthRoutes();
    router.mount('/api/auth/', authRoutes.router.call);
    router.get('/api/server-info', _getServerInfo);

    // Connected clients management (for server UI only - no auth needed as it's local)
    router.get('/api/connected-clients', _getConnectedClients);
    router.post('/api/disconnect-client', _disconnectClient);

    // Protected routes (require JWT authentication)
    final protectedRouter = Router();

    // Mount all resource routes
    final studentsRoutes = StudentsRoutes();
    protectedRouter.mount('/api/students/', studentsRoutes.router.call);

    final paymentsRoutes = PaymentsRoutes();
    protectedRouter.mount('/api/payments/', paymentsRoutes.router.call);

    final classesRoutes = ClassesRoutes();
    protectedRouter.mount('/api/classes/', classesRoutes.router.call);

    final feesRoutes = FeesRoutes();
    protectedRouter.mount('/api/fees/', feesRoutes.router.call);

    final billsRoutes = BillsRoutes();
    protectedRouter.mount('/api/bills/', billsRoutes.router.call);

    final sessionsRoutes = SessionsRoutes();
    protectedRouter.mount('/api/sessions/', sessionsRoutes.router.call);

    final permissionsRoutes = PermissionsRoutes();
    protectedRouter.mount('/api/permissions/', permissionsRoutes.router.call);

    final schoolRoutes = SchoolRoutes();
    protectedRouter.mount('/api/school/', schoolRoutes.router.call);

    final settingsRoutes = SettingsRoutes();
    protectedRouter.mount('/api/settings/', settingsRoutes.router.call);

    final reportsRoutes = ReportsRoutes();
    protectedRouter.mount('/api/reports/', reportsRoutes.router.call);

    final auditLogRoutes = AuditLogRoutes();
    protectedRouter.mount('/api/audit-log/', auditLogRoutes.router.call);

    final expensesRoutes = ExpensesRoutes();
    protectedRouter.mount('/api/expenses/', expensesRoutes.router.call);

    final staffFinancialRoutes = StaffFinancialRoutes();
    protectedRouter.mount('/api/staff-financial/', staffFinancialRoutes.router.call);

    final stockItemsRoutes = StockItemsRoutes();
    protectedRouter.mount('/api/stock-items/', stockItemsRoutes.router.call);

    final suppliersRoutes = SuppliersRoutes();
    protectedRouter.mount('/api/suppliers/', suppliersRoutes.router.call);

    final salesRoutes = SalesRoutes();
    protectedRouter.mount('/api/sales/', salesRoutes.router.call);

    final transportRoutes = TransportRoutes();
    protectedRouter.mount('/api/transport/', transportRoutes.router.call);

    // Apply JWT middleware to protected routes
    router.mount(
      '/',
      Pipeline()
          .addMiddleware(jwtMiddleware)
          .addHandler(protectedRouter.call),
    );

    return router;
  }

  /// Generate 6-digit PIN (100000 to 999999)
  String _generatePin() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// Get server information endpoint
  Future<Response> _getServerInfo(Request request) async {
    try {
      final networkInfo = await _getNetworkInfo();

      return Response.ok(
        '''
{
  "pin": "$_serverPin",
  "ipAddress": "${networkInfo['ip']}",
  "port": $_port,
  "isHotspot": ${networkInfo['isHotspot']},
  "ssid": "${networkInfo['ssid']}",
  "version": "1.0.0"
}
''',
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: '{"error": "Failed to get server info: $e"}',
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Get list of connected clients
  Future<Response> _getConnectedClients(Request request) async {
    try {
      final clients = _connectedClients.map((c) => c.toJson()).toList();

      return Response.ok(
        '''
{
  "clients": ${clients.map((c) => '''
    {
      "ipAddress": "${c['ipAddress']}",
      "username": "${c['username']}",
      "userType": "${c['userType']}",
      "connectedAt": "${c['connectedAt']}",
      "duration": ${c['duration']}
    }''').join(',')},
  "total": ${clients.length}
}
''',
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: '{"error": "Failed to get connected clients: $e"}',
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Disconnect a client by IP address
  Future<Response> _disconnectClient(Request request) async {
    try {
      final body = await request.readAsString();
      final ipMatch = RegExp(r'"ipAddress"\s*:\s*"([^"]+)"').firstMatch(body);

      if (ipMatch == null) {
        return Response.badRequest(
          body: '{"error": "Missing ipAddress in request body"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      final ipAddress = ipMatch.group(1)!;
      removeClient(ipAddress);

      return Response.ok(
        '{"success": true, "message": "Client disconnected"}',
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: '{"error": "Failed to disconnect client: $e"}',
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Get network information (IP address, SSID, etc.)
  Future<Map<String, dynamic>> _getNetworkInfo() async {
    try {
      final networkInfo = NetworkInfo();

      // Get WiFi SSID
      String? ssid;
      try {
        ssid = await networkInfo.getWifiName();
        // Remove quotes from SSID if present
        ssid = ssid?.replaceAll('"', '');
      } catch (e) {
        ssid = 'Unknown';
      }

      // Get IP address
      String? ip;
      try {
        ip = await networkInfo.getWifiIP();
      } catch (e) {
        // Fallback: get from network interfaces
        final interfaces = await NetworkInterface.list();
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              ip = addr.address;
              break;
            }
          }
          if (ip != null) break;
        }
      }

      return {
        'ip': ip ?? 'Unknown',
        'ssid': ssid ?? 'Unknown',
        'isHotspot': false, // TODO: Detect hotspot mode
      };
    } catch (e) {
      print('Error getting network info: $e');
      return {
        'ip': 'Unknown',
        'ssid': 'Unknown',
        'isHotspot': false,
      };
    }
  }

  /// Start mDNS service discovery (broadcast server availability)
  Future<void> _startServiceDiscovery() async {
    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();

      // Broadcast service: _bursary._tcp.local
      // Include PIN in TXT record for client discovery

      // Note: Full mDNS service registration requires additional implementation
      // For now, we're just starting the client for service queries
      // Full service registration would require platform-specific code

      print('📡 mDNS client started (service registration pending)');
    } catch (e) {
      print('⚠️ mDNS service discovery failed: $e');
      // Non-critical error - server can still work with manual IP entry
    }
  }

  /// Stop mDNS service discovery
  Future<void> _stopServiceDiscovery() async {
    try {
      _mdnsClient?.stop();
      _mdnsClient = null;
      print('📡 mDNS service stopped');
    } catch (e) {
      print('⚠️ Error stopping mDNS: $e');
    }
  }

  /// CORS middleware for allowing cross-origin requests
  Middleware corsHeaders() {
    return (Handler handler) {
      return (Request request) async {
        // Handle preflight requests
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }

        // Add CORS headers to response
        final response = await handler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  /// CORS headers
  final Map<String, String> _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
  };
}
