# Thin Client Architecture

## Overview

The Bursary Manager supports a **thin client architecture** where client devices connect to a central server and access data based on user permissions. Clients do not have their own local database - all data operations are performed via HTTP API calls to the server.

## Architecture Components

### 1. **Server Mode**
- Runs HTTP server on port 8080
- Generates 6-digit PIN for client pairing
- Serves REST API with JWT authentication
- Uses local SQLite database for data storage
- Broadcasts availability via mDNS (network discovery)

**Key Files:**
- `lib/server/server.dart` - HTTP server core
- `lib/server/routes/` - API route handlers (auth, students, payments, classes, fees, bills, sessions, permissions, school, reports)
- `lib/server/auth_middleware.dart` - JWT authentication middleware
- `lib/screens/server/server_config_screen.dart` - Server management UI

### 2. **Client Mode**
- Connects to server via 6-digit PIN or manual IP entry
- Authenticates users via JWT
- Fetches data from server based on user role/permissions
- No local database - all operations are API calls
- Offline capabilities limited (auth token cached)

**Key Files:**
- `lib/screens/client/client_connection_screen.dart` - Server discovery & connection
- `lib/screens/client/client_login_screen.dart` - User authentication
- `lib/client/server_discovery.dart` - mDNS and manual server discovery
- `lib/data/remote_data_source.dart` - HTTP API client (implements DataRepository)

### 3. **Data Layer (Repository Pattern)**

The app uses the **Repository Pattern** to abstract data access:

```
Screen/Widget
    ↓
DatabaseHelperWrapper (transparent routing)
    ↓
RepositoryFactory (mode detection)
    ↓
┌─────────────────┬──────────────────┐
│ LocalDataSource │ RemoteDataSource │
│   (SQLite)      │   (HTTP API)     │
└─────────────────┴──────────────────┘
```

**Key Files:**
- `lib/data/repository.dart` - Abstract interface (contract)
- `lib/data/local_data_source.dart` - SQLite wrapper (standalone/server modes)
- `lib/data/remote_data_source.dart` - HTTP client (client mode)
- `lib/data/repository_factory.dart` - Mode detection & routing
- `lib/data/database_helper_wrapper.dart` - Drop-in replacement for DatabaseHelper

### 4. **Mode Detection**

The app operates in three modes, stored in `SharedPreferences` as `app_mode`:

| Mode | Database | HTTP Server | HTTP Client | Use Case |
|------|----------|-------------|-------------|----------|
| **standalone** | Local SQLite | ❌ | ❌ | Single device usage |
| **server** | Local SQLite | ✅ | ❌ | Host server for clients |
| **client** | ❌ (Remote only) | ❌ | ✅ | Thin client connecting to server |

## User Flow

### Setting up Server Mode

1. User navigates to Settings → Server Configuration
2. Click "Start Server"
3. Server generates 6-digit PIN (e.g., `123456`)
4. Server displays IP address and WiFi network
5. Clients can now connect using the PIN

### Connecting as Client

1. User launches app on client device
2. Select "Connect to Server"
3. Enter 6-digit PIN from server
4. App discovers server via mDNS or manual IP entry
5. User logs in with username/password
6. JWT token is issued and saved
7. User accesses data based on their role permissions

## Permission-Based Access

The server enforces permissions at the API level:

- **Super Admin**: Full access to all modules
- **Admin**: Configurable access per module
- **User**: Limited access based on assigned permissions

**Permission Modules** (28 total):
- dashboard, session_term, students_view, students_add, students_edit, students_batch_upload, students_promote, students_deactivate, students_inactive, classes_view, classes_manage, arms_view, arms_manage, fees_view, fees_manage, class_fees, bills_view, bills_generate, payments_view, payments_record, payments_edit, reports_daily, reports_debtors, school_profile, users_manage, permissions_manage, license_manage, backup_restore

## API Endpoints

All endpoints are prefixed with `/api/`

### Public Endpoints (no authentication)
- `GET /api/server-info` - Server information (PIN, IP, version)
- `POST /api/auth/login` - User authentication
- `POST /api/auth/logout` - User logout
- `GET /api/auth/verify` - Verify JWT token

### Protected Endpoints (require JWT)
- `/api/students/*` - Student CRUD operations
- `/api/payments/*` - Payment management
- `/api/classes/*` - Class & arm management
- `/api/fees/*` - Fee items & class fees
- `/api/bills/*` - Bill generation & queries
- `/api/sessions/*` - Academic sessions & terms
- `/api/permissions/*` - Role permissions
- `/api/school/*` - School profile
- `/api/reports/*` - Financial reports & debtors
- `/api/users/*` - User management (admin only)

## Security

### JWT Authentication
- All protected endpoints require valid JWT token
- Token includes: userId, username, userType, expiration
- Token is sent in `Authorization: Bearer <token>` header
- Invalid/expired tokens return 401 Unauthorized

### Password Hashing
- All passwords are hashed using bcrypt (cost factor: 12)
- Plain text passwords are automatically migrated on first login
- Server never stores or transmits plain text passwords

### Network Security
- CORS enabled for cross-origin requests
- Server PIN changes on each restart
- mDNS discovery limited to local network

## Testing

### Server Tests
Run server integration tests:
```bash
flutter test test/server_test.dart
```

**Test Coverage:**
- ✅ Server starts and generates PIN
- ✅ Server info endpoint responds
- ✅ Auth endpoint rejects invalid credentials
- ✅ Protected endpoints require authentication
- ✅ Server stops correctly

### Manual Testing
Use the standalone test files:
- `test_server.dart` - Test server functionality
- `test_server_ui.dart` - Test server UI screens

## Troubleshooting

### Client can't discover server
- Ensure both devices are on same WiFi network
- Check server is running and PIN is correct
- Try manual IP entry if mDNS fails
- Verify firewall allows port 8080

### Authentication fails
- Verify username/password are correct
- Check server logs for error details
- Ensure user account exists on server
- Try recreating user account

### Permission denied errors
- Check user role has required permissions
- Admin can configure permissions in Permissions Management
- Some operations require Super Admin access

## Future Enhancements

### Planned Features
- [ ] Offline mode with data sync
- [ ] Real-time data updates (WebSockets)
- [ ] Multi-school support
- [ ] Encrypted communication (HTTPS)
- [ ] Session management & token refresh
- [ ] Audit logging for all operations
- [ ] Bulk data synchronization
- [ ] Conflict resolution for concurrent edits

## Migration Guide

### Converting Existing Screens to Support Client Mode

All screens should use `DatabaseHelperWrapper` instead of `DatabaseHelper`:

```dart
// ❌ Old (local only)
final _db = DatabaseHelper();

// ✅ New (supports all modes)
final _db = DatabaseHelperWrapper();
```

The wrapper automatically routes to the correct data source based on app mode. No other changes needed!

## Notes

- Server uses SQLite database (local file)
- Client has no local database (all data from server)
- JWT tokens are cached in SharedPreferences
- Mode switching requires app restart
- Server can support multiple concurrent clients
- All API responses are JSON format
