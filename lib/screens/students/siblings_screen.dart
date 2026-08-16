// lib/screens/students/siblings_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/navigation_helper.dart';
import 'siblings_information_screen.dart';

class SiblingsScreen extends StatefulWidget {
  const SiblingsScreen({super.key});

  @override
  State<SiblingsScreen> createState() => _SiblingsScreenState();
}

class _SiblingsScreenState extends State<SiblingsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchController = TextEditingController();

  Map<String, dynamic> _currentUser = {};
  List<Map<String, dynamic>> _siblingGroups = [];
  List<Map<String, dynamic>> _filteredGroups = [];
  bool _loading = true;

  String _activeTerm = "";

  // Color palette for sibling group differentiation
  static const List<Color> _groupColors = [
    Color(0xFF00897B), // Teal
    Color(0xFF5E35B1), // Deep Purple
    Color(0xFF1E88E5), // Blue
    Color(0xFFD81B60), // Pink
    Color(0xFF43A047), // Green
    Color(0xFFFF6F00), // Amber
    Color(0xFF3949AB), // Indigo
    Color(0xFFE53935), // Red
    Color(0xFF00ACC1), // Cyan
    Color(0xFF8E24AA), // Purple
  ];

  @override
  void initState() {
    super.initState();
    _loadSiblingGroups();
    _searchController.addListener(_filterGroups);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSiblingGroups({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    _currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };

    try {
      final db = await _db.database;

      // Get current term
      _activeTerm = await _db.getActiveTerm();

      // Find all parent phones that have more than one student (siblings)
      final siblingPhones = await db.rawQuery('''
        SELECT parentPhone, COUNT(*) as count
        FROM students
        WHERE isActive = 1
          AND parentPhone IS NOT NULL
          AND parentPhone != ''
        GROUP BY parentPhone
        HAVING COUNT(*) > 1
        ORDER BY count DESC
      ''');

      final List<Map<String, dynamic>> groups = [];

      for (final phoneRow in siblingPhones) {
        final parentPhone = phoneRow['parentPhone'] as String;

        // Get all students with this parent phone (brief details only)
        final students = await db.rawQuery('''
          SELECT
            s.id,
            s.surname,
            s.firstName,
            s.otherName,
            s.gender,
            s.parentPhone,
            s.parentName,
            c.name as className,
            a.name as armName
          FROM students s
          LEFT JOIN classes c ON s.classId = c.id
          LEFT JOIN arms a ON s.armId = a.id
          WHERE s.isActive = 1
            AND s.parentPhone = ?
          ORDER BY s.surname, s.firstName
        ''', [parentPhone]);

        if (students.length < 2) continue;

        // Get parent name from first student
        final parentName = students.first['parentName'] ?? 'Parent';

        groups.add({
          'parentPhone': parentPhone,
          'parentName': parentName,
          'students': students.map((s) => Map<String, dynamic>.from(s)).toList(),
        });
      }

      if (mounted) {
        setState(() {
          _siblingGroups = groups;
          _filteredGroups = groups;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading sibling groups: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _filterGroups() {
    final query = _searchController.text.toLowerCase().trim();

    if (query.isEmpty) {
      setState(() => _filteredGroups = _siblingGroups);
      return;
    }

    final filtered = _siblingGroups.where((group) {
      // Check if any student name matches the search
      final students = group['students'] as List<Map<String, dynamic>>;
      for (final student in students) {
        final fullName = '${student['surname']} ${student['firstName']} ${student['otherName'] ?? ''}'
            .toLowerCase()
            .trim();
        if (fullName.contains(query)) {
          return true;
        }
      }
      // Also check parent name
      final parentName = (group['parentName'] as String?)?.toLowerCase() ?? '';
      if (parentName.contains(query)) {
        return true;
      }
      return false;
    }).toList();

    setState(() => _filteredGroups = filtered);
  }

  Future<void> _openSiblingsInformation(Map<String, dynamic> group, Color groupColor) async {
    await NavigationHelper.pushWithSidebar(
      context,
      page: SiblingsInformationScreen(
        siblingGroup: group,
        groupColor: groupColor,
      ),
      currentUser: _currentUser,
      pageId: 'student_management/siblings',
    );
    // Refresh without showing the full-screen spinner so the ListView stays
    // mounted and the scroll position is preserved when returning here.
    _loadSiblingGroups(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Siblings'),
        backgroundColor: Colors.cyan.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (_activeTerm.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _activeTerm,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by student or parent name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.cyan.shade700, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Stats bar
          if (!_loading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.cyan.shade50,
              child: Row(
                children: [
                  Icon(Icons.family_restroom, size: 18, color: Colors.cyan.shade700),
                  const SizedBox(width: 8),
                  Text(
                    '${_filteredGroups.length} sibling group${_filteredGroups.length != 1 ? 's' : ''} found',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.cyan.shade700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_filteredGroups.fold<int>(0, (sum, g) => sum + (g['students'] as List).length)} students',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredGroups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchController.text.isNotEmpty
                                  ? Icons.search_off
                                  : Icons.family_restroom,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No siblings found matching "${_searchController.text}"'
                                  : 'No sibling groups found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_searchController.text.isEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Students with the same parent phone\nwill appear here',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadSiblingGroups,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredGroups.length,
                          itemBuilder: (context, index) {
                            final groupColor = _groupColors[index % _groupColors.length];
                            return _buildSiblingGroupCard(
                              _filteredGroups[index],
                              groupIndex: index,
                              groupColor: groupColor,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSiblingGroupCard(
    Map<String, dynamic> group, {
    required int groupIndex,
    required Color groupColor,
  }) {
    final students = group['students'] as List<Map<String, dynamic>>;
    final parentName = group['parentName'] as String? ?? 'Parent';

    // Get family surname from first student
    final familySurname = students.isNotEmpty
        ? (students.first['surname'] as String? ?? 'Family')
        : 'Family';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openSiblingsInformation(group, groupColor),
        child: Column(
          children: [
            // Colored header strip with group number
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [groupColor, groupColor.withValues(alpha: 0.7)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  // Group number badge
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${groupIndex + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: groupColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Family name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'The $familySurname Family',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${students.length} ${students.length == 1 ? 'child' : 'children'} • $parentName',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Arrow icon
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),

            // Brief children list (Name and Class only)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: students.map((student) => _buildBriefStudentTile(student, groupColor)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefStudentTile(Map<String, dynamic> student, Color groupColor) {
    final fullName = '${student['surname']} ${student['firstName']} ${student['otherName'] ?? ''}'.trim();
    final className = student['className'] ?? 'N/A';
    final armName = student['armName'];
    final classDisplay = armName != null && armName.isNotEmpty ? '$className - $armName' : className;
    final gender = student['gender'] ?? 'Male';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: groupColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: groupColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Gender icon
          CircleAvatar(
            radius: 16,
            backgroundColor: gender == 'Male' ? Colors.blue.shade100 : Colors.pink.shade100,
            child: Icon(
              gender == 'Male' ? Icons.boy : Icons.girl,
              size: 16,
              color: gender == 'Male' ? Colors.blue.shade700 : Colors.pink.shade700,
            ),
          ),
          const SizedBox(width: 10),
          // Name and class
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: groupColor,
                  ),
                ),
                Text(
                  classDisplay,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
