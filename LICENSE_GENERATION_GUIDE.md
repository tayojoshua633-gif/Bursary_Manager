# License Generation Guide

## Overview

The Bursary Manager supports **two methods** for generating and distributing license keys:

1. **Pre-Bound Licenses** (Recommended for remote distribution)
2. **Flexible Licenses** (Default - binds during activation)

---

## Method 1: Pre-Bound Licenses (Device-Specific)

**Use Case:** When you need to generate a license for a **specific device remotely**

### How It Works

1. **School contacts you** for a license
2. **School shares their Device ID** with you
3. **You generate a license** bound to that specific device
4. **School activates** the license on their device

### Step-by-Step Process

#### Step 1: School Gets Their Device ID

The school admin should:
1. Install the Bursary Manager app
2. Open the app (License Activation screen appears)
3. See their **Device ID** displayed prominently
4. **Copy** the Device ID (tap the copy icon)
5. **Share** the Device ID with you via email/WhatsApp/etc.

**Example Device ID:**
```
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6
```

#### Step 2: You Generate the License

1. Open Bursary Manager on **your device**
2. Access **Developer Mode** (use secret code)
3. Navigate to **License Generator**
4. Fill in school details:
   - School Name
   - School Code
   - Max Students (optional)
   - Expiry Date
5. **Enable "Device Binding"** toggle
6. **Paste the school's Device ID** into the field
7. Click **"Generate License Key"**
8. **Copy** the generated license key
9. **Share** it with the school

#### Step 3: School Activates the License

The school admin:
1. Opens the app (License Activation screen)
2. **Pastes** the license key you provided
3. Clicks **"Validate License"**
4. Reviews the license details
5. Clicks **"Activate License"**
6. ✅ Done! App is now activated

### Advantages
- ✅ **Secure**: License only works on the intended device
- ✅ **Remote**: No need to visit the school
- ✅ **Controlled**: You decide which device gets the license
- ✅ **Prevents sharing**: License cannot be shared with other schools

### Disadvantages
- ⚠️ **Device-specific**: If school changes device, you need to generate a new license
- ⚠️ **Requires coordination**: School must send you their Device ID first

---

## Method 2: Flexible Licenses (Bind-on-Activation)

**Use Case:** When you want a **flexible license** that can be activated on any device

### How It Works

1. **You generate a license** without binding to a specific device
2. **Share the license** with the school
3. **School activates** on their device
4. **License binds** to that device during activation

### Step-by-Step Process

#### Step 1: Generate Flexible License

1. Open Bursary Manager on **your device**
2. Access **Developer Mode**
3. Navigate to **License Generator**
4. Fill in school details:
   - School Name
   - School Code
   - Max Students (optional)
   - Expiry Date
5. **Leave "Device Binding" toggle OFF** (default)
6. Click **"Generate License Key"**
7. **Copy** the generated license key
8. **Share** it with the school

#### Step 2: School Activates

The school admin:
1. Installs and opens the app
2. **Pastes** the license key
3. Clicks **"Validate License"**
4. Reviews license details
5. Clicks **"Activate License"**
6. ✅ License is now **bound to this device**

### Advantages
- ✅ **Simple**: No need to collect Device ID first
- ✅ **Flexible**: Can be activated on any device
- ✅ **Quick**: Faster process for both parties
- ✅ **User-friendly**: Less technical coordination needed

### Disadvantages
- ⚠️ **First-come-first-served**: Whoever activates first gets it
- ⚠️ **Sharing risk**: License could potentially be activated by wrong person
- ⚠️ **One device only**: Once activated, cannot be moved to another device

---

## Comparison Table

| Feature | Pre-Bound License | Flexible License |
|---------|-------------------|------------------|
| **Requires Device ID** | ✅ Yes | ❌ No |
| **Remote Generation** | ✅ Yes | ✅ Yes |
| **Security** | 🔒 High | 🔒 Medium |
| **Setup Complexity** | 🔴 Medium | 🟢 Simple |
| **Device Flexibility** | ❌ Fixed | 🟡 First activation |
| **Sharing Prevention** | ✅ Strong | 🟡 Moderate |
| **Best For** | Enterprise/Remote | Quick deployment |

---

## Recommended Workflow

### For Large Organizations
**Use Pre-Bound Licenses:**
1. Request Device ID from client
2. Generate bound license
3. Verify activation on correct device

### For Trusted Clients
**Use Flexible Licenses:**
1. Generate flexible license
2. Share immediately
3. Client activates when ready

