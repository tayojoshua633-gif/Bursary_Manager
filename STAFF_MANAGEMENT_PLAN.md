# Staff Management Implementation Plan

## Overview
Add a comprehensive Staff Management system to the Bursary Manager app with staff registration, office management, class allocation, office allocation, salary management, and staff viewing capabilities.

---

## 1. Database Schema

### New Tables (Database Version 23)

#### `staff` Table
```sql
CREATE TABLE staff (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  staffId TEXT UNIQUE NOT NULL,          -- Auto-generated: STF001, STF002...
  staffType TEXT NOT NULL,               -- 'Teaching Staff' or 'Non-Teaching Staff'
  surname TEXT NOT NULL,
  firstName TEXT NOT NULL,
  otherName TEXT,
  gender TEXT NOT NULL,
  dateOfBirth TEXT,
  maritalStatus TEXT,
  stateOfOrigin TEXT,
  lga TEXT,
  nationality TEXT,
  religion TEXT,
  address TEXT,
  phone TEXT,
  phone2 TEXT,
  email TEXT,
  academicInfo TEXT,                     -- JSON array of academic records
  jobExperience TEXT,                    -- JSON array of job experiences
  skills TEXT,                           -- JSON array of skills
  hobbies TEXT,                          -- JSON array of hobbies
  referee1Name TEXT,
  referee1Phone TEXT,
  referee1Relationship TEXT,
  referee1Address TEXT,
  referee2Name TEXT,
  referee2Phone TEXT,
  referee2Relationship TEXT,
  referee2Address TEXT,
  dateOfEmployment TEXT,
  salary REAL DEFAULT 0,
  photoPath TEXT,
  isActive INTEGER DEFAULT 1,
  createdAt TEXT,
  updatedAt TEXT
);
```

#### `staff_offices` Table
```sql
CREATE TABLE staff_offices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  createdAt TEXT
);
```

#### `staff_class_allocations` Table
```sql
CREATE TABLE staff_class_allocations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  staffId INTEGER NOT NULL,
  classId INTEGER NOT NULL,
  armId INTEGER NOT NULL,
  subjectsTaught TEXT,                   -- JSON array (for JSS/SSS classes)
  createdAt TEXT,
  FOREIGN KEY (staffId) REFERENCES staff(id),
  FOREIGN KEY (classId) REFERENCES classes(id),
  FOREIGN KEY (armId) REFERENCES arms(id)
);
```

#### `staff_office_allocations` Table
```sql
CREATE TABLE staff_office_allocations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  staffId INTEGER NOT NULL,
  officeId INTEGER NOT NULL,
  createdAt TEXT,
  FOREIGN KEY (staffId) REFERENCES staff(id),
  FOREIGN KEY (officeId) REFERENCES staff_offices(id)
);
```

---

## 2. Models

### File: `lib/models/staff.dart`
```dart
class Staff {
  int? id;
  String staffId;           // Auto-generated
  String staffType;         // Teaching Staff / Non-Teaching Staff
  String surname;
  String firstName;
  String? otherName;
  String gender;
  String? dateOfBirth;
  String? maritalStatus;
  String? stateOfOrigin;
  String? lga;
  String? nationality;
  String? religion;
  String? address;
  String? phone;
  String? phone2;
  String? email;
  List<AcademicRecord>? academicInfo;
  List<JobExperience>? jobExperience;
  List<String>? skills;
  List<String>? hobbies;
  String? referee1Name;
  String? referee1Phone;
  String? referee1Relationship;
  String? referee1Address;
  String? referee2Name;
  String? referee2Phone;
  String? referee2Relationship;
  String? referee2Address;
  String? dateOfEmployment;
  double salary;
  String? photoPath;
  int isActive;
  String? createdAt;
  String? updatedAt;

  // Helper getters
  String get fullName => '$surname $firstName ${otherName ?? ''}'.trim();
  bool get isTeachingStaff => staffType == 'Teaching Staff';
}

class AcademicRecord {
  String schoolName;
  String certificate;
  String yearObtained;
}

class JobExperience {
  String organization;
  String position;
  String startDate;
  String endDate;
}
```

### File: `lib/models/staff_office.dart`
```dart
class StaffOffice {
  int? id;
  String name;
  String? description;
  String? createdAt;
}
```

### File: `lib/models/staff_class_allocation.dart`
```dart
class StaffClassAllocation {
  int? id;
  int staffId;
  int classId;
  int armId;
  List<String>? subjectsTaught;
  String? createdAt;

  // Joined fields
  String? staffName;
  String? className;
  String? armName;
}
```

### File: `lib/models/staff_office_allocation.dart`
```dart
class StaffOfficeAllocation {
  int? id;
  int staffId;
  int officeId;
  String? createdAt;

  // Joined fields
  String? staffName;
  String? officeName;
}
```

---

## 3. Screen Structure

