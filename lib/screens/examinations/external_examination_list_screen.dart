import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/external_examination.dart';
import '../../utils/display_settings_helper.dart';

class ExternalExaminationListScreen extends StatefulWidget {
  const ExternalExaminationListScreen({super.key});

  @override
  State<ExternalExaminationListScreen> createState() =>
      _ExternalExaminationListScreenState();
}

class _ExternalExaminationListScreenState
    extends State<ExternalExaminationListScreen> {
  final _db = DatabaseHelper();
  List<ExternalExamination> _exams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.getExternalExaminations();
    if (!mounted) return;
    setState(() {
      _exams = rows.map(ExternalExamination.fromMap).toList();
      _loading = false;
    });
  }

  Future<void> _showForm({ExternalExamination? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Examination' : 'Edit Examination'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Examination Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code / Abbreviation *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final now = DateTime.now().toIso8601String();
    if (existing == null) {
      await _db.insertExternalExamination({
        'name': nameCtrl.text.trim(),
        'code': codeCtrl.text.trim(),
        'isDefault': 0,
        'isActive': 1,
        'createdAt': now,
      });
    } else {
      await _db.updateExternalExamination(existing.id!, {
        'name': nameCtrl.text.trim(),
        'code': codeCtrl.text.trim(),
      });
    }
    _load();
  }

  Future<void> _toggleActive(ExternalExamination exam) async {
    await _db.updateExternalExamination(exam.id!, {
      'isActive': exam.isActive ? 0 : 1,
    });
    _load();
  }

  Future<void> _delete(ExternalExamination exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Examination'),
        content: Text(
            'Delete "${exam.name} (${exam.code})"?\n\nAll student registrations for this exam will also be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.deleteExternalExamination(exam.id!);
    _load();
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Defaults'),
        content: const Text(
            'This will add back the 5 default examinations if they are missing. Existing records will not be affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final defaults = [
      {'name': 'Primary School Leaving Certificate', 'code': 'PSLC'},
      {'name': 'Basic Education Certificate Examination', 'code': 'BECE'},
      {'name': 'SSS Two Joint Examination', 'code': 'SSS 2 JOINT'},
      {'name': 'West African Examination Council', 'code': 'WAEC'},
      {'name': 'National Examination Council', 'code': 'NECO'},
    ];

    final existing = await _db.getExternalExaminations();
    final existingCodes =
        existing.map((e) => (e['code'] as String).toUpperCase()).toSet();
    final now = DateTime.now().toIso8601String();
    int added = 0;
    for (final d in defaults) {
      if (!existingCodes.contains(d['code']!.toUpperCase())) {
        await _db.insertExternalExamination({
          'name': d['name'],
          'code': d['code'],
          'isDefault': 1,
          'isActive': 1,
          'createdAt': now,
        });
        added++;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            added > 0 ? '$added default examination(s) restored.' : 'All defaults already present.'),
        backgroundColor: added > 0 ? Colors.green : Colors.grey,
      ));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Examination Types'),
        backgroundColor: Colors.cyan.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Restore Defaults',
            onPressed: _restore,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Examination',
            onPressed: () => _showForm(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _exams.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No examinations found',
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: ds.titleFontSize)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _restore,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore Defaults'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: EdgeInsets.all(ds.cardPadding),
                    itemCount: _exams.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(height: ds.cardPadding * 0.5),
                    itemBuilder: (_, i) {
                      final exam = _exams[i];
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: ds.cardPadding,
                              vertical: ds.cardPadding * 0.4),
                          leading: CircleAvatar(
                            backgroundColor: exam.isActive
                                ? Colors.cyan.shade700.withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.15),
                            child: Text(
                              exam.code.length > 4
                                  ? exam.code.substring(0, 4)
                                  : exam.code,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: exam.isActive
                                    ? Colors.cyan.shade700
                                    : Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          title: Text(
                            exam.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: ds.titleFontSize * 0.85,
                              color:
                                  exam.isActive ? null : Colors.grey,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Text(exam.code,
                                  style: TextStyle(
                                      fontSize: ds.subtitleFontSize,
                                      color: Colors.grey[600])),
                              if (exam.isDefault) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('Default',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.blue)),
                                ),
                              ],
                              if (!exam.isActive) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('Inactive',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.red)),
                                ),
                              ],
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _showForm(existing: exam);
                              if (v == 'toggle') _toggleActive(exam);
                              if (v == 'delete') _delete(exam);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ])),
                              PopupMenuItem(
                                  value: 'toggle',
                                  child: Row(children: [
                                    Icon(
                                      exam.isActive
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(exam.isActive
                                        ? 'Deactivate'
                                        : 'Activate'),
                                  ])),
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(children: [
                                    Icon(Icons.delete_outline,
                                        size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete',
                                        style: TextStyle(color: Colors.red)),
                                  ])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.cyan.shade700,
        foregroundColor: Colors.white,
        tooltip: 'Add Examination',
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