### For Trial/Demo
**Use Flexible Licenses:**
- Quick to distribute
- Easy to activate
- Time-limited (set expiry)

---

## Common Scenarios

### Scenario 1: School Has Multiple Devices

**Question:** Can one license work on multiple devices?

**Answer:** No. Each license activates on **one device only**.

**Solution:**
- Generate **separate licenses** for each device
- Use different School Codes (e.g., SMS001-PC1, SMS001-PC2)
- Or use same school details but different licenses

### Scenario 2: School Changed Devices

**Question:** Old device crashed. Can they move license to new device?

**Answer:** No. License is permanently bound to the original device.

**Solution:**
- Generate a **new license** for the new device
- Optionally: Use the new device's Device ID (pre-bound method)
- Previous license will remain inactive

### Scenario 3: License Was Activated by Mistake

**Question:** Wrong person activated the flexible license!

**Answer:** License is now bound to that device and cannot be transferred.

**Solution:**
- Generate a **new license** for the correct device
- **Lesson:** Use pre-bound licenses for sensitive deployments

### Scenario 4: Want to Pre-Activate Before Shipping

**Question:** Can I activate before sending device to school?

**Answer:** Yes!

**Solution:**
1. Install app on device before shipping
2. Get the Device ID from that device
3. Generate pre-bound license using that Device ID
4. Activate on the device
5. Ship the device with app already activated

---

## Security Best Practices

### 1. Protect Your Secret Code
- Never share the developer secret code
- Change it from the default
- Use strong, unique code

### 2. Track License Distribution
- Keep a spreadsheet of:
  - School Name
  - License Key
  - Device ID (if bound)
  - Expiry Date
  - Activation Status

### 3. Use Expiry Dates Wisely
- **Trial**: 30-90 days
- **Annual**: 365 days
- **Perpetual**: 10 years (max)

### 4. Verify Before Activation
- Always verify school details before generating
- Double-check Device ID for pre-bound licenses
- Test license generation process periodically

---

## Troubleshooting

### Error: "This license is bound to a different device"

**Cause:** License was generated with a specific Device ID that doesn't match current device.

**Fix:**
1. Verify the Device ID on current device
2. Generate a new license with correct Device ID
3. Or use flexible license (no device binding)

### Error: "This license key has already been activated"

**Cause:** License was already activated (either on this or another device).

**Fix:**
- Each license can only be activated once
- Generate a new license for this device

### Error: "Invalid license key format"

**Cause:** License key was corrupted or incorrectly copied.

**Fix:**
1. Copy the license key again carefully
2. Ensure no extra spaces or line breaks
3. Verify the entire key is copied

---

## Example: Complete Remote Setup

### Scenario
St. Mary's School in Lagos needs a license. You're in Abuja.

### Process

1. **Initial Contact**
   ```
   School: "We need a license for Bursary Manager"
   You: "Please install the app and send me your Device ID"
   ```

2. **School Sends Device ID**
   ```
   School: "Our Device ID is: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6..."
   ```

3. **You Generate License**
   - Open Developer Mode
   - School Name: `St. Mary's School`
   - School Code: `STMARY001`
   - Max Students: `500`
   - Expiry: `December 31, 2025`
   - ✅ **Enable Device Binding**
   - Device ID: `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6...`
   - Generate → Copy key

4. **Share License**
   ```
   You: "Here's your license key:
   [long license key string]

   Please activate it in the app. This license:
   - Expires: Dec 31, 2025
   - Max Students: 500
   - Valid only on your device"
   ```

5. **School Activates**
   - Paste license
   - Validate
   - Review details
   - Activate
   - ✅ **Success!**

---

## FAQ

**Q: Can I change the Device ID after generating?**
A: No. Generate a new license instead.

**Q: How many licenses can I generate?**
A: Unlimited.

**Q: Does the license expire?**
A: Yes, based on the expiry date you set (max 10 years).

**Q: Can school extend their license?**
A: Generate a new license with a later expiry date.

**Q: What happens when license expires?**
A: App will require a new valid license to continue working.

**Q: Can I deactivate a license?**
A: No. Licenses cannot be deactivated remotely. Generate new ones as needed.

---

## Summary

✅ **For maximum security**: Use Pre-Bound Licenses
✅ **For simplicity**: Use Flexible Licenses
✅ **Always**: Set appropriate expiry dates
✅ **Remember**: One license = One device activation

---

**Need Help?**
Contact: Ty Solutions Multimedia Technologies
Website: www.tysolutions.com.ng

---

**Last Updated:** December 2024
**Version:** 2.0.0
