// lib/screens/menus/parents_management_menu.dart

import 'package:flutter/material.dart';
import '../../utils/display_settings_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../parents/parent_form_screen.dart';
import '../parents/all_parents_screen.dart';
import '../parents/manage_parent_contacts_screen.dart';

class ParentsManagementMenu extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const ParentsManagementMenu({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parents Management'),
        backgroundColor: Colors.teal,
      ),
      body: GridView.extent(
        maxCrossAxisExtent: context.gridMaxExtent,
        padding: EdgeInsets.all(ds.cardPadding),
        crossAxisSpacing: ds.cardPadding,
        mainAxisSpacing: ds.cardPadding,
        childAspectRatio: context.gridChildAspectRatio,
        children: [
          // Add New Parent
          _buildMenuItem(
            context,
            title: 'Add New Parent',
            subtitle: 'Register parent info',
            icon: Icons.person_add,
            color: Colors.teal,
            page: const ParentFormScreen(),
            pageId: 'parents_management/add_parent',
          ),

          // All Parents
          _buildMenuItem(
            context,
            title: 'All Parents',
            subtitle: 'View & manage',
            icon: Icons.people,
            color: Colors.indigo,
            page: const AllParentsScreen(),
            pageId: 'parents_management/all_parents',
          ),

          // Manage Parent Contacts
          _buildMenuItem(
            context,
            title: 'Manage Contacts',
            subtitle: 'Save to device',
            icon: Icons.contact_phone,
            color: Colors.deepPurple,
            page: const ManageParentContactsScreen(),
            pageId: 'parents_management/manage_contacts',
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget page,
    String? pageId,
  }) {
    final ds = DisplaySettingsProvider.of(context);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          final screenSize = MediaQuery.of(context).size;
          final showSidebar = screenSize.shortestSide >= 700;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => showSidebar
                  ? SidebarScaffold(
                      currentUser: currentUser,
                      currentPageId: pageId,
                      child: page,
                    )
                  : page,
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(ds.cardPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 35,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, size: ds.iconSize * 1.6, color: color),
              ),
              SizedBox(height: ds.cardPadding * 0.75),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ds.titleFontSize * 0.85,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: ds.cardPadding * 0.25),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ds.subtitleFontSize,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
