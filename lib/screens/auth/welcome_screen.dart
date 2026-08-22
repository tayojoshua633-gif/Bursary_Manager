// lib/screens/auth/welcome_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../home_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _db = DatabaseHelperWrapper();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    debugPrint('🔵 WelcomeScreen initialized');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Save user data to SharedPreferences after successful login
  /// ✅ FIXED: Properly handles userId as int (not String)
  Future<void> _saveUserDataAfterLogin(Map<String, dynamic> user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Mark as logged in
      await prefs.setBool('isLoggedIn', true);
      
      // Save username (always String)
      final username = user['username']?.toString() ?? 'User';
      await prefs.setString('username', username);
      
      // Save userType (always String)
      final userType = user['userType']?.toString() ?? 'user';
      await prefs.setString('userType', userType);
      
      // ✅ IMPORTANT: Save userId as int (not String!)
      // Handle both int and String from database
      final userId = user['id'] ?? user['userId'];
      if (userId != null) {
        if (userId is int) {
          // Already an int - save directly
          await prefs.setInt('userId', userId);
        } else if (userId is String) {
          // String - parse to int
          final parsed = int.tryParse(userId);
          if (parsed != null) {
            await prefs.setInt('userId', parsed);
          } else {
            debugPrint('⚠️ Warning: Could not parse userId: $userId');
            // Fallback: save as int 1
            await prefs.setInt('userId', 1);
          }
        } else {
          debugPrint('⚠️ Warning: Unknown userId type: ${userId.runtimeType}');
          await prefs.setInt('userId', 1);
        }
      } else {
        // No userId provided - use default
        await prefs.setInt('userId', 1);
      }
      
      // Save email if available
      if (user['email'] != null) {
        await prefs.setString('email', user['email'].toString());
      }
      
      // Save schoolId if available
      final schoolId = user['schoolId'];
      if (schoolId != null) {
        if (schoolId is int) {
          await prefs.setInt('schoolId', schoolId);
        } else if (schoolId is String) {
          final parsed = int.tryParse(schoolId);
          if (parsed != null) {
            await prefs.setInt('schoolId', parsed);
          }
        }
      }
      
      debugPrint('✅ User data saved successfully');
      debugPrint('Username: $username');
      debugPrint('UserType: $userType');
      debugPrint('UserId: $userId (saved as int)');

    } catch (e) {
      debugPrint('❌ Error saving user data: $e');
      // Don't rethrow - allow login to continue even if saving fails
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      final user = await _db.authenticateUser(username, password);

      if (!mounted) return;

      if (user != null) {
        // ✅ FIXED: Save user data to SharedPreferences
        await _saveUserDataAfterLogin(user);

        if (!mounted) return;

        // Login successful - navigate to home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SidebarScaffold(
              currentUser: user,
              currentPageId: 'home',
              child: HomeScreen(
                currentUser: user,
              ),
            ),
          ),
        );
      } else {
        // Login failed
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid username or password'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withValues(alpha: 0.7),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo/Icon
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.account_balance,
                      size: 80,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  const Text(
                    'School Bursary Manager',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Welcome Back',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Login Form Card
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 24),

                            // Username Field
                            TextFormField(
                              controller: _usernameController,
                              decoration: InputDecoration(
                                labelText: 'Username',
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter username';
                                }
                                return null;
                              },
                              textInputAction: TextInputAction.next,
                            ),

                            const SizedBox(height: 16),

                            // Password Field
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter password';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _login(),
                            ),

                            const SizedBox(height: 24),

                            // Login Button
                            ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Login',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Branding Footer
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Designed by
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.design_services,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 6),
                            const Flexible(
                              child: Text(
                                'Designed by Ty Solutions Multimedia Technologies',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'www.tysolutions.com.ng',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.8),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // Divider
                        Container(
                          height: 1,
                          width: 80,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // Powered by
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bolt,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Powered by New Beginning Edu. Consult',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}