# Server Permission Update

## Summary

Updated the server/hosting feature from an app mode to a permission-based system. Super Admin can now grant server management access to Admin or Bursar users through the Permission Management screen.

---

## Changes Made

### 1. ✅ Removed Mode Selection After License Activation

**Problem:** After activating a license, users were forced to choose between Standalone, Server, or Client mode. This was confusing because:
- Client mode was already chosen at the Mode Selection Screen
- Server should be a permission, not a mode
- Caused unnecessary friction in the onboarding flow

**Solution:** License activation now goes directly to the login screen.

**Files Modified:**
- [license_activation_screen.dart](lib/screens/license/license_activation_screen.dart)

**Changes:**
1. Removed `_showModeSelectionDialog()` method
2. Removed `_buildModeCard()` method
3. Removed "Connect as Client" card from bottom of screen
4. Updated activation flow:
   ```dart
   // Before: Show mode selection dialog
   await _showModeSelectionDialog();

   // After: Set default mode and go to login
   final prefs = await SharedPreferences.getInstance();
   await prefs.setString('app_mode', 'standalone');

   Navigator.pushAndRemoveUntil(
     context,
     MaterialPageRoute(builder: (_) => const WelcomeScreen()),
     (route) => false,
   );
   ```
5. Applied same logic to license reactivation flow

---

### 2. ✅ Created `server_hosting` Permission Module

**Problem:** Server management was tied to `app_mode == 'server'`, meaning:
- Only devices in "server mode" could host
- Mode was set globally, not per-user
- No granular control over who can manage the server

**Solution:** Created a new permission module `server_hosting` that Super Admin can grant to specific users.

**Files Modified:**
- [database_helper.dart](lib/db/database_helper.dart)

**Changes:**
1. Added `server_hosting` to PERMISSION_MODULES list
2. Updated module count from 28 to 29
3. Positioned after `thermal_printer` (line 49)

```dart
static const List<String> PERMISSION_MODULES = [
  // ... other permissions
  'thermal_printer',         // Thermal printer settings
  'server_hosting',          // Server/hosting management ← NEW
  'backup',                  // Backup and restore
  // ... remaining permissions
];
```

**Permission Behavior:**
- **Super Admin:** Always has access (hardcoded)
- **Admin:** Can be granted access via Permission Management
- **Bursar:** Can be granted access via Permission Management

---

### 3. ✅ Updated Home Screen to Use Permission-Based Checks

**Problem:** Server badge and Server Management menu item checked for `app_mode == 'server'` or `isSuperAdmin`, not permissions.

**Solution:** Updated both to check the `server_hosting` permission.

**Files Modified:**
- [home_screen.dart](lib/screens/home_screen.dart)

**Changes:**

#### A. Added Permission Check Method
```dart
Future<bool> _hasServerHostingPermission() async {
  final userTypeRaw = widget.currentUser['userType'] ?? 'bursar';

  // Super admin always has access
  if (userTypeRaw == 'super_admin') {
    return true;
  }

  // Check permission for admin and bursar
  final db = DatabaseHelperWrapper();
  return await db.hasPermission(userTypeRaw, 'server_hosting');
}
```

#### B. Updated AppBar Server Badge
**Before:**
```dart
if (_appMode == 'server')
  Padding(/* Server badge */)
```

**After:**
```dart
FutureBuilder<bool>(
  future: _hasServerHostingPermission(),
  builder: (context, snapshot) {
    final hasPermission = snapshot.data ?? false;
    if (!hasPermission) return const SizedBox.shrink();

    return Padding(/* Server badge */);
  },
)
```

#### C. Updated Server Management Menu Item
**Before:**
```dart
if (isSuperAdmin)
  _menuCard(
    context,
    title: 'Server Management',
    /* ... */
  )
```

**After:**
```dart
_permissionMenuCard(
  context,
  module: 'server_hosting',
  title: 'Server Management',
  subtitle: 'Host for multiple clients',
  icon: Icons.dns,
  color: Colors.green,
  page: const ServerManagementScreen(),
)
```

#### D. Fixed Deprecation Warning
Changed `withOpacity` to `withValues`:
```dart
// Before
color: Colors.green.withOpacity(0.2)

// After
color: Colors.green.withValues(alpha: 0.2)
```

---

## How It Works Now

### User Flow

#### 1. **First Launch (No License)**
```
SplashScreen
    ↓
Mode Selection Screen
    ├─→ Activate License
    │       ↓
    │   License Activation Screen
    │       ↓
    │   Set app_mode = 'standalone'
    │       ↓
    │   Welcome Screen (Login)
    │       ↓
    │   HomeScreen
    │
    └─→ Connect as Client
            ↓
        Client Connection Screen
            ↓
        Client Login Screen
            ↓
        HomeScreen (client mode)
```

#### 2. **Granting Server Hosting Permission**

Super Admin can grant `server_hosting` permission to users:

1. Login as Super Admin
2. Navigate to **Permission Management**
3. Select user role (Admin or Bursar)
4. Enable **Server/Hosting Management** permission
5. Save permissions

#### 3. **Accessing Server Management**

Users with `server_hosting` permission will see:

**A. Server Badge in AppBar** (All modes except client)
- Green badge labeled "Server"
- Click to open Server Config Screen
- Shows server status, PIN, IP address
- Quick access to start/stop server

**B. Server Management Menu Item** (Dashboard)
- Visible in main menu
- Full server management interface
- Configure server settings
- View connected clients
- Manage server lifecycle

---

## Permission Matrix

