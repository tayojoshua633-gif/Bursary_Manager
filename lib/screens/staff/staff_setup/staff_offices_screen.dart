// lib/screens/staff/staff_setup/staff_offices_screen.dart
import 'package:flutter/material.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff_office.dart';
import 'staff_office_form_screen.dart';

class StaffOfficesScreen extends StatefulWidget {
  const StaffOfficesScreen({super.key});

  @override
  State<StaffOfficesScreen> createState() => _StaffOfficesScreenState();
}

class _StaffOfficesScreenState extends State<StaffOfficesScreen> {
  final _dbHelper = DatabaseHelper();
  List<StaffOffice> _offices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOffices();
  }

  Future<void> _loadOffices() async {
    setState(() => _isLoading = true);
    try {
      final officesData = await _dbHelper.getStaffOffices();
      setState(() {
        _offices = officesData.map((e) => StaffOffice.fromMap(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading offices: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteOffice(StaffOffice office) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Office'),
        content: Text('Are you sure you want to delete "${office.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _dbHelper.deleteStaffOffice(office.id!);
        _loadOffices();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Office deleted'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Offices'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StaffOfficeFormScreen()),
          );
          if (result == true) _loadOffices();
        },
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _offices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.business_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No offices created yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const StaffOfficeFormScreen()),
                          );
                          if (result == true) _loadOffices();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Office'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _offices.length,
                  itemBuilder: (ctx, i) {
                    final office = _offices[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.withValues(alpha: 0.2),
                          child: const Icon(Icons.business, color: Colors.teal),
                        ),
                        title: Text(
                          office.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: office.description != null && office.description!.isNotEmpty
                            ? Text(office.description!)
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StaffOfficeFormScreen(office: office),
                                  ),
                                );
                                if (result == true) _loadOffices();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteOffice(office),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
