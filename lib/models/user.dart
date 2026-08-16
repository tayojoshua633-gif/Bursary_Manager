class User {
  int? id;
  String username;
  String password;
  String userType; // 'developer', 'super_admin', 'admin', or 'bursar'
  int canChangeCredentials; // 0 = no, 1 = yes
  String createdAt;

  User({
    this.id,
    required this.username,
    required this.password,
    required this.userType,
    required this.canChangeCredentials,
    required this.createdAt,
  });

  // Convert from DB Map
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'],
      password: map['password'],
      userType: map['userType'],
      canChangeCredentials: map['canChangeCredentials'],
      createdAt: map['createdAt'],
    );
  }

  // Convert to DB Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'userType': userType,
      'canChangeCredentials': canChangeCredentials,
      'createdAt': createdAt,
    };
  }

  // Helper getters
  bool get isDeveloper => userType == 'developer';
  bool get isSuperAdmin => userType == 'super_admin';
  bool get isAdmin => userType == 'admin';
  bool get isBursar => userType == 'bursar';
  bool get canChange => canChangeCredentials == 1;

  // Display name for role
  String get roleDisplayName {
    switch (userType) {
      case 'developer':
        return 'Developer (System)';
      case 'super_admin':
        return 'Super Admin';
      case 'admin':
        return 'Admin';
      case 'bursar':
        return 'Bursar';
      default:
        return userType;
    }
  }
}