```
lib/screens/
├── menus/
│   └── staff_management_menu_screen.dart    # Main Staff Management menu
│
└── staff/
    ├── staff_setup/
    │   ├── staff_register_screen.dart       # Register new staff form
    │   ├── staff_offices_screen.dart        # CRUD for offices
    │   ├── staff_office_form_screen.dart    # Create/Edit office form
    │   ├── class_allocation_screen.dart     # Allocate teachers to classes
    │   ├── office_allocation_screen.dart    # Allocate staff to offices
    │   └── staff_salary_screen.dart         # Manage staff salaries
    │
    └── staff_view/
        ├── staff_list_screen.dart           # List staff with cards
        ├── staff_details_screen.dart        # Full staff details view
        ├── staff_edit_screen.dart           # Edit staff details
        └── staff_table_screen.dart          # Staff listing in table format
```

---

## 4. Home Screen Menu Integration

Add to `lib/screens/home_screen.dart` menu items:
- Icon: `Icons.badge` or `Icons.people_alt`
- Label: "Staff Management"
- Navigate to: `StaffManagementMenuScreen`

---

## 5. Staff Management Menu Structure

### StaffManagementMenuScreen
Two main sections:

**1. Staff Setup**
- Register Staff
- Staff Offices
- Class Allocation
- Office Allocation
- Staff Salary

**2. View Staff**
- Staff List (cards)
- Staff Listing (table)

---

## 6. Permission Modules to Add

```dart
'staff_view',
'staff_add',
'staff_edit',
'staff_offices',
'staff_class_allocation',
'staff_office_allocation',
'staff_salary',
'staff_listing',
```

---

## 7. Implementation Steps

### Phase 1: Database & Models
1. Create Staff model (`lib/models/staff.dart`)
2. Create StaffOffice model (`lib/models/staff_office.dart`)
3. Create StaffClassAllocation model (`lib/models/staff_class_allocation.dart`)
4. Create StaffOfficeAllocation model (`lib/models/staff_office_allocation.dart`)
5. Add database tables and CRUD methods to `DatabaseHelper`
6. Increment database version to 23

### Phase 2: Staff Setup Screens
7. Create `StaffManagementMenuScreen`
8. Create `StaffRegisterScreen` (with photo capture)
9. Create `StaffOfficesScreen` and `StaffOfficeFormScreen`
10. Create `ClassAllocationScreen`
11. Create `OfficeAllocationScreen`
12. Create `StaffSalaryScreen`

### Phase 3: View Staff Screens
13. Create `StaffListScreen` (cards view)
14. Create `StaffDetailsScreen`
15. Create `StaffEditScreen`
16. Create `StaffTableScreen` (table listing)

### Phase 4: Integration
17. Add Staff Management to Home Screen menu
18. Add permission modules
19. Test all functionality

---

## 8. Key Implementation Details

### Auto-Generate Staff ID
```dart
Future<String> generateStaffId() async {
  final db = await database;
  final result = await db.rawQuery('SELECT COUNT(*) as count FROM staff');
  final count = (result.first['count'] as int) + 1;
  return 'STF${count.toString().padLeft(3, '0')}';
}
```

### JSON Storage for Arrays
Use `dart:convert` for encoding/decoding:
```dart
// Store
'academicInfo': jsonEncode(academicInfo.map((e) => e.toMap()).toList())

// Retrieve
academicInfo: (jsonDecode(map['academicInfo'] ?? '[]') as List)
    .map((e) => AcademicRecord.fromMap(e)).toList()
```

### Photo Capture
Use `image_picker` package (already in pubspec.yaml):
```dart
final picker = ImagePicker();
final XFile? image = await picker.pickImage(source: ImageSource.camera);
// Save to app directory and store path
```

### Secondary Class Detection (for subjects)
```dart
bool isSecondaryClass(String className) {
  final lower = className.toLowerCase();
  return lower.contains('jss') || lower.contains('sss') ||
         lower.contains('js ') || lower.contains('ss ');
}
```

---

## 9. Files to Create

1. `lib/models/staff.dart`
2. `lib/models/staff_office.dart`
3. `lib/models/staff_class_allocation.dart`
4. `lib/models/staff_office_allocation.dart`
5. `lib/screens/menus/staff_management_menu_screen.dart`
6. `lib/screens/staff/staff_setup/staff_register_screen.dart`
7. `lib/screens/staff/staff_setup/staff_offices_screen.dart`
8. `lib/screens/staff/staff_setup/staff_office_form_screen.dart`
9. `lib/screens/staff/staff_setup/class_allocation_screen.dart`
10. `lib/screens/staff/staff_setup/office_allocation_screen.dart`
11. `lib/screens/staff/staff_setup/staff_salary_screen.dart`
12. `lib/screens/staff/staff_view/staff_list_screen.dart`
13. `lib/screens/staff/staff_view/staff_details_screen.dart`
14. `lib/screens/staff/staff_view/staff_edit_screen.dart`
15. `lib/screens/staff/staff_view/staff_table_screen.dart`

---

## 10. Files to Modify

1. `lib/db/database_helper.dart` - Add tables and CRUD methods
2. `lib/screens/home_screen.dart` - Add Staff Management menu item
3. `lib/utils/permission_helper.dart` - Add new permission modules
