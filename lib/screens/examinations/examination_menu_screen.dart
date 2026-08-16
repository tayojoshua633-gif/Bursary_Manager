import 'package:flutter/material.dart';
import '../../utils/display_settings_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import 'external_examination_list_screen.dart';
import 'examination_registration_screen.dart';
import 'registered_students_screen.dart';

class ExaminationMenuScreen extends StatelessWidget {
  final Map<String, dynamic> currentUser;

  const ExaminationMenuScreen({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('External Examination'),
        backgroundColor: Colors.cyan.shade700,
        foregroundColor: Colors.white,
      ),
      body: GridView.extent(
        maxCrossAxisExtent: context.gridMaxExtent,
        padding: EdgeInsets.all(ds.cardPadding),
        crossAxisSpacing: ds.cardPadding,
        mainAxisSpacing: ds.cardPadding,
        childAspectRatio: context.gridChildAspectRatio,
        children: [
          _menuCard(
            context,
            title: 'Examination Types',
            subtitle: 'Manage external examinations',
            icon: Icons.school_outlined,
            color: Colors.cyan.shade700,
            page: const ExternalExaminationListScreen(),
            pageId: 'external_examinations/types',
          ),
          _menuCard(
            context,
            title: 'Exam Registration',
            subtitle: 'Register students for exams',
            icon: Icons.app_registration_outlined,
            color: Colors.teal,
            page: ExaminationRegistrationScreen(currentUser: currentUser),
            pageId: 'external_examinations/registration',
          ),
          _menuCard(
            context,
            title: 'Registered Students',
            subtitle: 'View & export registered students',
            icon: Icons.people_outline,
            color: Colors.indigo,
            page: const RegisteredStudentsScreen(),
            pageId: 'external_examinations/students',
          ),
        ],
      ),
    );
  }

  Widget _menuCard(
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
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final showSidebar = MediaQuery.of(context).size.shortestSide >= 700;
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
        child: Container(
          padding: EdgeInsets.all(ds.cardPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.12),
                color.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(ds.cardPadding),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: ds.iconSize * 1.6, color: color),
              ),
              SizedBox(height: ds.cardPadding * 0.75),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: ds.titleFontSize * 0.85,
                ),
              ),
              SizedBox(height: ds.cardPadding * 0.25),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ds.subtitleFontSize,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
