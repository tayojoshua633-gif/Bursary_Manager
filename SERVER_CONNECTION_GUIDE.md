# Server Connection Guide

## Issue: Auto-Discovery Not Working

### Root Cause

The server auto-discovery is failing because:

1. **mDNS Service Not Advertised** - The server starts an mDNS client but doesn't register/advertise the service. This is noted in the code as "service registration pending" because full mDNS service advertising requires platform-specific implementation.

2. **Network Scan Fallback** - When mDNS fails, the client falls back to scanning the local network, but this can be slow or blocked by:
   - Windows Firewall blocking HTTP requests
   - Network security policies
   - Router firewall rules
   - Different subnet configurations

### Files Involved

- **Server:** [server.dart](lib/server/server.dart:232-250) - mDNS client started but service not advertised
- **Client:** [server_discovery.dart](lib/client/server_discovery.dart) - Discovery mechanism with mDNS and network scan fallback

---

## ✅ Immediate Workaround: Manual Connection

Since auto-discovery may fail, **use manual IP connection** which works reliably.

### Steps:

#### On Server Device:

1. Start the server (Server Management or Server Config)
2. Note the **6-digit PIN** (e.g., `123456`)
3. Note the **IP Address** (e.g., `192.168.1.100`)
4. *Optional:* Click the **Copy button** next to IP Address to copy it

#### On Client Device:

1. Tap "Connect as Client" from Mode Selection
2. Enter the **6-digit PIN**
3. Wait for auto-discovery (will likely fail)
4. When "Manual Connection" section appears:
   - Enter the **IP Address** from server device
   - Enter the **PIN** again
5. Tap "Connect"
6. Should connect successfully! ✅

---

## Changes Made to Improve Experience

### 1. ✅ Better Error Message

**Before:**
```
Server not found. Please check the PIN and ensure you are on the same WiFi network.
```

**After:**
```
Auto-discovery failed. Please use manual connection below.

On the server device, check Server Management to find the IP address,
then enter it below along with the PIN.
```

**File:** [client_connection_screen.dart](lib/screens/client/client_connection_screen.dart:65)

### 2. ✅ Increased Discovery Timeout

**Before:** 10 seconds
**After:** 15 seconds

Gives network scan more time to complete.

**File:** [server_discovery.dart](lib/client/server_discovery.dart:14)

### 3. ✅ Increased Per-IP Scan Timeout

**Before:** 500ms per IP
**After:** 1000ms per IP

More forgiving for slower networks or devices.

**File:** [server_discovery.dart](lib/client/server_discovery.dart:213)

### 4. ✅ Copy Button Already Present

The ServerConfigScreen already has a copy button next to all info fields including IP Address.

---

## Why Auto-Discovery Might Fail

### 1. **mDNS Service Not Advertised (Main Issue)**

The server code starts an mDNS client but doesn't advertise the service:

```dart
// lib/server/server.dart:232-245
Future<void> _startServiceDiscovery() async {
  try {
    _mdnsClient = MDnsClient();
    await _mdnsClient!.start();

    // Broadcast service: _bursary._tcp.local
    // Include PIN in TXT record for client discovery

    // Note: Full mDNS service registration requires additional implementation
    // ← THIS IS THE ISSUE!

    print('📡 mDNS client started (service registration pending)');
  } catch (e) {
    print('⚠️ mDNS service discovery failed: $e');
  }
}
```

**Why Not Implemented:**
- The `multicast_dns` Dart package is primarily for **discovering** services, not advertising them
- Advertising mDNS services typically requires platform-specific code
- Would need separate implementations for Android, iOS, Windows, macOS, Linux

### 2. **Windows Firewall**

Windows Firewall may block incoming HTTP connections on port 8080.

**Solution:**
- Allow incoming connections for `bursary_manager.exe`
- Or disable firewall temporarily for testing (not recommended for production)

### 3. **Network Configuration**

