# Default User Accounts

This document lists all default user accounts in the Bursary Manager application.

## User Accounts Summary

| Username | Password | Role | Editable | Purpose |
|----------|----------|------|----------|---------|
| **developer** | `dev2024bursarymanager@master` | Developer (System) | ❌ No | Fixed developer access (superior to all roles) |
| **superadmin** | `12345` | Super Admin | ✅ Yes | Default super admin account (editable) |
| **admin** | `12345` | Admin | ✅ Yes | Default admin account (editable) |
| **bursar** | `12345` | Bursar | ✅ Yes | Default bursar account (editable) |

---

## Account Details

### 1. Developer (System Account)
- **Username:** `developer`
- **Password:** `dev2024bursarymanager@master`
- **Role:** Developer (System)
- **Can Change Credentials:** ❌ No (Fixed account)
- **Purpose:** System-level developer access account that cannot be edited or deleted
- **Permissions:** **Unrestricted access** to all features including:
  - ✅ Full user management (can create/edit/delete superadmin accounts)
  - ✅ All system settings and configurations
  - ✅ All application features
- **Special Privileges:**
  - Superior to Super Admin role
  - Can manage Super Admin accounts
  - Cannot be edited or deleted through the UI
  - Only account with absolute control

### 2. Super Admin
- **Username:** `superadmin`
- **Password:** `12345`
- **Role:** Super Admin
- **Can Change Credentials:** ✅ Yes
- **Purpose:** Default super admin account for primary administrators
- **Permissions:** Full access to all features including user management
- **Note:** Password can be changed after first login

### 3. Admin
- **Username:** `admin`
- **Password:** `12345`
- **Role:** Admin
- **Can Change Credentials:** ✅ Yes
- **Purpose:** Default admin account for administrative staff
- **Permissions:** Full access except user management
- **Note:** Password can be changed after first login

### 4. Bursar
- **Username:** `bursar`
- **Password:** `12345`
- **Role:** Bursar
- **Can Change Credentials:** ✅ Yes
- **Purpose:** Default bursar account for financial operations
- **Permissions:** Access to financial operations (billing, payments, reports)
- **Note:** Password can be changed after first login

---

## Role Hierarchy

```
Developer (System)
    ↓ (superior to)
Super Admin
    ↓ (superior to)
Admin
    ↓ (superior to)
Bursar
```

### Permission Levels

#### Developer (System) - Level 4 (Highest)
- ✅ **Unrestricted access** to everything
- ✅ Can create, edit, and delete **any user** including Super Admins
- ✅ Full user management capabilities
- ✅ All dashboard and system features
- ✅ Cannot be edited or deleted
- ⚠️ **Use only for system administration and emergency access**

#### Super Admin - Level 3
- ✅ All dashboard and overview features
- ✅ Session & term management
- ✅ Student management (view, add, edit, batch upload, promote, deactivate)
- ✅ Class and arm management
- ✅ Fee items management
- ✅ Billing operations
- ✅ Payment recording and editing
- ✅ All reports (daily, debtors, termly, overpayment)
- ✅ Expense tracking
- ✅ School profile management
- ✅ License management
- ✅ Thermal printer setup
- ✅ Backup & restore
- ✅ User management (can manage Admin and Bursar accounts)
- ❌ Cannot create or edit Developer accounts
- ❌ Cannot delete Developer accounts

#### Admin - Level 2
- ✅ All dashboard and overview features
- ✅ Session & term management
- ✅ Student management (view, add, edit, batch upload, promote, deactivate)
- ✅ Class and arm management
- ✅ Fee items management
- ✅ Billing operations
- ✅ Payment recording and editing
- ✅ All reports (daily, debtors, termly, overpayment)
- ✅ Expense tracking
- ✅ School profile management
- ✅ License management
- ✅ Thermal printer setup
- ✅ Backup & restore
- ❌ User management (not available)

#### Bursar - Level 1
- ✅ Dashboard & overview
- ✅ View students and student statements
- ✅ Billing operations (generate and print bills)
- ✅ Payment recording and receipt printing
- ✅ Payment history
- ✅ All financial reports (daily, debtors, termly, overpayment)
- ✅ Expense tracking
- ❌ Student management (add, edit, promote, deactivate)
- ❌ Class and fee management
- ❌ System settings and administration
- ❌ User management

---

## Security Notes

### Password Security
- All passwords are hashed using **bcrypt** before storage
- Plain text passwords are never stored in the database
- Password verification is done through secure hash comparison

### Developer Account
- **Cannot be edited or deleted** through the UI
- **Superior to Super Admin** - can manage Super Admin accounts
- Provides guaranteed system access for developers/support
- Should only be used for:
  - Technical support
  - Emergency access
  - System administration
  - Critical troubleshooting
- **⚠️ CRITICAL:** Change the password in production deployments for security

### Recommended Actions After First Login

1. **Immediately change all default passwords** (`12345`)
2. **Change the developer account password** for production security
3. **Keep the developer credentials extremely secure** (not to be shared)
4. **Create individual user accounts** for each staff member
5. **Disable or change credentials** for unused default accounts
6. **Document any custom user accounts** created
7. **Use the developer account sparingly** - prefer using Super Admin for day-to-day administration

---

## How to Change Passwords

1. Log in with your current credentials
2. Navigate to **Settings** → **Change Credentials**
3. Enter current password
4. Enter new password (twice for confirmation)
5. Save changes

**Note:** The `developer` account cannot change its credentials through the UI.

---

## Migration Details

### For New Installations
All four user accounts will be created automatically during first-time setup.

### For Existing Installations
When upgrading to version 14:
- Old **developeradmin** account will be removed (if exists)
- New **developer** account will be created with corrected credentials
- **admin** account will be added if it doesn't exist
- **superadmin** password will be updated to `12345` and made editable
- **bursar** password will be updated to `12345`

---

## Database Version
- **Current Version:** 14
- **Migration:** v14 - Updated default user accounts with Developer (System) role

---

## Frequently Asked Questions

### Q: What's the difference between Developer and Super Admin?
**A:** Developer is superior to Super Admin and can manage Super Admin accounts. It's meant for system-level access, not day-to-day administration.

### Q: Can Super Admin delete the Developer account?
**A:** No. The Developer account cannot be edited or deleted by anyone, including Super Admins.

### Q: When should I use the Developer account?
**A:** Only for system administration, emergency access, or when you need to manage Super Admin accounts. For normal operations, use a Super Admin account.

### Q: Can I change the Developer password?
**A:** The Developer account's `canChangeCredentials` is set to 0, so it cannot change its password through the Change Credentials screen. To change it, you must directly modify the database or update the seeding code.

### Q: What happens if I forget the Developer password?
**A:** You can reset it by modifying the database directly or by reinstalling the application (which will recreate all default accounts).

---

*Last Updated: December 26, 2024*
