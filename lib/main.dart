// lib/main.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'data/repository_factory.dart';
import 'data/database_helper_wrapper.dart';
import 'screens/home_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/auth/mode_selection_screen.dart';
import 'screens/client/client_connection_screen.dart';
import 'screens/client/client_login_screen.dart';
import 'utils/license_checker.dart';
import 'utils/school_sync_client.dart';
import 'utils/auto_sync_service.dart';
import 'utils/display_settings_helper.dart';
import 'utils/app_uptime.dart';
import 'utils/sound_service.dart';
import 'navigation/sidebar_state_provider.dart';
import 'navigation/sidebar_scaffold.dart';

/// Plays the popup sound whenever a dialog / bottom sheet / dropdown route
/// is pushed, without every screen having to remember to call SoundService.
class _SoundRouteObserver extends RouteObserver<ModalRoute<void>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      SoundService.instance.playPopup();
    }
    super.didPush(route, previousRoute);
  }
}

/// Global route observer — used by screens that need to refresh on every appearance.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    _SoundRouteObserver();

/// True if the pointer-down at [position] landed on an actually-interactive
/// widget (button, InkWell, list tile, switch, tab, etc.) rather than blank
/// space, a scroll gesture, or a text field.
///
/// Verified empirically (see test/click_detection_test.dart) against real
/// Material widgets — mouse-cursor identity looked reliable on paper but
/// doesn't hold up: on non-web platforms every Material widget's MouseRegion
/// cursor resolves down to the plain arrow before it ever reaches
/// RenderMouseRegion, indistinguishable from blank space. What *does* work:
/// InkWell/IconButton/ButtonStyleButton-based widgets attach a
/// `Semantics(onTap: ...)` node (RenderSemanticsAnnotations), and a raw
/// `GestureDetector(onTap: ...)` attaches a RenderSemanticsGestureHandler —
/// both are ordinary members of the normal hit-test path, no accessibility
/// mode required.
bool _isTapOnClickableWidget(Offset position, int viewId) {
  final HitTestResult result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, position, viewId);
  for (final HitTestEntry entry in result.path) {
    final Object target = entry.target;
    if (target is RenderSemanticsAnnotations && target.properties.onTap != null) {
      return true;
    }
    if (target is RenderSemanticsGestureHandler && target.onTap != null) {
      return true;
    }
  }
  return false;
}

