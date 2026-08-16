// lib/screens/parents/all_parents_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/parent.dart';
import '../../utils/navigation_helper.dart';
import 'parent_form_screen.dart';
import 'parent_details_screen.dart';

class AllParentsScreen extends StatefulWidget {
  const AllParentsScreen({super.key});

  @override
  State<AllParentsScreen> createState() => _AllParentsScreenState();
}

class _AllParentsScreenState extends State<AllParentsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic> _currentUser = {};
  List<Parent> _parents = [];
  List<Parent> _allParents = [];
  bool _loading = true;
  double _savedScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadParents();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };
  }

  Future<void> _loadParents() async {
    setState(() => _loading = true);

    try {
      final raw = await _db.getAllParents();
      final list = raw.map((m) => Parent.fromMap(m)).toList();

      if (!mounted) return;

      setState(() {
        _allParents = list;
        _parents = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading parents: $e')),
      );
    }
  }

  void _searchParents(String keyword) {
    final kw = keyword.toLowerCase().trim();

    setState(() {
      if (kw.isEmpty) {
        _parents = _allParents;
      } else {
        _parents = _allParents.where((parent) {
          final name = parent.parentName.toLowerCase();
          final phone = parent.phoneNumber.toLowerCase();
          final phone2 = (parent.phoneNumber2 ?? '').toLowerCase();
          final email = (parent.emailAddress ?? '').toLowerCase();
          final address = parent.homeAddress.toLowerCase();

          return name.contains(kw) ||
              phone.contains(kw) ||
              phone2.contains(kw) ||
              email.contains(kw) ||
              address.contains(kw);
        }).toList();
      }
    });
  }

  Future<void> _navigateToAddParent() async {
    final result = await NavigationHelper.pushWithSidebar(
      context,
      page: const ParentFormScreen(),
      currentUser: _currentUser,
      pageId: 'parents',
    );

    if (result == true) {
      _loadParents();
    }
  }

  Future<void> _navigateToParentDetails(Parent parent) async {
    // Save scroll position before navigating
    _savedScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0;

    await NavigationHelper.pushWithSidebar(
      context,
      page: ParentDetailsScreen(parent: parent),
      currentUser: _currentUser,
      pageId: 'parents',
    );

    // Reload in case parent was edited
    await _loadParents();

    // Restore scroll position after list rebuilds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _savedScrollOffset > 0) {
        _scrollController.jumpTo(_savedScrollOffset);
      }
    });
  }

  Future<void> _deleteParent(Parent parent) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Parent'),
        content: Text(
          'Are you sure you want to delete ${parent.parentName}?\n\n'
          'This will also remove the parent details from all associated students.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // First, clear parent details from all students with this parent's phone number
        final allStudents = await _db.getStudents();
        final associatedStudents = allStudents.where((s) =>
          s['parentPhone'] == parent.phoneNumber ||
          (parent.phoneNumber2 != null &&
           parent.phoneNumber2!.isNotEmpty &&
           s['parentPhone'] == parent.phoneNumber2)
        ).toList();

        // Clear parent data from associated students
        for (final student in associatedStudents) {
          await _db.updateStudent(student['id'], {
            'parentName': '',
            'parentPhone': '',
            'parentEmail': '',
            'parentAddress': '',
          });
        }

        // Now delete the parent record
        await _db.deleteParent(parent.id!);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              associatedStudents.isNotEmpty
                  ? 'Parent deleted. Cleared from ${associatedStudents.length} student(s).'
                  : 'Parent deleted successfully',
            ),
          ),
        );
        _loadParents();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting parent: $e')),
        );
      }
    }
  }

  Future<void> _migrateParentData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migrate Parent Data'),
        content: const Text(
          'This will extract all unique parent records from existing student data.\n\n'
          'Use this after restoring from backup to populate the Parents table.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('MIGRATE'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Migrating parent data...'),
            duration: Duration(seconds: 2),
          ),
        );

        final count = await _db.migrateParentDataFromStudents();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully migrated $count parent records'),
            backgroundColor: Colors.green,
          ),
        );
        _loadParents();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error migrating parent data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Launch phone dialer
  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No phone app found to call $phoneNumber')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch dialer: $e')),
      );
    }
  }

  // Launch email composer
  Future<void> _sendEmail(String email) async {
    final uri = Uri.parse('mailto:$email');
    try {
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No email client found to send to $email')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch email client: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Parents'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade600, Colors.indigo.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadParents,
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'migrate') {
                _migrateParentData();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'migrate',
                child: Row(
                  children: [
                    Icon(Icons.sync_alt, size: 20),
                    SizedBox(width: 12),
                    Text('Migrate Parent Data'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Header with Search and Count
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade50, Colors.purple.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade300,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Count Badge Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade600,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.indigo.shade200,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.people,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Parent Directory',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Manage all parent records',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade600,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.shade200,
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '${_parents.length}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Search Bar
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search by name, phone, email, or address...',
                      prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchCtrl.clear();
                                _searchParents('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.indigo.shade400, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: _searchParents,
                  ),
                ],
              ),
            ),
          ),

          // Parents List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _parents.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _parents.length,
                        itemBuilder: (context, index) {
                          final parent = _parents[index];
                          return _buildParentCard(parent, index);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddParent,
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Parent', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildParentCard(Parent parent, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _navigateToParentDetails(parent),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Serial Number Badge
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.indigo.shade400, Colors.indigo.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Avatar
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.indigo.shade100,
                    child: Icon(
                      Icons.person,
                      size: 26,
                      color: Colors.indigo.shade700,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Name and Occupation
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parent.parentName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (parent.occupation != null && parent.occupation!.isNotEmpty)
                          Text(
                            parent.occupation!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // Action Buttons
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'view') {
                        _navigateToParentDetails(parent);
                      } else if (value == 'delete') {
                        _deleteParent(parent);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.visibility, size: 20, color: Colors.blue),
                            SizedBox(width: 12),
                            Text('View Details'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const Divider(height: 24),

              // Contact Info Row
              Row(
                children: [
                  // Phone
                  Expanded(
                    child: InkWell(
                      onTap: () => _makePhoneCall(parent.phoneNumber),
                      child: Row(
                        children: [
                          Icon(Icons.phone, size: 16, color: Colors.green.shade600),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              parent.phoneNumber,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Email
                  if (parent.emailAddress != null && parent.emailAddress!.isNotEmpty)
                    Expanded(
                      child: InkWell(
                        onTap: () => _sendEmail(parent.emailAddress!),
                        child: Row(
                          children: [
                            Icon(Icons.email, size: 16, color: Colors.orange.shade600),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                parent.emailAddress!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Address Row
              Row(
                children: [
                  Icon(Icons.home, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      parent.homeAddress,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline,
                size: 80,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _allParents.isEmpty ? 'No Parents Added Yet' : 'No Parents Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _allParents.isEmpty
                  ? 'Add your first parent to get started'
                  : 'Try adjusting your search',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            if (_allParents.isEmpty) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _navigateToAddParent,
                icon: const Icon(Icons.add),
                label: const Text('Add First Parent'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
