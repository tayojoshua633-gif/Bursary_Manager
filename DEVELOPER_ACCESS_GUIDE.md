# Developer Access Guide

## Overview
The Bursary Manager app now includes a special **Developer Access** feature that allows authorized developers to generate license keys directly from the app.

## Features
- 🔐 Secure authentication with secret code
- 🎯 Access from both License Activation and Welcome screens
- 🔑 Built-in license key generator
- ⚡ Quick and easy license generation for new devices

---

## How to Access Developer Mode

### Method 1: From License Activation Screen
1. Open the app (if not activated, you'll see the License Activation screen)
2. Scroll to the bottom
3. Click on **"Developer Access"** button
4. Enter the secret code when prompted
5. Access the License Generator

### Method 2: From Welcome/Login Screen
1. Open the app (if already activated, you'll see the Welcome screen)
2. Scroll to the bottom
3. Click on **"Developer Access"** button
4. Enter the secret code when prompted
5. Access the License Generator

---

## Default Secret Code

**Default Secret Code:** `DEV2024BURSARYMANAGER@MASTER`

⚠️ **IMPORTANT:** Change this to your own custom secret code for security!

---

## Changing the Secret Code

### Step 1: Generate a New Hash
Run the hash generator script:
```bash
dart run generate_developer_hash.dart
```

### Step 2: Enter Your Custom Code
When prompted, enter your desired secret code (or press Enter to use the default).

### Step 3: Update the Helper File
Copy the generated hash and update it in:
**File:** `lib/utils/developer_auth_helper.dart`

Replace the existing `_secretCodeHash` value:
```dart
static const String _secretCodeHash = 'YOUR_NEW_HASH_HERE';
```

### Step 4: Rebuild the App
```bash
flutter run
```

---

## Security Features

1. **Hashed Storage**: The secret code is never stored in plain text
2. **Attempt Limiting**: Maximum 3 failed attempts before access is denied
3. **Delay Protection**: Small delay between attempts to prevent brute force
4. **Dismissible Dialog**: Cannot be dismissed by tapping outside

---

## Using the License Generator

Once authenticated:

1. **Enter School Details**:
   - School Name (required)
   - School Code (required)
   - Max Students (optional - leave empty for unlimited)

2. **Select Expiry Date**:
   - Click on the date card to select
   - Default: 1 year from today
   - Maximum: 10 years

3. **Generate License**:
   - Click "Generate License Key" button
   - View the generated key and school details
   - Copy the key to clipboard
   - Generate new keys as needed

4. **Use the License**:
   - Share the license key with the school administrator
   - They can activate it on their device using the License Activation screen

---

## Troubleshooting

### "Invalid secret code" Error
- Ensure you're using the correct secret code
- Check for typos (case-sensitive)
- Verify the hash in `developer_auth_helper.dart` matches your secret code

### "Too many failed attempts" Error
- Wait a moment and try again
- Close and reopen the app if needed
- Verify you have the correct secret code

### Cannot Access License Generator
- Ensure you've successfully authenticated
- Check that the imports are correct in the screen files
- Verify the `LicenseGeneratorScreen` exists

---

## File Structure

```
lib/
├── utils/
│   └── developer_auth_helper.dart      # Authentication logic
├── widgets/
│   └── developer_auth_dialog.dart      # Authentication UI
├── screens/
│   ├── license/
│   │   ├── license_activation_screen.dart    # Has developer button
│   │   └── license_generator_screen.dart     # License generator
│   └── auth/
│       └── welcome_screen.dart              # Has developer button
generate_developer_hash.dart            # Hash generation utility
```

---

## Best Practices

1. **Keep the Secret Code Secure**:
   - Don't share it publicly
   - Don't commit it to version control
   - Change it periodically

2. **Generate Strong Codes**:
   - Use a mix of uppercase, lowercase, numbers, and symbols
   - Make it at least 16 characters long
   - Avoid common words or patterns

3. **Document Access**:
   - Keep a secure record of who has access
   - Update the code when team members change

4. **Testing**:
   - Test the authentication flow after changing the secret code
   - Verify license generation works correctly
   - Test on different devices/platforms

---

## Support

For issues or questions, contact:
- **Ty Solutions Multimedia Technologies**
- Website: www.tysolutions.com.ng

---

**Last Updated:** December 2024
**Version:** 1.0.0
