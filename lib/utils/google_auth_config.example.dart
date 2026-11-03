// lib/utils/google_auth_config.example.dart
//
// Template for the Windows/Linux/macOS desktop Google OAuth credentials.
//
// SETUP (one-time):
//   1. Go to https://console.cloud.google.com/
//   2. Create a project → Enable "Google Drive API"
//   3. APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID
//   4. Application type: "Desktop app" → Download the JSON
//   5. Copy this file to google_auth_config.dart (gitignored) and paste the
//      client_id / client_secret from the JSON into the constants below.
//   6. In "OAuth consent screen", add the test user email (or publish the app)

const String googleAuthClientId = 'YOUR_CLIENT_ID.apps.googleusercontent.com';
const String googleAuthClientSecret = 'YOUR_CLIENT_SECRET';