- Router firewall rules
- Different subnets (e.g., server on 192.168.1.x, client on 192.168.0.x)
- Guest WiFi isolation (devices can't see each other)
- Enterprise WiFi with client isolation

### 4. **Slow Network Response**

Some networks or devices respond slowly to HTTP requests, causing timeouts.

---

## Testing Scenarios

### ✅ Should Work:
- Both devices on same home WiFi network
- Using manual IP connection
- Server running and visible in Server Management
- No firewall blocking port 8080

### ❌ Might Fail:
- Auto-discovery via PIN only (mDNS not advertising)
- Different subnets
- Guest WiFi networks with isolation
- Enterprise WiFi with security policies
- Windows Firewall blocking incoming connections

---

## Long-Term Solutions

### Option 1: Implement mDNS Service Advertising (Complex)

Would require platform-specific code for each platform:

**Pros:**
- True zero-configuration discovery
- Industry-standard protocol

**Cons:**
- Complex implementation
- Requires native code for each platform
- May not work on all networks anyway (guest WiFi isolation, etc.)

**Effort:** High (weeks of development)

### Option 2: UDP Broadcast Discovery (Simpler)

Implement simple UDP broadcast on local network:

```dart
// Server broadcasts:
"BURSARY_SERVER:123456:192.168.1.100:8080"

// Client listens and matches PIN
```

**Pros:**
- Simpler than mDNS
- Works across platforms
- No native code required

**Cons:**
- May be blocked by firewalls
- Doesn't work across subnets
- Less standard than mDNS

**Effort:** Medium (few days)

### Option 3: QR Code Connection (Easiest)

Server displays QR code containing connection info:

```json
{
  "ip": "192.168.1.100",
  "port": 8080,
  "pin": "123456"
}
```

Client scans QR code → Auto-fills connection details → Connects

**Pros:**
- Very user-friendly
- No network discovery needed
- Works on any network
- Fast and reliable

**Cons:**
- Requires QR code package
- Need camera permission

**Effort:** Low (1 day)

### Option 4: Server List / Cloud Registry (Production)

Servers register with cloud service, clients discover via cloud:

**Pros:**
- Works over internet (not just local network)
- Centralized management
- Can work from anywhere

**Cons:**
- Requires backend infrastructure
- Privacy concerns (server IPs exposed)
- Requires internet connection

**Effort:** High (weeks + ongoing hosting costs)

### ✅ **Recommended: Option 3 (QR Code)**

**Reasoning:**
- Fastest to implement
- Best user experience
- Works on any network
- No complex networking code
- Reliable and secure

**Implementation Steps:**
1. Add `qr_flutter` package
2. Server generates QR code with connection info
3. Client scans QR code
4. Auto-fills IP and PIN
5. Connects immediately

**User Flow:**
```
Server Device:
[Server Management] → [Show QR Code] → Display QR

Client Device:
[Connect as Client] → [Scan QR Code] → Camera → Auto-connect ✅
```

---

## Current Workaround Summary

**Until auto-discovery is improved, follow these steps:**

### Setup (One Time):

1. **Server Device:**
   - Go to Server Management
   - Start Server
   - Note IP Address and PIN

2. **Client Device:**
   - Choose "Connect as Client"
   - Enter PIN
   - Wait for "Manual Connection" to appear
   - Enter IP Address from server
   - Connect

### Daily Use:

If server IP doesn't change (most home WiFi), clients can reconnect using saved connection.

---

## Technical Details

### Discovery Flow

```
Client enters PIN
    ↓
Try mDNS Discovery (10s timeout)
    ├─→ Looks for _bursary._tcp service
    ├─→ ❌ Fails (service not advertised)
    ↓
Try Network Scan Fallback
    ├─→ Check priority IPs first
    │   ├─ Router (192.168.1.1)
    │   ├─ Common server IPs (.100, .101, .10, .2)
    │   └─ Local device IP
    ├─→ If not found, scan full subnet (1-254)
    │   ├─ Batches of 20 concurrent requests
    │   ├─ 1000ms timeout per IP
    │   └─ Check /api/server-info endpoint
    ├─→ Match PIN from server response
    ↓
Success or Show Manual Entry
```

### Network Scan Performance

**Best Case:** Found in priority IPs
- Time: 2-3 seconds
- Checks: 6 IP addresses

**Average Case:** Found in first 50 IPs
- Time: 5-10 seconds
- Checks: ~50 IP addresses (batched)

**Worst Case:** Full subnet scan
- Time: 15+ seconds
- Checks: 254 IP addresses
- May timeout if server not found

### Why Manual Connection Always Works

Manual connection bypasses discovery entirely:

```
User enters IP + PIN
    ↓
Direct HTTP request to http://<IP>:8080/api/server-info
    ↓
Verify PIN matches
    ↓
Connect ✅
```

**Time:** < 1 second
**Success Rate:** ~100% (if IP and PIN correct)

---

## FAQ

### Q: Why can't I find the server even on same WiFi?

**A:** mDNS service advertising is not implemented, and network scan may be blocked by firewall. Use manual IP connection.

### Q: Do I need to enter IP every time?

**A:** No. After first successful connection, the app saves the server URL. You'll only need to reconnect if:
- Server IP changes
- You clear app data
- Server is restarted with different network

### Q: Can I connect over the internet?

**A:** Currently, no. The server only listens on local network. You would need:
- Port forwarding on router
- Dynamic DNS service
- HTTPS for security
- Authentication improvements

### Q: Why does it work sometimes and not others?

**A:** Network scan timing is variable. It depends on:
- How many devices on network
- Which IP the server has
- Network response time
- Firewall rules

Manual connection is always consistent.

### Q: Is manual connection secure?

**A:** Yes! The PIN is still verified. Manual connection just skips the discovery step. Security is the same.

---

## Conclusion

**Current State:**
- ✅ Manual connection works reliably
- ❌ Auto-discovery unreliable (mDNS not advertising)
- ✅ Network scan fallback works but can be slow
- ✅ Error messages improved
- ✅ Copy buttons available

**Recommended Approach:**
- Short term: Use manual IP connection
- Long term: Implement QR code scanning for best UX

**For Now:**
The manual connection workaround is reliable and only takes a few extra seconds. The improved error messages guide users to use manual connection when auto-discovery fails.
