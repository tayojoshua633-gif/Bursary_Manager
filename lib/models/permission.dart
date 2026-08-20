// lib/models/permission.dart

class Permission {
  int? id;
  String role; // 'admin' or 'bursar'
  String module; // Module identifier
  bool canAccess; // Access flag

  Permission({
    this.id,
    required this.role,
    required this.module,
    required this.canAccess,
  });

  factory Permission.fromMap(Map<String, dynamic> map) {
    return Permission(
      id: map['id'],
      role: map['role'],
      module: map['module'],
      canAccess: map['canAccess'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'role': role,
      'module': module,
      'canAccess': canAccess ? 1 : 0,
    };
  }
}

/// Module display names for UI - Comprehensive list of all permission modules
class PermissionModule {
  static const Map<String, String> displayNames = {
    // Core
    'dashboard': 'Dashboard & Overview',
    'session_term': 'Session & Term Management',

    // Students - Granular permissions
    'students_view': 'View Students (List & Details)',
    'students_add': 'Register New Students',
    'students_edit': 'Edit Student Information',
    'students_batch_upload': 'Batch Upload Students',
    'students_promote': 'Promote Students to Next Class',
    'students_deactivate': 'Deactivate Students',
    'students_inactive': 'View Inactive Students',
    'students_statement': 'View Student Account Statements',

    // Classes & Arms
    'classes_arms': 'Classes & Arms Management',

    // Fee Items - Granular permissions
    'fee_items_view': 'View Fee Items',
    'fee_items_manage': 'Add/Edit Fee Items',
    'fee_class_assignment': 'Assign Fees to Classes',

    // Billing - Granular permissions
    'billing_generate': 'Generate Student Bills',
    'billing_print': 'Print Bills',

    // Payments - Granular permissions
    'payments_record': 'Record Student Payments',
    'payments_edit': 'Edit Recorded Payments',
    'payments_receipt': 'Print Payment Receipts',
    'payments_history': 'View Payment History',

    // Reports
    'reports_daily': 'Daily Financial Reports',
    'reports_debtors': 'Debtors List Report',
    'reports_termly': 'Termly Financial Report',
    'reports_overpayment': 'Overpayment Tracker Report',
    'reports_fees_balance': 'School Fees Balance Report',
    'audit_log_view': 'View Activity/Audit Log',

    // Expenses
    'expenses': 'Track & Manage Expenses',

    // System Settings
    'school_profile': 'School Profile Management',
    'license_management': 'License Management',
    'sync_key_management': 'Read-Only Sync Key Management',
    'thermal_printer': 'Thermal Printer Setup',
    'server_hosting': 'Server/Hosting Management',
    'backup': 'Backup & Restore Database',
    'data_management': 'Data Management (Clear/Delete Tools)',

    // Transportation
    'transportation_manage': 'Transportation Route Management',
    'transportation_allocate': 'Transportation Route Allocation',

    // Admin Only (cannot be toggled)
    'user_management': 'User Management (Super Admin Only)',
  };

  /// Get display name for a module
  static String getDisplayName(String module) {
    return displayNames[module] ?? module;
  }

  /// Get all module identifiers
  static List<String> getAllModules() {
    return displayNames.keys.toList();
  }
}
