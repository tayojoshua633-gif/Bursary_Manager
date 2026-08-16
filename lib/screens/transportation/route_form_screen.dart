import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';

class RouteFormScreen extends StatefulWidget {
  final Map<String, dynamic>? route;

  const RouteFormScreen({super.key, this.route});

  @override
  State<RouteFormScreen> createState() => _RouteFormScreenState();
}

class _RouteFormScreenState extends State<RouteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _fareCtrl = TextEditingController();
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final route = widget.route;
    if (route != null) {
      _nameCtrl.text = (route['name'] ?? '').toString();
      _descriptionCtrl.text = (route['description'] ?? '').toString();
      final fare = route['fare'];
      _fareCtrl.text = fare == null ? '' : (fare as num).toString();
      _isActive = route['isActive'] == 1;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _fareCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final data = {
      'name': _nameCtrl.text.trim(),
      'description': _descriptionCtrl.text.trim(),
      'fare': double.parse(_fareCtrl.text.trim()),
      'isActive': _isActive ? 1 : 0,
    };

    try {
      if (widget.route == null) {
        await _db.insertTransportRoute(data);
      } else {
        await _db.updateTransportRoute(widget.route!['id'] as int, data);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save route: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.route != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Route' : 'Add Route')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Route Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Route name required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fareCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fare',
                  border: OutlineInputBorder(),
                  prefixText: '₦',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim());
                  if (value == null) return 'Enter a valid amount';
                  if (value < 0) return 'Fare cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Active'),
                subtitle: const Text('Inactive routes cannot be assigned to students'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
