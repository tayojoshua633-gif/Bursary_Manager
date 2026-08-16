// lib/data/repository_factory.dart
// Factory that creates appropriate repository based on app mode
// Routes to LocalDataSource (SQLite) or RemoteDataSource (HTTP API)

import 'package:shared_preferences/shared_preferences.dart';
import 'repository.dart';
import 'local_data_source.dart';
import 'remote_data_source.dart';

class RepositoryFactory {
  static DataRepository? _instance;

  /// Get repository instance based on app mode stored in SharedPreferences
  static Future<DataRepository> getInstance() async {
    if (_instance != null) {
      print('📦 Repository: Returning cached instance (${_instance.runtimeType})');
      return _instance!;
    }

    final prefs = await SharedPreferences.getInstance();
    final appMode = prefs.getString('app_mode') ?? 'standalone';
    print('📦 Repository: Creating NEW instance for mode: $appMode');

    if (appMode == 'client') {
      // Client mode: use remote data source (API calls)
      final serverUrl = prefs.getString('server_url');
      print('📦 Repository: Client mode detected, server URL: $serverUrl');

      if (serverUrl == null) {
        throw Exception('Server URL not configured for client mode');
      }
      _instance = RemoteDataSource(serverUrl);
      print('✅ Repository: Created RemoteDataSource with URL: $serverUrl');
    } else {
      // Standalone or Server mode: use local data source (SQLite)
      _instance = LocalDataSource();
      print('✅ Repository: Created LocalDataSource for $appMode mode');
    }

    return _instance!;
  }

  /// Reset instance (useful when switching modes)
  static void reset() {
    _instance = null;
  }

  /// Get current app mode
  static Future<String> getAppMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('app_mode') ?? 'standalone';
  }

  /// Set app mode
  static Future<void> setAppMode(String mode) async {
    if (!['standalone', 'server', 'client'].contains(mode)) {
      throw ArgumentError('Invalid app mode: $mode. Must be standalone, server, or client');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', mode);

    // Reset instance so next call to getInstance() will use new mode
    reset();
  }
}
