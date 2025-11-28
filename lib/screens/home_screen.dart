import 'package:flutter/material.dart';

import 'students/student_list_screen.dart';
import 'classes/class_list_screen.dart';
import 'fees/fee_item_list_screen.dart';
import 'billing/bill_student_select_screen.dart';
import 'payments/payment_student_select_screen.dart';
import 'school_profile/school_profile_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'backup/backup_screen.dart';
import 'sessions/session_term_management_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Bursary Manager'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          menuCard(
            context,
            title: 'Dashboard',
            subtitle: 'Summary of students, fees & payments',
            icon: Icons.dashboard_outlined,
            page: const DashboardScreen(),
          ),

          menuCard(
            context,
            title: 'Session & Term Management',
            subtitle: 'Configure and activate school sessions & terms',
            icon: Icons.date_range_outlined,
            page: const SessionTermManagementScreen(),
          ),

          menuCard(
            context,
            title: 'Student Management',
            subtitle: 'Register, view and manage students',
            icon: Icons.person_outline,
            page: const StudentListScreen(),
          ),

          menuCard(
            context,
            title: 'Class & Arm Management',
            subtitle: 'Configure classes and arms',
            icon: Icons.school_outlined,
            page: const ClassListScreen(),
          ),

          menuCard(
            context,
            title: 'Fee Items & Class Fees',
            subtitle: 'Define fees and assign to classes',
            icon: Icons.payments_outlined,
            page: const FeeItemListScreen(),
          ),

          menuCard(
            context,
            title: 'Student Bills',
            subtitle: 'Generate bills and receipts',
            icon: Icons.receipt_long_outlined,
            page: const BillStudentSelectScreen(),
          ),

          menuCard(
            context,
            title: 'Payments',
            subtitle: 'Record student payments',
            icon: Icons.attach_money_outlined,
            page: const PaymentStudentSelectScreen(),
          ),

          menuCard(
            context,
            title: 'School Profile',
            subtitle: 'Set school info and logo',
            icon: Icons.account_balance_outlined,
            page: const SchoolProfileScreen(),
          ),

          menuCard(
            context,
            title: 'Backup & Restore',
            subtitle: 'Save or restore your database',
            icon: Icons.save_alt_outlined,
            page: const BackupScreen(),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // REUSABLE MENU CARD WIDGET
  // -------------------------------------------------------------
  Widget menuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget page,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, size: 34),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => page),
          );
        },
      ),
    );
  }
}