| User Role | Default Access | Can Be Granted | Notes |
|-----------|----------------|----------------|-------|
| **Super Admin** | ✅ Always | N/A | Hardcoded access, cannot be removed |
| **Admin** | ❌ No | ✅ Yes | Can be granted by Super Admin |
| **Bursar** | ❌ No | ✅ Yes | Can be granted by Super Admin |

---

## Benefits

### 1. **Simplified Onboarding**
✅ No confusing mode selection after license activation
✅ Client mode clearly separated at initial screen
✅ Straight to login after activation

### 2. **Granular Access Control**
✅ Per-user permission instead of device-wide mode
✅ Super Admin controls who can host
✅ Can grant to trusted Admin or Bursar users

### 3. **Better Security**
✅ Not everyone with license can start server
✅ Permission can be revoked if needed
✅ Audit trail through permission system

### 4. **Flexibility**
✅ Multiple users on same device can have different permissions
✅ Can change permissions without reinstalling
✅ Supports organizational hierarchies

---

## Technical Details

### App Modes Still Exist

The `app_mode` setting still exists but serves a different purpose:

| Mode | Purpose | When Set |
|------|---------|----------|
| **standalone** | Normal licensed use | After license activation (default) |
| **client** | Thin client connecting to server | When user chooses "Connect as Client" |
| **server** | *(Deprecated for permission)* | No longer set automatically |

**Note:** The `server` app_mode is no longer actively used. Server functionality is now controlled by the `server_hosting` permission.

### Permission Check Flow

```dart
// 1. Check if Super Admin (bypass permission check)
if (userType == 'super_admin') return true;

// 2. Query permissions table
SELECT can_access FROM permissions
WHERE role = ? AND module = 'server_hosting'

// 3. Return result (default: false)
return can_access == 1;
```

---

## Database Schema

### Permissions Table
```sql
CREATE TABLE permissions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  role TEXT NOT NULL,           -- 'super_admin', 'admin', or 'bursar'
  module TEXT NOT NULL,         -- e.g., 'server_hosting'
  can_access INTEGER DEFAULT 0  -- 0 = no access, 1 = has access
);
```

### Default Permissions

When a new permission module is added, default permissions are created:

| Role | Module | Default Access |
|------|--------|----------------|
| super_admin | server_hosting | ✅ 1 (always granted) |
| admin | server_hosting | ❌ 0 (must be granted) |
| bursar | server_hosting | ❌ 0 (must be granted) |

**Note:** Super Admin permissions are managed programmatically and always return `true` regardless of database value.

---

## Testing Checklist

- [ ] License activation goes directly to login screen
- [ ] No mode selection dialog appears after activation
- [ ] App mode is set to 'standalone' after activation
- [ ] Super Admin sees Server badge in AppBar
- [ ] Super Admin sees Server Management in menu
- [ ] Admin WITHOUT permission does NOT see Server badge
- [ ] Admin WITHOUT permission does NOT see Server Management
- [ ] Admin WITH permission DOES see Server badge
- [ ] Admin WITH permission DOES see Server Management
- [ ] Bursar WITH permission can access server features
- [ ] Permission can be granted via Permission Management screen
- [ ] Permission can be revoked via Permission Management screen
- [ ] Server badge opens ServerConfigScreen
- [ ] Server Management menu opens ServerManagementScreen
- [ ] Client mode still works correctly
- [ ] Client mode does NOT show server badge

---

## Migration Notes

### For Existing Installations

**Automatic Migration:**
1. The `server_hosting` permission module will be automatically added to the database
2. Default permissions will be created on next database operation
3. Super Admin users will automatically have access
4. Admin and Bursar users will need to be granted permission

**Manual Steps Required:**
1. Super Admin should login
2. Navigate to Permission Management
3. Grant `server_hosting` permission to trusted users
4. Users will need to restart app or re-login to see changes

### For New Installations

No action required:
- `server_hosting` permission automatically created during database initialization
- Super Admin has access by default
- Other users can be granted access as needed

---

## Future Enhancements

Potential improvements to consider:

1. **Server Session Management**
   - Track which users started/stopped server
   - Show active server sessions
   - Auto-stop server when hosting user logs out

2. **Client Connection Approval**
   - Require server host approval for client connections
   - Whitelist/blacklist client devices
   - Show connected clients in real-time

3. **Permission Notifications**
   - Notify users when they're granted server hosting permission
   - Alert when permission is revoked
   - Show who granted the permission

4. **Audit Logging**
   - Log all server start/stop events
   - Track permission changes
   - Record client connections/disconnections

5. **Multi-Server Support**
   - Allow multiple simultaneous servers
   - Load balancing across servers
   - Server discovery improvements

---

## Breaking Changes

### ⚠️ Behavioral Changes

1. **License Activation Flow**
   - Before: License → Mode Selection → Login
   - After: License → Login
   - Impact: Faster onboarding, no mode confusion

2. **Server Access Control**
   - Before: Anyone in "server mode" could host
   - After: Only users with `server_hosting` permission
   - Impact: Better security, granular control

3. **Server Badge Visibility**
   - Before: Shown when `app_mode == 'server'`
   - After: Shown when user has `server_hosting` permission
   - Impact: Badge follows user, not device mode

### ✅ Non-Breaking Changes

- Client mode still works exactly the same
- Mode Selection Screen still functions for client connection choice
- Existing server functionality unchanged
- All API endpoints remain the same

---

## Conclusion

These changes transform server hosting from a device-wide mode into a user-specific permission, providing:

✅ **Simplified onboarding** - No confusing mode selection
✅ **Better security** - Granular access control
✅ **Flexibility** - Per-user permissions
✅ **Consistency** - Aligns with permission system

The server/hosting feature is now properly integrated into the permission management system, giving administrators fine-grained control over who can host the server for client devices.
