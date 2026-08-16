// lib/data/remote_data_source.dart
// Remote data source that implements repository interface via HTTP API calls
// Used in client mode to communicate with server

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'repository.dart';

class RemoteDataSource implements DataRepository {
  final String baseUrl;
  String? _authToken;
  Future<void>? _tokenLoadingFuture;

  RemoteDataSource(this.baseUrl) {
    _tokenLoadingFuture = _loadToken();
  }

  // ========================================
  // TOKEN MANAGEMENT
  // ========================================

  /// Load saved auth token from SharedPreferences
  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('auth_token');
    print('🔑 Token loaded: ${_authToken != null ? "Present" : "None"}');
  }

  /// Ensure token is loaded before making requests
  Future<void> _ensureTokenLoaded() async {
    if (_tokenLoadingFuture != null) {
      await _tokenLoadingFuture;
      _tokenLoadingFuture = null;
    }
  }

  /// Save auth token to SharedPreferences
  Future<void> _saveToken(String token) async {
    _authToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  /// Clear auth token
  Future<void> _clearToken() async {
    _authToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  // ========================================
  // HTTP HELPERS
  // ========================================

  /// Make authenticated HTTP request
  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool requireAuth = true,
  }) async {
    // Ensure token is loaded before making request
    await _ensureTokenLoaded();

    final url = Uri.parse('$baseUrl$path');
    print('🌐 HTTP $method: $url');

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (requireAuth && _authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
      print('🔑 Using auth token: ${_authToken?.substring(0, 20)}...');
    } else if (requireAuth && _authToken == null) {
      print('⚠️ Auth required but no token available for $method $path');
    }

    http.Response response;

    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(url, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            url,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'PUT':
          response = await http.put(
            url,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'DELETE':
          response = await http.delete(url, headers: headers);
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      // Handle different status codes
      if (response.statusCode == 401) {
        // Token expired or invalid - clear token and throw
        await _clearToken();
        throw Exception('Authentication required. Please login again.');
      }

      if (response.statusCode >= 400) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Request failed with status ${response.statusCode}');
      }

      // Parse successful response
      if (response.body.isEmpty) {
        return null;
      }
      return jsonDecode(response.body);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // ========================================
  // AUTHENTICATION & USERS
  // ========================================

  @override
  Future<Map<String, dynamic>?> authenticateUser(String username, String password) async {
    try {
      final response = await _request(
        'POST',
        '/api/auth/login',
        body: {'username': username, 'password': password},
        requireAuth: false,
      );

      if (response['success'] == true) {
        await _saveToken(response['token']);
        return Map<String, dynamic>.from(response['user']);
      }
      return null;
    } catch (e) {
      print('Auth error: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final users = await _request('GET', '/api/users?username=$username');
    if (users is List && users.isNotEmpty) {
      return Map<String, dynamic>.from(users.first);
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final response = await _request('GET', '/api/users');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getUserById(int userId) async {
    final response = await _request('GET', '/api/users/$userId');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<bool> updateUserCredentials({
    required int userId,
    required String newUsername,
    required String newPassword,
  }) async {
    final response = await _request(
      'PUT',
      '/api/users/$userId/credentials',
      body: {'newUsername': newUsername, 'newPassword': newPassword},
    );
    return response['success'] == true;
  }

  @override
  Future<bool> resetBursarCredentials({
    required String newUsername,
    required String newPassword,
  }) async {
    final response = await _request(
      'POST',
      '/api/users/reset-bursar',
      body: {'newUsername': newUsername, 'newPassword': newPassword},
    );
    return response['success'] == true;
  }

  @override
  Future<Map<String, dynamic>?> getBursarAccount() async {
    final response = await _request('GET', '/api/users/bursar');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<int?> createUser({
    required String username,
    required String password,
    required String userType,
    required int canChangeCredentials,
  }) async {
    final response = await _request(
      'POST',
      '/api/users',
      body: {
        'username': username,
        'password': password,
        'userType': userType,
        'canChangeCredentials': canChangeCredentials,
      },
    );
    return response['id'];
  }

  @override
  Future<bool> updateUser({
    required int userId,
    required String username,
    required String password,
    required String userType,
    required int canChangeCredentials,
  }) async {
    final response = await _request(
      'PUT',
      '/api/users/$userId',
      body: {
        'username': username,
        'password': password,
        'userType': userType,
        'canChangeCredentials': canChangeCredentials,
      },
    );
    return response['success'] == true;
  }

  @override
  Future<Map<String, dynamic>> deleteUser(int userId) async {
    final response = await _request('DELETE', '/api/users/$userId');
    return Map<String, dynamic>.from(response);
  }

  @override
  Future<int> countSuperAdmins() async {
    final response = await _request('GET', '/api/users/count-super-admins');
    return response['count'];
  }

  // ========================================
  // PERMISSIONS
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getPermissionsByRole(String role) async {
    final response = await _request('GET', '/api/permissions/role/$role');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<bool> hasPermission(String role, String module) async {
    final response = await _request('GET', '/api/permissions/check/$role/$module');
    return response['hasPermission'] == true;
  }

  @override
  Future<void> setPermission(String role, String module, bool canAccess) async {
    await _request(
      'POST',
      '/api/permissions',
      body: {'role': role, 'module': module, 'canAccess': canAccess},
    );
  }

  @override
  Future<void> updateRolePermissions(String role, Map<String, bool> permissions) async {
    await _request(
      'PUT',
      '/api/permissions/role/$role',
      body: {'permissions': permissions},
    );
  }

  // ========================================
  // SESSIONS & TERMS
  // ========================================

  @override
  Future<String> getActiveTerm() async {
    final response = await _request('GET', '/api/sessions/active-term');
    return response['term'] ?? 'First Term';
  }

  @override
  Future<void> setActiveTerm(String term) async {
    await _request('POST', '/api/sessions/active-term', body: {'term': term});
  }

  @override
  Future<Map<String, dynamic>?> getActiveSession() async {
    final response = await _request('GET', '/api/sessions/active');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final response = await _request('GET', '/api/sessions');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getSessions() async {
    return getAllSessions();
  }

  @override
  Future<void> setActiveSession(int sessionId) async {
    await _request('POST', '/api/sessions/active', body: {'sessionId': sessionId});
  }

  // ========================================
  // STUDENTS
  // ========================================

  @override
  Future<int> insertStudent(Map<String, dynamic> student) async {
    final response = await _request('POST', '/api/students', body: student);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getStudents({bool includeInactive = false}) async {
    final response = await _request('GET', '/api/students?includeInactive=$includeInactive');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveStudents() async {
    print('🌐 RemoteDataSource: Fetching active students (simple) from API');
    return getStudents(includeInactive: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveStudentsWithDetails() async {
    print('🌐 RemoteDataSource: Fetching active students from API');
    print('🌐 RemoteDataSource: Base URL: $baseUrl');
    final response = await _request('GET', '/api/students/with-details');
    print('✅ RemoteDataSource: Received ${response is List ? response.length : 0} students from API');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getInactiveStudents() async {
    final response = await _request('GET', '/api/students?onlyInactive=true');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getStudentById(int id) async {
    final response = await _request('GET', '/api/students/$id');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<Map<String, dynamic>?> getStudentByIdWithDetails(int id) async {
    final response = await _request('GET', '/api/students/$id/with-details');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<int> updateStudent(int id, Map<String, dynamic> student) async {
    await _request('PUT', '/api/students/$id', body: student);
    return 1; // Success
  }

  @override
  Future<int> deleteStudent(int id) async {
    await _request('DELETE', '/api/students/$id');
    return 1; // Success
  }

  @override
  Future<int> deactivateStudent(int studentId, String leftDate, String leftReason) async {
    await _request(
      'POST',
      '/api/students/$studentId/deactivate',
      body: {'leftDate': leftDate, 'leftReason': leftReason},
    );
    return 1;
  }

  @override
  Future<int> restoreStudent(int studentId) async {
    await _request('POST', '/api/students/$studentId/restore');
    return 1;
  }

  @override
  Future<String> generateAdmissionNumber() async {
    final response = await _request('GET', '/api/students/generate-admission-number');
    return response['admissionNumber'];
  }

  // ========================================
  // PARENTS
  // ========================================

  @override
  Future<int> insertParent(Map<String, dynamic> parent) async {
    final response = await _request('POST', '/api/parents', body: parent);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getAllParents() async {
    final response = await _request('GET', '/api/parents');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getParentById(int id) async {
    try {
      final response = await _request('GET', '/api/parents/$id');
      return Map<String, dynamic>.from(response);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchParents(String query) async {
    final response = await _request('GET', '/api/parents/search?q=${Uri.encodeComponent(query)}');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> updateParent(int id, Map<String, dynamic> parent) async {
    await _request('PUT', '/api/parents/$id', body: parent);
    return 1;
  }

  @override
  Future<int> deleteParent(int id) async {
    await _request('DELETE', '/api/parents/$id');
    return 1;
  }

  // ========================================
  // CLASSES
  // ========================================

  @override
  Future<int> insertClass(Map<String, dynamic> cls) async {
    final response = await _request('POST', '/api/classes', body: cls);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getClasses() async {
    final response = await _request('GET', '/api/classes');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> updateClass(int id, Map<String, dynamic> cls) async {
    await _request('PUT', '/api/classes/$id', body: cls);
    return 1;
  }

  @override
  Future<int> deleteClass(int id) async {
    await _request('DELETE', '/api/classes/$id');
    return 1;
  }

  // ========================================
  // ARMS
  // ========================================

  @override
  Future<int> insertArm(Map<String, dynamic> arm) async {
    final response = await _request('POST', '/api/classes/arms', body: arm);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getArmsByClass(int classId) async {
    final response = await _request('GET', '/api/classes/$classId/arms');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getArms() async {
    final response = await _request('GET', '/api/classes/arms');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> updateArm(int id, Map<String, dynamic> arm) async {
    await _request('PUT', '/api/classes/arms/$id', body: arm);
    return 1;
  }

  @override
  Future<int> deleteArm(int id) async {
    await _request('DELETE', '/api/classes/arms/$id');
    return 1;
  }

  // ========================================
  // FEE ITEMS
  // ========================================

  @override
  Future<int> insertFeeItem(Map<String, dynamic> item) async {
    final response = await _request('POST', '/api/fees', body: item);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getFeeItems({String? term, String? session}) async {
    String path = '/api/fees?';
    if (term != null) path += 'term=$term&';
    if (session != null) path += 'session=$session';
    final response = await _request('GET', path);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> updateFeeItem(int id, Map<String, dynamic> item) async {
    await _request('PUT', '/api/fees/$id', body: item);
    return 1;
  }

  @override
  Future<int> deleteFeeItem(int id) async {
    await _request('DELETE', '/api/fees/$id');
    return 1;
  }

  // ========================================
  // CLASS FEES
  // ========================================

  @override
  Future<int> insertClassFee(Map<String, dynamic> classFee) async {
    final response = await _request('POST', '/api/fees/class-fees', body: classFee);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getClassFees(int classId, String term, String session, {int? armId}) async {
    String url = '/api/fees/class-fees?classId=$classId&term=$term&session=$session';
    if (armId != null) {
      url += '&armId=$armId';
    }
    final response = await _request('GET', url);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> deleteClassFee(int id) async {
    await _request('DELETE', '/api/fees/class-fees/$id');
    return 1;
  }

  @override
  Future<void> replaceClassFeesFor(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> fees, {
    int? armId,
  }) async {
    await _request(
      'POST',
      '/api/fees/class-fees/replace',
      body: {
        'classId': classId,
        'term': term,
        'session': session,
        if (armId != null) 'armId': armId,
        'fees': fees,
      },
    );
  }

  // ========================================
  // SPECIAL FEE ITEMS (for new intake students)
  // ========================================

  @override
  Future<int> insertSpecialFeeItem(Map<String, dynamic> item) async {
    final response = await _request('POST', '/api/fees/special-fee-items', body: item);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItems({String? term, String? session, bool? parentsOnly, int? parentId, bool? categoriesOnly, bool? standaloneOnly}) async {
    final params = <String>[];
    if (term != null) params.add('term=$term');
    if (session != null) params.add('session=$session');
    if (parentsOnly == true) params.add('parentsOnly=true');
    if (parentId != null) params.add('parentId=$parentId');
    if (categoriesOnly == true) params.add('categoriesOnly=true');
    if (standaloneOnly == true) params.add('standaloneOnly=true');
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    final response = await _request('GET', '/api/fees/special-fee-items$query');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemParents({String? term, String? session}) async {
    return getSpecialFeeItems(term: term, session: session, parentsOnly: true);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemCategories({String? term, String? session}) async {
    return getSpecialFeeItems(term: term, session: session, parentsOnly: true, categoriesOnly: true);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemStandalone({String? term, String? session}) async {
    return getSpecialFeeItems(term: term, session: session, standaloneOnly: true);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemChildren(int parentId, {String? term, String? session}) async {
    return getSpecialFeeItems(term: term, session: session, parentId: parentId);
  }

  @override
  Future<bool> specialFeeItemHasChildren(int itemId) async {
    final response = await _request('GET', '/api/fees/special-fee-items/$itemId/has-children');
    return response['hasChildren'] == true;
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemsHierarchy({String? term, String? session}) async {
    final params = <String>[];
    if (term != null) params.add('term=$term');
    if (session != null) params.add('session=$session');
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    final response = await _request('GET', '/api/fees/special-fee-items/hierarchy$query');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> updateSpecialFeeItem(int id, Map<String, dynamic> item) async {
    await _request('PUT', '/api/fees/special-fee-items/$id', body: item);
    return 1;
  }

  @override
  Future<int> deleteSpecialFeeItem(int id) async {
    await _request('DELETE', '/api/fees/special-fee-items/$id');
    return 1;
  }

  // ========================================
  // SPECIAL CLASS FEES (for new intake students)
  // ========================================

  @override
  Future<int> insertSpecialClassFee(Map<String, dynamic> classFee) async {
    final response = await _request('POST', '/api/fees/special-class-fees', body: classFee);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialClassFees(int classId, String term, String session, {int? armId}) async {
    String url = '/api/fees/special-class-fees?classId=$classId&term=$term&session=$session';
    if (armId != null) {
      url += '&armId=$armId';
    }
    final response = await _request('GET', url);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> deleteSpecialClassFee(int id) async {
    await _request('DELETE', '/api/fees/special-class-fees/$id');
    return 1;
  }

  @override
  Future<void> replaceSpecialClassFeesFor(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> fees, {
    int? armId,
  }) async {
    await _request(
      'POST',
      '/api/fees/special-class-fees/replace',
      body: {
        if (armId != null) 'armId': armId,
        'classId': classId,
        'term': term,
        'session': session,
        'fees': fees,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> getNewIntakeBillForClass(int classId, String term, String session, {int? armId}) async {
    String url = '/api/fees/new-intake-bill?classId=$classId&term=$term&session=$session';
    if (armId != null) {
      url += '&armId=$armId';
    }
    final response = await _request(
      'GET',
      url,
    );
    return Map<String, dynamic>.from(response);
  }

  // ========================================
  // BILLS
  // ========================================

  @override
  Future<int> insertBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown) async {
    final response = await _request(
      'POST',
      '/api/bills',
      body: {'bill': bill, 'breakdown': breakdown},
    );
    return response['id'];
  }

  @override
  Future<int> insertStudentBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown) async {
    return insertBill(bill, breakdown);
  }

  @override
  Future<Map<String, dynamic>?> getBillForStudent(int studentId, String term, String session) async {
    final response = await _request(
      'GET',
      '/api/bills/student/$studentId?term=$term&session=$session',
    );
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<List<Map<String, dynamic>>> getBillBreakdown(int billId) async {
    final response = await _request('GET', '/api/bills/$billId/breakdown');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<double> computeOutstandingForTermSession(
    int studentId, {
    required String term,
    required String session,
  }) async {
    final response = await _request(
      'GET',
      '/api/bills/outstanding/$studentId?term=$term&session=$session',
    );
    return (response['outstanding'] as num).toDouble();
  }

  @override
  Future<double> computeOutstandingBeforeTerm(
    int studentId, {
    required String term,
    required String session,
  }) async {
    final response = await _request(
      'GET',
      '/api/bills/outstanding-before/$studentId?term=$term&session=$session',
    );
    return (response['outstanding'] as num).toDouble();
  }

  @override
  Future<int> recalculatePreviousBalances() async {
    // Remote source delegates to a local SQLite operation; not applicable via API.
    throw UnimplementedError('recalculatePreviousBalances is only available on the local data source');
  }

  // ========================================
  // PAYMENTS
  // ========================================

  @override
  Future<int> insertPayment(Map<String, dynamic> payment, {String? term, String? session}) async {
    final body = Map<String, dynamic>.from(payment);
    if (term != null) body['term'] = term;
    if (session != null) body['session'] = session;

    final response = await _request('POST', '/api/payments', body: body);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getPaymentsByExactDate(String date) async {
    final response = await _request('GET', '/api/payments/by-date/$date');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getPayments(
    int studentId, {
    String? term,
    String? session,
  }) async {
    String path = '/api/payments/student/$studentId?';
    if (term != null) path += 'term=$term&';
    if (session != null) path += 'session=$session';

    final response = await _request('GET', path);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<double> computeOutstandingBalance(int studentId) async {
    final response = await _request('GET', '/api/payments/outstanding/$studentId');
    return (response['outstanding'] as num).toDouble();
  }

  @override
  Future<int> updatePayment(int paymentId, Map<String, dynamic> updates) async {
    await _request('PUT', '/api/payments/$paymentId', body: updates);
    return 1;
  }

  @override
  Future<int> deletePayment(int paymentId) async {
    await _request('DELETE', '/api/payments/$paymentId');
    return 1;
  }

  // ========================================
  // AUDIT LOG
  // ========================================
  // Payment create/update/delete already write their audit_log entry
  // server-side (the server itself runs on LocalDataSource), so
  // insertAuditLog is rarely called directly from client mode — it exists
  // to satisfy the DataRepository contract.

  @override
  Future<void> insertAuditLog({
    required String entityType,
    required int entityId,
    required String action,
    int? studentId,
    double? amount,
    Map<String, dynamic>? changes,
  }) async {
    await _request('POST', '/api/audit-log', body: {
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'studentId': studentId,
      'amount': amount,
      'changes': changes,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getAuditLog({
    String? entityType,
    int? entityId,
    DateTime? from,
    DateTime? to,
    int? userId,
  }) async {
    final query = <String>[];
    if (entityType != null) query.add('entityType=$entityType');
    if (entityId != null) query.add('entityId=$entityId');
    if (from != null) query.add('from=${from.toIso8601String()}');
    if (to != null) query.add('to=${to.toIso8601String()}');
    if (userId != null) query.add('userId=$userId');

    final path = '/api/audit-log${query.isEmpty ? '' : '?${query.join('&')}'}';
    final response = await _request('GET', path);
    return List<Map<String, dynamic>>.from(response);
  }

  // ========================================
  // EXPENSES
  // ========================================

  @override
  Future<int> insertExpense(Map<String, dynamic> expense) async {
    final response = await _request('POST', '/api/expenses', body: expense);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getAllExpenses({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
  }) async {
    final query = <String>[];
    if (term != null) query.add('term=$term');
    if (session != null) query.add('session=$session');
    if (startDate != null) query.add('startDate=$startDate');
    if (endDate != null) query.add('endDate=$endDate');

    final path = '/api/expenses${query.isEmpty ? '' : '?${query.join('&')}'}';
    final response = await _request('GET', path);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getExpenseById(int id) async {
    final response = await _request('GET', '/api/expenses/$id');
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  @override
  Future<int> updateExpense(int id, Map<String, dynamic> expense) async {
    await _request('PUT', '/api/expenses/$id', body: expense);
    return 1;
  }

  @override
  Future<int> deleteExpense(int id) async {
    await _request('DELETE', '/api/expenses/$id');
    return 1;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllExpenseCategories() async {
    final response = await _request('GET', '/api/expenses/categories');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> insertExpenseCategory(String name) async {
    final response =
        await _request('POST', '/api/expenses/categories', body: {'name': name});
    return response['id'];
  }

  @override
  Future<int> updateExpenseCategory(int id, String name) async {
    await _request('PUT', '/api/expenses/categories/$id', body: {'name': name});
    return 1;
  }

  @override
  Future<int> deleteExpenseCategory(int id) async {
    await _request('DELETE', '/api/expenses/categories/$id');
    return 1;
  }

  // ========================================
  // STAFF FINANCIAL RECORDS
  // ========================================

  @override
  Future<Map<String, dynamic>?> getStaffById(int id) async {
    final response = await _request('GET', '/api/staff-financial/staff/$id');
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  // -- Staff Loans --

  @override
  Future<int> insertStaffLoan(Map<String, dynamic> loan) async {
    final response = await _request('POST', '/api/staff-financial/loans', body: loan);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getAllStaffLoans() async {
    final response = await _request('GET', '/api/staff-financial/loans');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getStaffLoanById(int id) async {
    final response = await _request('GET', '/api/staff-financial/loans/$id');
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  @override
  Future<int> updateStaffLoan(int id, Map<String, dynamic> loan) async {
    await _request('PUT', '/api/staff-financial/loans/$id', body: loan);
    return 1;
  }

  @override
  Future<int> deleteStaffLoan(int id) async {
    await _request('DELETE', '/api/staff-financial/loans/$id');
    return 1;
  }

  // -- Staff Deductions --

  @override
  Future<int> insertStaffDeduction(Map<String, dynamic> deduction) async {
    final response =
        await _request('POST', '/api/staff-financial/deductions', body: deduction);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getStaffDeductionsByMonth(String month) async {
    final response =
        await _request('GET', '/api/staff-financial/deductions?month=$month');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> updateStaffDeduction(int id, Map<String, dynamic> data) async {
    await _request('PUT', '/api/staff-financial/deductions/$id', body: data);
    return 1;
  }

  @override
  Future<int> deleteStaffDeduction(int id) async {
    await _request('DELETE', '/api/staff-financial/deductions/$id');
    return 1;
  }

  // -- Staff Incentives --

  @override
  Future<int> insertStaffIncentive(Map<String, dynamic> incentive) async {
    final response =
        await _request('POST', '/api/staff-financial/incentives', body: incentive);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getStaffIncentivesByMonth(String month) async {
    final response =
        await _request('GET', '/api/staff-financial/incentives?month=$month');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> updateStaffIncentive(int id, Map<String, dynamic> data) async {
    await _request('PUT', '/api/staff-financial/incentives/$id', body: data);
    return 1;
  }

  @override
  Future<int> deleteStaffIncentive(int id) async {
    await _request('DELETE', '/api/staff-financial/incentives/$id');
    return 1;
  }

  // -- Staff Salary Payments --

  @override
  Future<void> toggleStaffSalaryPayment(
    int staffId,
    String month,
    bool isPaid, {
    String? paymentMethod,
    String? notes,
  }) async {
    await _request('POST', '/api/staff-financial/salary-payments/toggle', body: {
      'staffId': staffId,
      'month': month,
      'isPaid': isPaid,
      'paymentMethod': paymentMethod,
      'notes': notes,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getSalaryPaymentsByMonth(String month) async {
    final response =
        await _request('GET', '/api/staff-financial/salary-payments?month=$month');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getStaffSalaryPayment(int staffId, String month) async {
    final response = await _request(
        'GET', '/api/staff-financial/salary-payments/single?staffId=$staffId&month=$month');
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  @override
  Future<void> setLoanDeductionsAppliedForPayment(int staffId, String month, String? json) async {
    await _request('POST', '/api/staff-financial/salary-payments/loan-deductions', body: {
      'staffId': staffId,
      'month': month,
      'json': json,
    });
  }

  // -- Staff Salary Increments/History --

  @override
  Future<int> insertSalaryHistory(
    int staffId,
    double salary,
    String effectiveMonth, {
    String? reason,
  }) async {
    final response = await _request('POST', '/api/staff-financial/salary-history', body: {
      'staffId': staffId,
      'salary': salary,
      'effectiveMonth': effectiveMonth,
      'reason': reason,
    });
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getSalaryHistory(int staffId) async {
    final response =
        await _request('GET', '/api/staff-financial/salary-history/staff/$staffId');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllSalaryHistory() async {
    final response = await _request('GET', '/api/staff-financial/salary-history');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> deleteSalaryHistory(int id) async {
    await _request('DELETE', '/api/staff-financial/salary-history/$id');
    return 1;
  }

  @override
  Future<int> updateStaffSalary(int id, double salary) async {
    await _request('PUT', '/api/staff-financial/salary/$id', body: {'salary': salary});
    return 1;
  }

  // ========================================
  // FINANCIAL AGGREGATES
  // ========================================

  @override
  Future<double> getTotalBillsForTermSession({
    required String term,
    required String session,
  }) async {
    final response = await _request(
      'GET',
      '/api/reports/total-bills?term=$term&session=$session',
    );
    return (response['total'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<double> getTotalPaymentsForTermSession({
    required String term,
    required String session,
  }) async {
    final response = await _request(
      'GET',
      '/api/reports/total-payments?term=$term&session=$session',
    );
    return (response['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ========================================
  // REPORTS
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getDebtorsList({
    required int classId,
    required String term,
    required String session,
    double minPercentagePaid = 0.0,
  }) async {
    final response = await _request(
      'GET',
      '/api/reports/debtors?classId=$classId&term=$term&session=$session&minPercentagePaid=$minPercentagePaid',
    );
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>> getDebtorsSummary({
    required int classId,
    required String term,
    required String session,
  }) async {
    final response = await _request(
      'GET',
      '/api/reports/debtors/summary?classId=$classId&term=$term&session=$session',
    );
    return Map<String, dynamic>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getLastTermDebtors({
    required String term,
    required String session,
    int classId = 0,
    int armId = 0,
  }) async {
    final response = await _request(
      'GET',
      '/api/reports/last-term-debtors?term=$term&session=$session&classId=$classId&armId=$armId',
    );
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>> getFeesBalanceSummary({
    required String term,
    required String session,
    int classId = 0,
  }) async {
    final response = await _request(
      'GET',
      '/api/reports/fees-balance/summary?term=$term&session=$session&classId=$classId',
    );
    return Map<String, dynamic>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getBalancedStudentsList({
    required int classId,
    required String term,
    required String session,
  }) async {
    final response = await _request(
      'GET',
      '/api/reports/fees-balance/students?classId=$classId&term=$term&session=$session',
    );
    return List<Map<String, dynamic>>.from(response);
  }

  // ========================================
  // SCHOOL PROFILE
  // ========================================

  @override
  Future<Map<String, dynamic>?> getSchoolProfile() async {
    final response = await _request('GET', '/api/school/profile');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<int> saveSchoolProfile(Map<String, dynamic> data) async {
    final response = await _request('POST', '/api/school/profile', body: data);
    return response['id'];
  }

  // ========================================
  // GENERIC SETTINGS
  // ========================================

  @override
  Future<String?> getSetting(String key) async {
    final response = await _request('GET', '/api/settings/$key');
    return response != null ? response['value'] as String? : null;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    await _request('PUT', '/api/settings/$key', body: {'value': value});
  }

  // ========================================
  // SMS LOG
  // ========================================

  @override
  Future<int> insertSmsLog({
    int? studentId,
    required String phone,
    required String message,
    String? context,
    required String status,
    String? errorMessage,
  }) async {
    final response = await _request('POST', '/api/settings/sms-log', body: {
      'studentId': studentId,
      'phone': phone,
      'message': message,
      'context': context,
      'status': status,
      'errorMessage': errorMessage,
    });
    return response['id'];
  }

  // ========================================
  // LICENSES
  // ========================================

  @override
  Future<Map<String, dynamic>?> getActiveLicense() async {
    final response = await _request('GET', '/api/licenses/active');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<int> activateLicense({
    required String licenseKey,
    required String schoolName,
    required String schoolCode,
    required String deviceId,
    required DateTime expiryDate,
    int? maxStudents,
  }) async {
    final response = await _request(
      'POST',
      '/api/licenses/activate',
      body: {
        'licenseKey': licenseKey,
        'schoolName': schoolName,
        'schoolCode': schoolCode,
        'deviceId': deviceId,
        'expiryDate': expiryDate.toIso8601String(),
        'maxStudents': maxStudents,
      },
    );
    return response['id'];
  }

  @override
  Future<int> deactivateLicense(int licenseId) async {
    await _request('POST', '/api/licenses/$licenseId/deactivate');
    return 1;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllLicenses() async {
    final response = await _request('GET', '/api/licenses');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<bool> licenseKeyExists(String licenseKey) async {
    final response = await _request('GET', '/api/licenses/exists/$licenseKey');
    return response['exists'] == true;
  }

  @override
  Future<Map<String, dynamic>?> getLicenseByKey(String licenseKey) async {
    final response = await _request('GET', '/api/licenses/by-key/$licenseKey');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<void> reactivateLicense(int licenseId) async {
    await _request('POST', '/api/licenses/$licenseId/reactivate');
  }

  // ========================================
  // STOCK ITEMS
  // ========================================

  @override
  Future<int> insertStockItem(Map<String, dynamic> item) async {
    final response = await _request('POST', '/api/stock-items', body: item);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getStockItems({bool includeInactive = false}) async {
    final response = await _request('GET', '/api/stock-items?includeInactive=$includeInactive');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getStockItemById(int id) async {
    final response = await _request('GET', '/api/stock-items/$id');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<int> updateStockItem(int id, Map<String, dynamic> item) async {
    await _request('PUT', '/api/stock-items/$id', body: item);
    return 1;
  }

  @override
  Future<int> deactivateStockItem(int id) async {
    await _request('DELETE', '/api/stock-items/$id');
    return 1;
  }

  @override
  Future<void> deleteStockItem(int stockItemId) async {
    await _request('DELETE', '/api/stock-items/$stockItemId/permanent');
  }

  @override
  Future<void> adjustStockQuantity(
    int stockItemId,
    int newQuantity,
    String note, {
    String? createdBy,
  }) async {
    await _request('POST', '/api/stock-items/$stockItemId/adjust', body: {
      'newQuantity': newQuantity,
      'note': note,
      'createdBy': createdBy,
    });
  }

  @override
  Future<void> restockItem(
    int stockItemId, {
    required int quantityAdded,
    required String supplier,
    String? invoiceNumber,
    double? newCostPrice,
    String? notes,
    String? createdBy,
  }) async {
    await _request('POST', '/api/stock-items/$stockItemId/restock', body: {
      'quantityAdded': quantityAdded,
      'supplier': supplier,
      'invoiceNumber': invoiceNumber,
      'newCostPrice': newCostPrice,
      'notes': notes,
      'createdBy': createdBy,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getLowStockItems() async {
    final response = await _request('GET', '/api/stock-items/low-stock');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getParentItems() async {
    final response = await _request('GET', '/api/stock-items/parents');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getChildItems(int parentId) async {
    final response = await _request('GET', '/api/stock-items/parents/$parentId/children');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<bool> hasChildItems(int itemId) async {
    final response = await _request('GET', '/api/stock-items/$itemId/has-children');
    return response['hasChildren'] as bool;
  }

  @override
  Future<bool> canSetAsParent(int itemId, int? proposedParentId) async {
    final response = await _request('POST', '/api/stock-items/validate-parent', body: {
      'itemId': itemId,
      'parentItemId': proposedParentId,
    });
    return response['valid'] as bool;
  }

  // ========================================
  // SUPPLIERS
  // ========================================

  @override
  Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    final response = await _request('POST', '/api/suppliers', body: supplier);
    return response['id'];
  }

  @override
  Future<List<Map<String, dynamic>>> getSuppliers({bool includeInactive = false}) async {
    final response = await _request('GET', '/api/suppliers?includeInactive=$includeInactive');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getSupplierById(int id) async {
    try {
      final response = await _request('GET', '/api/suppliers/$id');
      return response['supplier'] as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<int> updateSupplier(int id, Map<String, dynamic> supplier) async {
    final response = await _request('PUT', '/api/suppliers/$id', body: supplier);
    return response['updated'] as int;
  }

  @override
  Future<int> deactivateSupplier(int id) async {
    final response = await _request('POST', '/api/suppliers/$id/deactivate');
    return response['updated'] as int;
  }

  @override
  Future<void> deleteSupplier(int id) async {
    await _request('DELETE', '/api/suppliers/$id');
  }

  // ========================================
  // SALES
  // ========================================

  @override
  Future<int> insertSale(Map<String, dynamic> sale, {String? createdBy}) async {
    final payload = {...sale, 'createdBy': createdBy};
    final response = await _request('POST', '/api/sales', body: payload);
    return response['id'];
  }

  @override
  Future<int> updateSalePayment(
    int saleId, {
    required double amountPaid,
    required double outstandingBalance,
    required String paymentStatus,
    required double additionalPayment,
    String? paymentMethod,
    String? note,
    String? term,
    String? session,
    String? createdBy,
    String? paymentTimestamp,
  }) async {
    final payload = {
      'amountPaid': amountPaid,
      'outstandingBalance': outstandingBalance,
      'paymentStatus': paymentStatus,
      'additionalPayment': additionalPayment,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (note != null) 'note': note,
      if (term != null) 'term': term,
      if (session != null) 'session': session,
      if (createdBy != null) 'createdBy': createdBy,
      if (paymentTimestamp != null) 'paymentTimestamp': paymentTimestamp,
    };
    final response = await _request('PUT', '/api/sales/$saleId/payment', body: payload);
    // Return payment receipt ID from response, or 0 if not provided
    return (response is Map && response['paymentReceiptId'] != null)
        ? response['paymentReceiptId'] as int
        : 0;
  }

  @override
  Future<List<Map<String, dynamic>>> getSalesByExactDate(String date) async {
    final response = await _request('GET', '/api/sales?date=$date');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllSales({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
    int? studentId,
  }) async {
    final queryParams = <String>[];
    if (term != null) queryParams.add('term=$term');
    if (session != null) queryParams.add('session=$session');
    if (startDate != null) queryParams.add('startDate=$startDate');
    if (endDate != null) queryParams.add('endDate=$endDate');
    if (studentId != null) queryParams.add('studentId=$studentId');

    final query = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final response = await _request('GET', '/api/sales$query');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getSaleById(int id) async {
    final response = await _request('GET', '/api/sales/$id');
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  @override
  Future<Map<String, double>> getSalesTotalsByMethod(String date) async {
    final response = await _request('GET', '/api/sales/totals-by-method?date=$date');
    return Map<String, double>.from(response);
  }

  @override
  Future<void> deleteSale(int saleId, {String? deletedBy}) async {
    final queryParams = <String>[];
    if (deletedBy != null) queryParams.add('deletedBy=$deletedBy');
    final query = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    await _request('DELETE', '/api/sales/$saleId$query');
  }

  @override
  Future<List<Map<String, dynamic>>> getSalesDebtors({
    String? term,
    String? session,
  }) async {
    final queryParams = <String>[];
    if (term != null) queryParams.add('term=$term');
    if (session != null) queryParams.add('session=$session');
    final query = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final response = await _request('GET', '/api/sales/debtors$query');
    return List<Map<String, dynamic>>.from(response);
  }

  // ========================================
  // STOCK MOVEMENTS
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getStockMovements(
    int stockItemId, {
    String? startDate,
    String? endDate,
  }) async {
    final queryParams = <String>[];
    if (startDate != null) queryParams.add('startDate=$startDate');
    if (endDate != null) queryParams.add('endDate=$endDate');

    final query = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final response = await _request('GET', '/api/stock-items/$stockItemId/movements$query');
    return List<Map<String, dynamic>>.from(response);
  }

  // ========================================
  // DATABASE MANAGEMENT
  // ========================================

  @override
  // ========================================
  // FEE PRIORITY (Fee Tracker)
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getFeePriorities({
    required String scope, int? classId, int? armId,
    required String term, required String session,
  }) async {
    throw UnimplementedError('Fee priorities not yet supported in remote mode');
  }

  @override
  Future<void> saveFeePriorities({
    required String scope, int? classId, int? armId,
    required String term, required String session,
    required List<Map<String, dynamic>> priorities,
  }) async {
    throw UnimplementedError('Fee priorities not yet supported in remote mode');
  }

  @override
  Future<List<Map<String, dynamic>>> getEffectiveFeePriorities({
    required int classId, int? armId,
    required String term, required String session,
  }) async {
    throw UnimplementedError('Fee priorities not yet supported in remote mode');
  }

  @override
  Future<List<Map<String, dynamic>>> getStudentsWithFeeItem({
    required int feeItemId, required String term, required String session,
    int? classId, int? armId,
  }) async {
    throw UnimplementedError('Fee tracker not yet supported in remote mode');
  }

  @override
  Future<List<Map<String, dynamic>>> getPaymentProgressionData({
    required String term, required String session,
    int? classId, int? armId,
  }) async {
    throw UnimplementedError('Fee tracker not yet supported in remote mode');
  }

  @override
  Future<List<Map<String, dynamic>>> getExtraFeeItemsForClassArm({
    required int classId, int? armId,
    required String term, required String session,
  }) async {
    throw UnimplementedError('Fee tracker not yet supported in remote mode');
  }

  // ========================================
  // TRANSPORTATION
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getTransportRoutes({bool includeInactive = false}) async {
    final response = await _request('GET', '/api/transport/routes?includeInactive=$includeInactive');
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getTransportRouteById(int id) async {
    final response = await _request('GET', '/api/transport/routes/$id');
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  @override
  Future<int> insertTransportRoute(Map<String, dynamic> data) async {
    final response = await _request('POST', '/api/transport/routes', body: data);
    return response['id'];
  }

  @override
  Future<int> updateTransportRoute(int id, Map<String, dynamic> data) async {
    await _request('PUT', '/api/transport/routes/$id', body: data);
    return 1;
  }

  @override
  Future<int> deleteTransportRoute(int id) async {
    await _request('DELETE', '/api/transport/routes/$id');
    return 1;
  }

  @override
  Future<int> countActiveAllocationsForRoute(int routeId) async {
    final response = await _request('GET', '/api/transport/routes/$routeId/allocation-count');
    return response['count'];
  }

  @override
  Future<Map<String, dynamic>?> getStudentTransportAllocation(int studentId, String term, String session) async {
    final response = await _request(
      'GET',
      '/api/transport/allocations/student/$studentId?term=${Uri.encodeQueryComponent(term)}&session=${Uri.encodeQueryComponent(session)}',
    );
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getRouteAllocationsWithDetails(String term, String session) async {
    final response = await _request(
      'GET',
      '/api/transport/allocations?term=${Uri.encodeQueryComponent(term)}&session=${Uri.encodeQueryComponent(session)}',
    );
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<int> allocateStudentToRoute({
    required int studentId,
    required int routeId,
    required String term,
    required String session,
  }) async {
    final response = await _request('POST', '/api/transport/allocations', body: {
      'studentId': studentId,
      'routeId': routeId,
      'term': term,
      'session': session,
    });
    return response['id'];
  }

  @override
  Future<int> removeStudentFromRoute(int studentId, String term, String session) async {
    final response = await _request(
      'DELETE',
      '/api/transport/allocations/student/$studentId?term=${Uri.encodeQueryComponent(term)}&session=${Uri.encodeQueryComponent(session)}',
    );
    return response['deleted'] ?? 0;
  }

  @override
  Future<void> closeAndReset() async {
    await _clearToken();
    // Client doesn't manage database, just clear credentials
  }

  @override
  Future<void> close() async {
    // No-op for remote data source
  }
}
