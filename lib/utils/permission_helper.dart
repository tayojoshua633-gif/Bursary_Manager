// lib/utils/permission_helper.dart
import '../data/database_helper_wrapper.dart';

class PermissionHelper {
  static final _db = DatabaseHelperWrapper();

  // Cache permissions for performance
  static final Map<String, Map<String, bool>> _permissionCache = {};

  /// Check if user has permission to access a module
  static Future<bool> hasPermission(
    Map<String, dynamic> currentUser,
    String module,
  ) async {
    final userType = currentUser['userType'] as String;

    // Developer role has unrestricted access to everything (superior to super_admin)
    if (userType == 'developer') return true;

    // Super admin always has access (except user_management which is developer-only)
    if (userType == 'super_admin') return true;

    // User management is developer-only (superior to super_admin)
    if (module == 'user_management') return false;

    // Check cache first
    if (_permissionCache.containsKey(userType) &&
        _permissionCache[userType]!.containsKey(module)) {
      return _permissionCache[userType]![module]!;
    }

    // Query database
    final hasAccess = await _db.hasPermission(userType, module);

    // Cache result
    if (!_permissionCache.containsKey(userType)) {
      _permissionCache[userType] = {};
    }
    _permissionCache[userType]![module] = hasAccess;

    return hasAccess;
  }

  /// Clear permission cache (call when permissions are updated)
  static void clearCache() {
    _permissionCache.clear();
  }

  /// Load all permissions for a role into cache
  static Future<void> loadPermissionsForRole(String role) async {
    final permissions = await _db.getPermissionsByRole(role);
    _permissionCache[role] = {};
    for (var perm in permissions) {
      _permissionCache[role]![perm['module']] = perm['canAccess'] == 1;
    }
  }

  /// Clear cache for a specific role
  static void clearCacheForRole(String role) {
    _permissionCache.remove(role);
  }
}
