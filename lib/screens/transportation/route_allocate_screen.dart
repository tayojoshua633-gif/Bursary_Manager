import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';

class RouteAllocateScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  final String term;
  final String session;

  const RouteAllocateScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.term,
    required this.session,
  });

  @override
  State<RouteAllocateScreen> createState() => _RouteAllocateScreenState();
}

class _RouteAllocateScreenState extends State<RouteAllocateScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _currency = NumberFormat.currency(locale: 'en_NG', symbol: '₦');

  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _routes = [];
  Map<String, dynamic>? _currentAllocation;
  int? _selectedRouteId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _routes = await _db.getTransportRoutes();
    _currentAllocation = await _db.getStudentTransportAllocation(
      widget.studentId,
      widget.term,
      widget.session,
    );
    _selectedRouteId = _currentAllocation?['routeId'] as int?;

    if (mounted) setState(() => _loading = false);
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    return msg.startsWith('Exception: ') ? msg.substring('Exception: '.length) : msg;
  }

  Future<void> _save() async {
    if (_selectedRouteId == null) {
      if (_currentAllocation != null) {
        await _remove();
      }
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _db.allocateStudentToRoute(
        studentId: widget.studentId,
        routeId: _selectedRouteId!,
        term: widget.term,
        session: widget.session,
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Route allocated and added to bill')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _db.removeStudentFromRoute(widget.studentId, widget.term, widget.session);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Route allocation removed from bill')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Allocate Route — ${widget.studentName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${widget.term}, ${widget.session}', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  if (_currentAllocation != null)
                    Card(
                      color: Colors.teal.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.directions_bus, color: Colors.teal.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Currently on "${_currentAllocation!['routeName']}" '
                                '(${_currency.format(_currentAllocation!['fareCharged'] ?? 0)} charged)',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    initialValue: _selectedRouteId,
                    decoration: const InputDecoration(
                      labelText: 'Route',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('-- Not Assigned --')),
                      ..._routes.map((r) => DropdownMenuItem<int?>(
                            value: r['id'] as int,
                            child: Text('${r['name']} (${_currency.format(r['fare'] ?? 0)})'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedRouteId = v),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (_currentAllocation != null)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : _remove,
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Remove'),
                          ),
                        ),
                      if (_currentAllocation != null) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Saving...' : 'Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
