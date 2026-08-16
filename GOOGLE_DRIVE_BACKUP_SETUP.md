# Google Drive Backup Integration Setup Guide

This guide will help you set up Google Drive backup functionality for the Bursary Manager app.

## Step 1: Add Dependencies to pubspec.yaml

Add these packages to your `pubspec.yaml` file under `dependencies`:

```yaml
dependencies:
  # ... existing dependencies ...

  # Google Drive Backup
  google_sign_in: ^6.2.1
  googleapis: ^13.2.0
  http: ^1.2.0
```

Then run:
```bash
flutter pub get
```

## Step 2: Google Cloud Console Setup

### 2.1 Create/Configure Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Name it something like "Bursary Manager"

### 2.2 Enable Google Drive API

1. In the Google Cloud Console, go to **APIs & Services** > **Library**
2. Search for "Google Drive API"
3. Click on it and press **Enable**

### 2.3 Create OAuth 2.0 Credentials

#### For Android:

1. Go to **APIs & Services** > **Credentials**
2. Click **Create Credentials** > **OAuth client ID**
3. Select **Android** as application type
4. For Package Name, enter: `com.example.bursary_manager` (or your actual package name from `android/app/build.gradle`)
5. For SHA-1 fingerprint, you need to get it:

**Get SHA-1 Fingerprint:**

```bash
# For debug keystore (development)
cd android
./gradlew signingReport

# Or use keytool directly:
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Copy the SHA-1 fingerprint and paste it in the Cloud Console.

6. Click **Create**
7. Download the `google-services.json` file (optional, for Firebase)

#### For Windows (Desktop):

1. Go to **APIs & Services** > **Credentials**
2. Click **Create Credentials** > **OAuth client ID**
3. Select **Desktop app** as application type
4. Name it "Bursary Manager Windows"
5. Click **Create**
6. You'll get a **Client ID** - save this

### 2.4 Configure OAuth Consent Screen

1. Go to **APIs & Services** > **OAuth consent screen**
2. Select **External** user type (unless you have Google Workspace)
3. Fill in:
   - App name: Bursary Manager
   - User support email: your email
   - Developer contact: your email
4. Add scopes:
   - `https://www.googleapis.com/auth/drive.file`
5. Add test users (your email) if in testing mode
6. Save and continue

## Step 3: Configure Android App

### 3.1 Update AndroidManifest.xml

Edit `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
    <application ...>
        <!-- Add this inside <application> tag -->
        <meta-data
            android:name="com.google.android.gms.version"
            android:value="@integer/google_play_services_version" />

        <!-- Your existing activities -->
    </application>
</manifest>
```

### 3.2 Update build.gradle (if needed)

Edit `android/app/build.gradle`:

```gradle
dependencies {
    // Make sure you have Google Play Services
    implementation 'com.google.android.gms:play-services-auth:20.7.0'
}
```

## Step 4: Configure Windows App (Desktop)

For Windows desktop, the Google Sign-In works through a web browser flow. No additional configuration needed beyond the OAuth credentials from Step 2.3.

## Step 5: Update Your Code

The helper file has been created at `lib/utils/google_drive_backup_helper.dart`.

### 5.1 Add Google Drive Button to Backup Screen

Update your `backup_screen.dart` to include Google Drive functionality:

```dart
// Add import
import '../../utils/google_drive_backup_helper.dart';

// Add state variables
bool _isSignedInToGoogle = false;
String? _googleUserEmail;

// Add in initState
@override
void initState() {
  super.initState();
  // ... existing code ...
  _checkGoogleSignIn();
}

// Add method to check sign-in status
Future<void> _checkGoogleSignIn() async {
  final isSignedIn = await GoogleDriveBackupHelper.isSignedIn();
  final email = GoogleDriveBackupHelper.getCurrentUserEmail();
  if (mounted) {
    setState(() {
      _isSignedInToGoogle = isSignedIn;
      _googleUserEmail = email;
    });
  }
}

// Add method to backup to Google Drive
Future<void> _backupToGoogleDrive() async {
  setState(() => _isLoading = true);

  // First create a local backup
  final backupResult = await DBBackupHelper.backupDatabase();

  if (!backupResult['success']) {
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(backupResult['message']),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  // Upload to Google Drive
  final uploadResult = await GoogleDriveBackupHelper.uploadBackupToDrive(
    backupResult['filePath'],
  );

  setState(() => _isLoading = false);

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(uploadResult['message']),
        backgroundColor: uploadResult['success'] ? Colors.green : Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  if (uploadResult['success']) {
    // Record backup
    await BackupReminderHelper.recordBackup();
  }
}

// Add button in your UI
ElevatedButton.icon(
  onPressed: _isSignedInToGoogle ? _backupToGoogleDrive : _signInToGoogle,
  icon: Icon(_isSignedInToGoogle ? Icons.cloud_upload : Icons.login),
  label: Text(_isSignedInToGoogle ? 'Backup to Google Drive' : 'Sign in to Google'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.blue,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.all(16),
  ),
),
```

## Step 6: Testing

### For Android:
1. Build and run on a physical device (Google Sign-In doesn't work well on emulators)
2. Make sure the device has Google Play Services installed
3. The device should have a Google account signed in

### For Windows:
1. Run the app
2. When you click sign in, a browser will open for authentication
3. Sign in with your Google account
4. Grant permissions
5. The app will receive the authentication token

## Step 7: Common Issues & Solutions

### Issue: "Sign-in failed" or "Invalid client ID"
**Solution**:
- Make sure your package name matches in Google Cloud Console
- Verify SHA-1 fingerprint is correct
- Check that Google Drive API is enabled

### Issue: "Access denied" or "Permission denied"
**Solution**:
- Make sure you added the correct scope in OAuth consent screen
- Add yourself as a test user if app is in testing mode
- Check that the app has the correct permissions in AndroidManifest.xml

### Issue: Google Sign-In doesn't open
**Solution**:
- Verify Google Play Services is installed (Android)
- Check internet connection
- Make sure OAuth client ID is configured for the correct platform

## Step 8: Production Deployment

Before deploying to production:

1. **Get a release keystore SHA-1**:
   ```bash
   keytool -list -v -keystore your-release-keystore.jks -alias your-alias
   ```

2. **Add release SHA-1 to Google Cloud Console**:
   - Add another OAuth client ID with the release SHA-1
   - Or add the release SHA-1 to your existing Android OAuth client

3. **Move OAuth consent screen to production**:
   - Complete the OAuth consent screen verification process
   - Submit for Google verification if needed

## Features Available

Once configured, users can:
- ✅ Sign in with Google account
- ✅ Upload backups to Google Drive (stored in "Bursary Backups" folder)
- ✅ List backups from Google Drive
- ✅ Download backups from Google Drive
- ✅ Delete backups from Google Drive
- ✅ Automatic folder organization in Drive

## Security Notes

- The app only requests `drive.file` scope (can only access files it created)
- Users control access through Google account permissions
- Authentication tokens are managed by the Google Sign-In SDK
- No credentials are stored in the app

## Support

For issues with Google Drive integration:
1. Check the Google Cloud Console logs
2. Verify all setup steps are complete
3. Test on a physical device with Google Play Services
4. Check app permissions in device settings