final bool _isDesktop =
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppUptime.startTime; // capture app launch time as early as possible

  // Initialize FFI for desktop platforms (Windows, Linux, macOS)
  if (_isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugPrint(
      '✅ Database initialized for desktop platform: ${Platform.operatingSystem}',
    );
  }

  await SoundService.instance.init();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    // Intercept the window close button so we can play a sound before the
    // process actually exits — otherwise the app vanishes before it plays.
    await windowManager.setPreventClose(true);
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver, WindowListener {
  final _navigatorKey = GlobalKey<NavigatorState>();
  DateTime? _lastPausedTime;
  Duration _autoLogoutDelay = const Duration(minutes: 5); // Default value
  DisplaySettings _displaySettings = DisplaySettingsHelper.autoMode;
  DisplayMode _selectedMode = DisplayMode.auto;
  late final SidebarState _sidebarState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sidebarState = SidebarState();
    _loadDisplaySettings();
    _loadAutoLogoutSettings();
    debugPrint('🔵 App lifecycle observer added');

    SoundService.instance.playAppOpen();

    if (_isDesktop) {
      windowManager.addListener(this);
    }
  }

  // WindowListener — fires when the user clicks the window's close button.
  // We play the close sound, wait for it to finish, then actually close.
  @override
  void onWindowClose() async {
    await SoundService.instance.playAppClose();
    await Future.delayed(const Duration(milliseconds: 450));
    await windowManager.destroy();
  }

  Future<void> _loadAutoLogoutSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final minutes = prefs.getInt('auto_logout_minutes') ?? 5;
    setState(() {
      _autoLogoutDelay = Duration(minutes: minutes);
    });
    debugPrint(
      '🔵 Auto-logout delay loaded: ${minutes == 0 ? "disabled (always logged in)" : "$minutes minutes"}',
    );
  }

  Future<void> _loadDisplaySettings() async {
    final settings = await DisplaySettingsHelper.getCurrentSettings();
    setState(() {
      _displaySettings = settings;
      _selectedMode = settings.mode;
    });
  }

  void _onDisplayModeChanged(DisplayMode mode) {
    setState(() {
      _selectedMode = mode;
      _displaySettings = DisplaySettingsHelper.getSettingsByMode(mode);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    _sidebarState.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    debugPrint('🔵 App lifecycle state changed: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground
        debugPrint('🔵 App resumed (foreground)');

        // Reload auto-logout settings in case user changed them
        _loadAutoLogoutSettings();

        // Check if we should logout based on how long app was paused
        if (_lastPausedTime != null) {
          final pauseDuration = DateTime.now().difference(_lastPausedTime!);
          debugPrint(
            '🔵 App was paused for: ${pauseDuration.inSeconds} seconds',
          );

          // Skip auto-logout if set to 0 (always logged in)
          if (_autoLogoutDelay.inMinutes == 0) {
            debugPrint(
              '🔵 Auto-logout disabled (always logged in) - NOT logging out',
            );
          } else if (pauseDuration >= _autoLogoutDelay) {
            debugPrint(
              '⚠️ App was paused for more than ${_autoLogoutDelay.inMinutes} minutes - auto-logout triggered',
            );
            _performAutoLogout();
          } else {
            debugPrint(
              '🔵 App was paused briefly (${pauseDuration.inSeconds}s) - NOT logging out',
            );
          }
          _lastPausedTime = null;
        }
        break;

      case AppLifecycleState.inactive:
        // App is inactive (e.g., incoming call, notification drawer, file picker, dialogs)
        // DO NOT auto-logout here - this gets triggered by system overlays, file pickers, etc.
        debugPrint('⚠️ App inactive (system overlay/dialog) - NOT logging out');
        break;

      case AppLifecycleState.paused:
        // App is in background (screen off, home button pressed)
        // Record when app was paused, logout will happen on resume if needed
        debugPrint('⚠️ App paused - recording pause time');
        _lastPausedTime = DateTime.now();
        break;

      case AppLifecycleState.detached:
        // App is detached
        debugPrint('🔴 App detached');
        break;

      case AppLifecycleState.hidden:
        // App is hidden (iOS specific)
        debugPrint('🔴 App hidden');
        break;
    }
  }

  Future<void> _performAutoLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

      if (!isLoggedIn) {
        debugPrint('🔵 User not logged in, skipping auto-logout');
        return;
      }

      // Clear all session data
      await prefs.remove('isLoggedIn');
      await prefs.remove('username');
      await prefs.remove('userType');
      await prefs.remove('userId');
      await prefs.remove('email');
      await prefs.remove('schoolId');

      debugPrint('✅ Auto-logout completed - session cleared');

      // Navigate to welcome screen
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('❌ Error during auto-logout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SidebarStateProvider(
      state: _sidebarState,
      child: DisplaySettingsProvider(
        settings: _displaySettings,
        selectedMode: _selectedMode,
        onModeChanged: _onDisplayModeChanged,
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          navigatorObservers: [appRouteObserver],
          title: 'Bursary Manager',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
          // Plays a soft click on every tap anywhere in the app, without
          // each of the 100+ screens needing to wire it in individually.
          // Only fires for actual interactive widgets (buttons, InkWell,
          // list tiles, switches, tabs, …) — not blank space, scrolls, or
          // text fields.
          builder: (context, child) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (_isTapOnClickableWidget(event.position, event.viewId)) {
                SoundService.instance.playClick();
              }
            },
            child: child,
          ),
          home: const SplashScreen(),
        ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Stores the navigation to execute after the 5-second display.
  VoidCallback? _pendingNav;

  @override
  void initState() {
    super.initState();
    _runSplash();
  }

  // Runs the login check and the 5-second timer in parallel.
  // Navigation fires only after BOTH complete — so the splash always shows
  // for at least 5 seconds, and never navigates before the check is ready.
  Future<void> _runSplash() async {
    await Future.wait([
      Future.delayed(const Duration(seconds: 5)),
      _prepareNavigation(),
    ]);
    if (mounted) _pendingNav?.call();
  }

  Future<void> _prepareNavigation() async {
    try {
      debugPrint('🔵 SplashScreen: Starting login check...');

      final prefs = await SharedPreferences.getInstance();
      final appMode = prefs.getString('app_mode') ?? 'standalone';

      debugPrint('🔵 SplashScreen: App mode = $appMode');

      if (appMode == 'client') {
        final serverUrl = prefs.getString('server_url');
        final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

        RepositoryFactory.reset();
        DatabaseHelperWrapper().resetRepository();
        debugPrint('🔄 Repository reset for client mode on app startup');

        if (serverUrl != null && isLoggedIn) {
          debugPrint(
            '🔵 SplashScreen: Client mode - logged in, navigating to HomeScreen',
          );
          final username = prefs.getString('username') ?? 'User';
          final userType = prefs.getString('userType') ?? 'user';
          final userId = prefs.getInt('userId') ?? 1;
          final currentUser = <String, dynamic>{
            'username': username,
            'userType': userType,
            'userId': userId,
            'id': userId,
          };
          _pendingNav = () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => SidebarScaffold(
                currentUser: currentUser,
                currentPageId: 'home',
                child: HomeScreen(currentUser: currentUser),
              ),
            ),
          );
        } else if (serverUrl != null) {
          debugPrint(
            '🔵 SplashScreen: Client mode - not logged in, navigating to ClientLoginScreen',
          );
          _pendingNav = () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ClientLoginScreen(serverUrl: serverUrl, serverInfo: {}),
            ),
          );
        } else {
          debugPrint(
            '🔵 SplashScreen: Client mode - no server, navigating to ClientConnectionScreen',
          );
          _pendingNav = () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const ClientConnectionScreen(),
            ),
          );
        }
        return;
      }

      final licenseStatus = await LicenseChecker.checkLicense();
      debugPrint('🔵 SplashScreen: License valid = ${licenseStatus.isValid}');

      if (!licenseStatus.isValid) {
        debugPrint(
          '🔵 SplashScreen: No valid license, navigating to ModeSelectionScreen',
        );
        _pendingNav = () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ModeSelectionScreen()),
        );
        return;
      }

      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      debugPrint('🔵 SplashScreen: isLoggedIn = $isLoggedIn');

      if (isLoggedIn) {
        debugPrint(
          '🔵 SplashScreen: Logged in (mode: $appMode), navigating to HomeScreen',
        );
        final username = prefs.getString('username') ?? 'User';
        final userType = prefs.getString('userType') ?? 'user';
        final userId = prefs.getInt('userId') ?? 1;
        final currentUser = <String, dynamic>{
          'username': username,
          'userType': userType,
          'userId': userId,
          'id': userId,
        };

        try {
          await SchoolSyncClient.refreshAllOnLaunch();
        } catch (e) {
          debugPrint('⚠️ School sync refresh-on-launch failed: $e');
        }
        unawaited(AutoSyncService.start());

        _pendingNav = () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SidebarScaffold(
              currentUser: currentUser,
              currentPageId: 'home',
              child: HomeScreen(currentUser: currentUser),
            ),
          ),
        );
      } else {
        debugPrint(
          '🔵 SplashScreen: Not logged in, navigating to WelcomeScreen',
        );
        _pendingNav = () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
        );
      }
    } catch (e) {
      debugPrint('❌ SplashScreen error: $e');
      _pendingNav = () => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background image ───────────────────────────────────
          // image3 (portrait) for phones, image4 (landscape) for tablets
          Image.asset(
            MediaQuery.of(context).size.shortestSide >= 600
                ? 'assets/image4.jpeg'
                : 'assets/image3.jpeg',
            fit: BoxFit.cover,
          ),

          // ── Dark gradient overlay for readability ──────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000), // 40% black at top
                  Color(0xCC000000), // 80% black at bottom
                ],
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                const Spacer(),

                // App icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.shade400,
                              Colors.blue.shade700,
                            ],
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.account_balance,
                        size: 44,
                        color: Colors.white,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.receipt_long,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // App name
                const Text(
                  'Bursary Manager',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'School Fee Management System',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 36),

                // Loading indicator
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Loading…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),

                const Spacer(),

                // ── Branding footer ──────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Designed by Ty Solutions Multimedia Technologies',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Powered by New Beginning Edu. Consult',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Divider(
                        color: Colors.white.withValues(alpha: 0.2),
                        height: 1,
                      ),
                      const SizedBox(height: 10),
                      _brandRow(
                        Icons.email_outlined,
                        'support@tysolutions.com.ng',
                      ),
                      const SizedBox(height: 4),
                      _brandRow(
                        Icons.phone_outlined,
                        '+234 806 305 9940  ·  +234 901 669 5102',
                      ),
                      const SizedBox(height: 4),
                      _brandRow(
                        Icons.language_outlined,
                        'www.tysolutions.com/ng/dsm',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandRow(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
