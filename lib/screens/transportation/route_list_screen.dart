import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/navigation_helper.dart';
import 'route_form_screen.dart';

class RouteListScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const RouteListScreen({super.key, required this.currentUser});

  @override
  State<RouteListScreen> createState() => _RouteListScreenState();
}

class _RouteListScreenState extends State<RouteListScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _currency = NumberFormat.currency(locale: 'en_NG', symbol: '₦');

  List<Map<String, dynamic>> _routes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() => _loading = true);
    final routes = await _db.getTransportRoutes(includeInactive: true);
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _loading = false;
    });
  }

  void _openForm({Map<String, dynamic>? route}) async {
    final result = await NavigationHelper.pushWithSidebar(
      context,
      page: RouteFormScreen(route: route),
      currentUser: widget.currentUser,
      pageId: 'transportation/routes',
    );
    if (result == true) _loadRoutes();
  }

  Future<void> _toggleActive(Map<String, dynamic> route) async {
    final newValue = route['isActive'] == 1 ? 0 : 1;
    await _db.updateTransportRoute(route['id'] as int, {'isActive': newValue});
    _loadRoutes();
  }

  Future<void> _deleteRoute(Map<String, dynamic> route) async {
    final messenger = ScaffoldMessenger.of(context);
    final allocationCount = await _db.countActiveAllocationsForRoute(route['id'] as int);

    if (!mounted) return;

    if (allocationCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red),
              SizedBox(width: 8),
              Text('Cannot Delete Route'),
            ],
          ),
          content: Text(
            '"${route['name']}" cannot be deleted because $allocationCount student(s) are '
            'currently allocated to it. Reassign or remove those students first, or mark the '
            'route inactive instead.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Route'),
        content: Text('Are you sure you want to delete "${route['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _db.deleteTransportRoute(route['id'] as int);
    if (!mounted) return;
    await _loadRoutes();
    messenger.showSnackBar(SnackBar(content: Text('Route "${route['name']}" deleted')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transport Routes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _routes.isEmpty
              ? const Center(child: Text('No routes added yet'))
              : ListView.builder(
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final r = _routes[index];
                    final active = r['isActive'] == 1;
                    return Card(
                      child: ListTile(
                        title: Text(r['name'] ?? ''),
                        subtitle: Text(
                          (r['description'] != null && (r['description'] as String).isNotEmpty)
                              ? '${r['description']}\nFare: ${_currency.format(r['fare'] ?? 0)}'
                              : 'Fare: ${_currency.format(r['fare'] ?? 0)}',
                        ),
                        isThreeLine: r['description'] != null && (r['description'] as String).isNotEmpty,
                        onTap: () => _openForm(route: r),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ActionChip(
                              label: Text(active ? 'Active' : 'Inactive'),
                              backgroundColor: active ? Colors.green.shade50 : Colors.grey.shade200,
                              labelStyle: TextStyle(color: active ? Colors.green.shade800 : Colors.grey.shade700),
                              onPressed: () => _toggleActive(r),
                            ),
                            IconButton(
                              tooltip: 'Edit Route',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _openForm(route: r),
                            ),
                            IconButton(
                              tooltip: 'Delete Route',
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteRoute(r),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
