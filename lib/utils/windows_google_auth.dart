// lib/utils/windows_google_auth.dart
//
// OAuth 2.0 loopback redirect flow for Windows/Linux/macOS desktop.
//
// Credentials live in google_auth_config.dart (gitignored) — see
// google_auth_config.example.dart for one-time setup instructions.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'google_auth_config.dart';

class WindowsGoogleAuth {
  static const _clientId = googleAuthClientId;
  static const _clientSecret = googleAuthClientSecret;

  static const _scopes = [
    'https://www.googleapis.com/auth/drive.file',     // create / upload own backups
    'https://www.googleapis.com/auth/drive.readonly', // read backups from Digital School Manager
    'email',
    'profile',
  ];

  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const _kAccessToken = 'win_google_access_token';
  static const _kRefreshToken = 'win_google_refresh_token';
  static const _kExpiry = 'win_google_token_expiry';
  static const _kEmail = 'win_google_email';

  // ── Public API ─────────────────────────────────────────────────────────────

  static Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kRefreshToken) != null &&
        prefs.getString(_kAccessToken) != null;
  }

  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEmail);
  }

  static Future<Map<String, dynamic>> signIn() async {
    try {
      return await _performOAuthFlow();
    } catch (e) {
      return {'success': false, 'message': 'Sign-in failed: $e'};
    }
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kExpiry);
    await prefs.remove(_kEmail);
  }

  /// Returns an HTTP client with a valid Bearer token attached.
  static Future<http.Client?> getAuthenticatedClient() async {
    final token = await _getValidAccessToken();
    if (token == null) return null;
    return _BearerClient(token);
  }

  // ── OAuth flow ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _performOAuthFlow() async {
    // Bind to any free port on loopback.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final redirectUri = 'http://localhost:$port';

    final verifier = _generateVerifier();
    final challenge = _generateChallenge(verifier);

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scopes.join(' '),
      'access_type': 'offline',
      'prompt': 'consent',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });

    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      await server.close();
      return {'success': false, 'message': 'Could not open browser'};
    }

    // Wait up to 5 minutes for the redirect.
    final completer = Completer<String?>();
    final sub = server.listen((req) async {
      final code = req.uri.queryParameters['code'];
      final error = req.uri.queryParameters['error'];
      req.response
        ..headers.contentType = ContentType.html
        ..write(code != null ? _kSuccessHtml : _errorHtml(error ?? 'Unknown error'));
      await req.response.close();
      if (!completer.isCompleted) completer.complete(code);
    });

    String? code;
    try {
      code = await completer.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      code = null;
    } finally {
      await sub.cancel();
      await server.close();
    }

    if (code == null) {
      return {'success': false, 'message': 'Sign-in timed out or was cancelled'};
    }

    return _exchangeCode(code, redirectUri, verifier);
  }

  static Future<Map<String, dynamic>> _exchangeCode(
    String code,
    String redirectUri,
    String verifier,
  ) async {
    final resp = await http.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );

    if (resp.statusCode != 200) {
      return {'success': false, 'message': 'Token exchange failed (${resp.statusCode})'};
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;

    if (accessToken == null) {
      return {'success': false, 'message': 'No access token received'};
    }

    final email = await _fetchEmail(accessToken);
    await _storeTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
      email: email,
    );

    return {'success': true, 'message': 'Signed in successfully', 'email': email ?? ''};
  }

  // ── Token management ───────────────────────────────────────────────────────

  static Future<String?> _getValidAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_kAccessToken);
    final refreshToken = prefs.getString(_kRefreshToken);
    if (accessToken == null || refreshToken == null) return null;

    final expiryStr = prefs.getString(_kExpiry);
    if (expiryStr != null) {
      final expiry = DateTime.tryParse(expiryStr);
      // Return current token if it has more than 60 s left.
      if (expiry != null &&
          DateTime.now().isBefore(expiry.subtract(const Duration(seconds: 60)))) {
        return accessToken;
      }
    }

    return _refresh(refreshToken);
  }

  static Future<String?> _refresh(String refreshToken) async {
    try {
      final resp = await http.post(
        Uri.https('oauth2.googleapis.com', '/token'),
        body: {
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final newToken = data['access_token'] as String?;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      if (newToken == null) return null;

      await _storeTokens(accessToken: newToken, expiresIn: expiresIn);
      return newToken;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _storeTokens({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
    String? email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, accessToken);
    if (refreshToken != null) await prefs.setString(_kRefreshToken, refreshToken);
    final expiry = DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String();
    await prefs.setString(_kExpiry, expiry);
    if (email != null) await prefs.setString(_kEmail, email);
  }

  static Future<String?> _fetchEmail(String accessToken) async {
    try {
      final resp = await http.get(
        Uri.https('www.googleapis.com', '/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (resp.statusCode == 200) {
        return (jsonDecode(resp.body) as Map<String, dynamic>)['email'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // ── PKCE helpers ───────────────────────────────────────────────────────────

  static String _generateVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _generateChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // ── Browser response pages ─────────────────────────────────────────────────

  static const _kSuccessHtml = '''
<!DOCTYPE html><html>
<head><title>Sign-in Successful</title>
<style>
  body{font-family:sans-serif;display:flex;justify-content:center;align-items:center;
       height:100vh;margin:0;background:#f0f4f8}
  .card{text-align:center;padding:40px;background:white;border-radius:12px;
        box-shadow:0 4px 20px rgba(0,0,0,.1)}
  h2{color:#1a73e8;margin-bottom:8px} p{color:#666}
</style></head>
<body><div class="card">
  <h2>&#10003; Signed In Successfully</h2>
  <p>You can close this window and return to the app.</p>
</div></body></html>
''';

  static String _errorHtml(String error) => '''
<!DOCTYPE html><html>
<head><title>Sign-in Failed</title>
<style>
  body{font-family:sans-serif;display:flex;justify-content:center;align-items:center;
       height:100vh;margin:0;background:#f0f4f8}
  .card{text-align:center;padding:40px;background:white;border-radius:12px;
        box-shadow:0 4px 20px rgba(0,0,0,.1)}
  h2{color:#d93025;margin-bottom:8px} p{color:#666}
</style></head>
<body><div class="card">
  <h2>&#10007; Sign-in Failed</h2>
  <p>$error</p><p>Close this window and try again.</p>
</div></body></html>
''';
}

// ── Bearer-token HTTP client ───────────────────────────────────────────────────

class _BearerClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();
  _BearerClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
