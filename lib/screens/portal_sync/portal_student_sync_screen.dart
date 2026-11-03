// lib/screens/portal_sync/portal_student_sync_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/portal_student_sync_client.dart';
import '../../utils/portal_student_sync_service.dart';

/// Home > School Portal Sync.
///
/// Class teachers correct their students' details on the online portal. For
/// a school that keeps its students in BM (and syncs them into DSM), the
/// portal sends those corrections here; the admin compares them with BM's
/// records and imports them. Photos still go to DSM.
class PortalStudentSyncScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  const PortalStudentSyncScreen({super.key, required this.currentUser});

  /// Who may open this screen. Not a permissions-table module, so no
  /// database migration: admins only, as with other school-wide settings.
  static bool allowed(Map<String, dynamic> user) =>
      const ['developer', 'super_admin', 'admin'].contains(user['userType']);

  @override
  State<PortalStudentSyncScreen> createState() => _PortalStudentSyncScreenState();
}

class _PortalStudentSyncScreenState extends State<PortalStudentSyncScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _canImport = true;
  bool _linked = false;
  String? _error;
  String? _schoolName;
  DateTime? _lastCheck;
  bool _autoImport = true;

  /// False when DSM hasn't switched on student details for teachers.
  bool _detailsOn = true;
  List<SyncRow> _rows = [];
  List<Map<String, dynamic>> _history = [];

  String get _actor => (widget.currentUser['username'] as String?) ?? 'Admin';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final canImport = await PortalStudentSyncService.canImportHere();
    final linked = await PortalStudentSyncClient.isLinked();
    final hist = canImport ? await PortalStudentSyncService.history() : <Map<String, dynamic>>[];
    final auto = await PortalStudentSyncService.autoImportEnabled();
    final last = await PortalStudentSyncService.lastCheck();
    if (!mounted) return;
    setState(() {
      _canImport = canImport;
      _linked = linked;
      _history = hist;
      _autoImport = auto;
      _lastCheck = last;
      _loading = false;
    });
    if (canImport && linked) _check();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final st = await PortalStudentSyncClient.status();
      final rows = await PortalStudentSyncService.fetchAndCompare();
      final hist = await PortalStudentSyncService.history();
      if (!mounted) return;
      setState(() {
        _schoolName = st['schoolName'] as String?;
        _detailsOn = st['studentDetailsOn'] != false;
        _rows = rows;
        _history = hist;
        _lastCheck = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is PortalSyncException ? e.message : 'Could not check the portal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(Map<int, SyncDecision> decisions, {Map<int, String> reasons = const {}}) async {
    if (decisions.isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await PortalStudentSyncService.apply(_rows, decisions, actedBy: _actor, reasons: reasons);
      if (!mounted) return;
      final parts = [
        if (res.imported > 0) '${res.imported} imported',
        if (res.keptLocal > 0) '${res.keptLocal} kept as in BM',
        if (res.rejected > 0) '${res.rejected} rejected',
      ];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${parts.isEmpty ? 'Nothing to do' : parts.join(', ')}.'
            '${res.ackError != null ? ' The portal will be told on the next check (${res.ackError}).' : ''}'),
        backgroundColor: res.ackError != null ? Colors.orange.shade800 : Colors.green,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _check();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ready = _canImport && _linked && PortalStudentSyncScreen.allowed(widget.currentUser);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('School Portal Sync'),
          actions: [
            if (ready)
              IconButton(
                tooltip: 'Connection',
                icon: const Icon(Icons.link),
                onPressed: _busy ? null : _openLink,
              ),
            if (ready)
              IconButton(
                tooltip: 'Check portal',
                icon: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_sync_outlined),
                onPressed: _busy ? null : _check,
              ),
          ],
          bottom: ready
              ? TabBar(tabs: [
                  Tab(child: _tabLabel('Student Details', _rows.length)),
                  const Tab(text: 'Log'),
                ])
              : null,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : !PortalStudentSyncScreen.allowed(widget.currentUser)
                ? _message(Icons.lock_outline, 'No access', 'Only an Admin or Super Admin can import student details from the portal.')
                : !_canImport
                    ? _message(Icons.phone_android, 'Open this on the school\'s main device',
                        'Student details from the portal are imported on the device that holds the school\'s own data, not on a network client or a Read-Only device.')
                    : !_linked
                        ? _LinkForm(onLinked: () {
                            setState(() => _linked = true);
                            PortalStudentSyncService.startAutoImportIfEnabled();
                            _check();
                          })
                        : Column(children: [
                            _statusStrip(),
                            Expanded(child: TabBarView(children: [_waitingTab(), _logTab()])),
                          ]),
      ),
    );
  }

  Widget _tabLabel(String text, int n) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text),
        if (n > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
            child: Text('$n', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ]);

  Widget _message(IconData icon, String title, String body) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 56, color: Colors.teal.shade300),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
            ]),
          ),
        ),
      );

  Widget _statusStrip() {
    final fmt = DateFormat('d MMM yyyy, h:mm a');
    return Container(
      width: double.infinity,
      color: Colors.teal.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Icon(Icons.cloud_done_outlined, size: 18, color: Colors.teal.shade600),
          if (_schoolName != null) Text(_schoolName!, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_lastCheck == null ? 'Not checked yet' : 'Last checked ${fmt.format(_lastCheck!)}'),
          Text('· ${_rows.length} waiting', style: const TextStyle(fontWeight: FontWeight.w600)),
          FilterChip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(_autoImport ? Icons.bolt : Icons.rule, size: 16),
            label: Text(_autoImport ? 'Auto-import on' : 'Auto-import off'),
            tooltip: 'Every 5 minutes, import corrections that need no check. '
                'Names, gender, date of birth and parent name/phone always wait for you.',
            selected: _autoImport,
            onSelected: (v) async {
              await PortalStudentSyncService.setAutoImport(v);
              if (mounted) setState(() => _autoImport = v);
            },
          ),
        ]),
        if (!_detailsOn)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Class teachers can\'t send student updates yet. In DSM, open Class/Subject Teacher Sync > Settings, '
                  'switch on teacher entry and tick Student Details; the portal follows after DSM\'s next online backup.',
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              ),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade800))),
            ]),
          ),
      ]),
    );
  }

  // ── Waiting: one card per student ────────────────────────────────────────

  Widget _waitingTab() {
    if (_rows.isEmpty) {
      return _message(Icons.badge_outlined, 'Nothing waiting',
          _busy ? 'Checking the portal…' : 'Corrections class teachers send to their students\' details appear here.');
    }
    final groups = <String, List<SyncRow>>{};
    for (final r in _rows) {
      groups.putIfAbsent('${r.entry.studentId}|${r.entry.userId}', () => []).add(r);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final g in groups.values) _groupCard(g)],
    );
  }

  Widget _groupCard(List<SyncRow> g) {
    final first = g.first;
    final count = <SyncStatus, int>{};
    for (final r in g) {
      count[r.status] = (count[r.status] ?? 0) + 1;
    }
    // Fields that identify the child or the parent always wait for a look.
    final quick = g.where((r) => r.clean && (r.status == SyncStatus.same || !(PortalStudentSyncService.fieldOf(r.entry.itemId)?.review ?? true)));
    final sent = g.map((r) => r.entry.createdAt).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: Colors.teal.shade50, child: Icon(Icons.badge_outlined, color: Colors.teal.shade700)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${first.studentName}${first.admissionNo.isNotEmpty ? ' (${first.admissionNo})' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${first.classLabel} · from ${first.entry.sender} · ${g.length} ${g.length == 1 ? 'change' : 'changes'}'
                    '${sent != null ? ' · sent ${DateFormat('d MMM, h:mm a').format(sent)}' : ''}',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final st in SyncStatus.values)
              if ((count[st] ?? 0) > 0) _statusChip(st, suffix: ' ${count[st]}'),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _busy || quick.isEmpty ? null : () => _apply({for (final r in quick) r.entry.id: SyncDecision.import}),
              icon: const Icon(Icons.download_done, size: 18),
              label: Text('Import ${quick.length} that need no check'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _openCompare(g),
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: const Text('Compare & decide'),
            ),
          ]),
        ]),
      ),
    );
  }

  static (String, Color) _statusStyle(SyncStatus s) => switch (s) {
        SyncStatus.newValue => ('New', Colors.blue),
        SyncStatus.changed => ('Changed', Colors.teal),
        SyncStatus.same => ('Same', Colors.grey),
        SyncStatus.conflict => ('Conflict', Colors.deepOrange),
        SyncStatus.blocked => ('Blocked', Colors.red),
      };

  Widget _statusChip(SyncStatus s, {String suffix = ''}) {
    final (label, color) = _statusStyle(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label$suffix', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Future<void> _openCompare(List<SyncRow> group) async {
    final result = await Navigator.push<_CompareResult>(
      context,
      MaterialPageRoute(builder: (_) => _CompareScreen(rows: group, statusChip: _statusChip)),
    );
    if (result != null) await _apply(result.decisions, reasons: result.reasons);
  }

  // ── Log ──────────────────────────────────────────────────────────────────

  Widget _logTab() {
    if (_history.isEmpty) {
      return _message(Icons.history, 'No imports yet', 'Every correction imported, kept or rejected here is listed, with who sent and who approved it.');
    }
    final fmt = DateFormat('d MMM yyyy, h:mm a');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _history.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final h = _history[i];
        final action = h['action'] as String? ?? '';
        final field = (h['field'] as num?)?.toInt();
        PortalValue? v(String col) {
          final s = h[col] as String?;
          if (s == null) return null;
          try {
            return PortalValue.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }

        final (label, color) = switch (action) {
          'applied' => ('Imported', Colors.green),
          'kept_local' => ('Kept BM value', Colors.blueGrey),
          _ => ('Rejected', Colors.red),
        };
        final when = DateTime.tryParse(h['actedAt'] as String? ?? '');
        return ListTile(
          dense: true,
          leading: Icon(Icons.badge_outlined, color: color),
          title: Text('${h['surname'] ?? ''} ${h['firstName'] ?? ''} · ${h['className'] ?? ''} ${h['armName'] ?? ''}'.trim()),
          subtitle: Text([
            '${PortalStudentSyncService.studentFields[field]?.label ?? 'Detail'}: '
                '${PortalStudentSyncService.formatValue(v('localBefore'), field: field)} → '
                '${action == 'applied' ? PortalStudentSyncService.formatValue(v('valueImported'), field: field) : 'not imported'}',
            'From ${(h['teacherName'] as String?)?.isNotEmpty == true ? h['teacherName'] : h['submittedBy']} · by ${h['actedBy']}'
                '${when != null ? ' · ${fmt.format(when)}' : ''}${(h['acked'] as num?)?.toInt() == 0 ? ' · portal not told yet' : ''}',
            if ((h['reason'] as String?)?.isNotEmpty == true) 'Reason: ${h['reason']}',
          ].join('\n'), maxLines: 4, overflow: TextOverflow.ellipsis),
          trailing: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        );
      },
    );
  }

  // ── Connection ───────────────────────────────────────────────────────────

  Future<void> _openLink() async {
    final code = await PortalStudentSyncClient.schoolCode();
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Portal connection'),
        content: Text('Connected with DSM school code ${code ?? '—'}.\n\n'
            'Change the token after generating a new one in DSM, or disconnect to stop receiving student details on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'unlink'), child: const Text('Disconnect')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'change'), child: const Text('Change token')),
        ],
      ),
    );
    if (action == null) return;
    if (action == 'unlink') {
      await PortalStudentSyncClient.unlink();
      PortalStudentSyncService.stopAutoImport();
      PortalStudentSyncService.pendingCount.value = 0;
    }
    if (!mounted) return;
    // Either way the link form shows next ("Change token" keeps the old
    // connection until a new one tests fine).
    setState(() {
      _linked = false;
      _rows = [];
      _error = null;
    });
  }
}

// ── Link form ──────────────────────────────────────────────────────────────

class _LinkForm extends StatefulWidget {
  final VoidCallback onLinked;
  const _LinkForm({required this.onLinked});

  @override
  State<_LinkForm> createState() => _LinkFormState();
}

class _LinkFormState extends State<_LinkForm> {
  final _code = TextEditingController();
  final _token = TextEditingController();
  bool _testing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    PortalStudentSyncClient.schoolCode().then((c) {
      if (c != null && mounted) _code.text = c;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final code = _code.text.trim();
    final token = _token.text.trim();
    if (code.isEmpty || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)) {
      setState(() => _error = 'Enter the DSM school code and the 64-character BM sync token.');
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
    });
    final oldCode = await PortalStudentSyncClient.schoolCode();
    final oldToken = await PortalStudentSyncClient.token();
    await PortalStudentSyncClient.link(code, token);
    try {
      await PortalStudentSyncClient.status();
      widget.onLinked();
    } catch (e) {
      // Keep the previous connection rather than one that doesn't work.
      if (oldCode != null && oldToken != null) {
        await PortalStudentSyncClient.link(oldCode, oldToken);
      } else {
        await PortalStudentSyncClient.unlink();
      }
      if (mounted) setState(() => _error = e is PortalSyncException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.cloud_sync_outlined, size: 56, color: Colors.teal.shade300),
              const SizedBox(height: 12),
              const Text('Receive student details from the portal',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Class teachers correct their students\' details on the online portal. If this school keeps its students in '
                'Bursary Manager and DSM syncs from BM, import those corrections here so DSM\'s next sync doesn\'t overwrite them.\n\n'
                '1. On the portal, set Preferences > Student Details Receiver to Bursary Manager.\n'
                '2. In DSM, open Class/Subject Teacher Sync > Settings and press Generate BM sync token.\n'
                '3. Paste the DSM school code and the token below.\n\n'
                'Photos are not sent to BM; they are still imported in DSM.',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'DSM school code', hintText: 'e.g. DAWOT-DT-CSC-0003', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                decoration: const InputDecoration(labelText: 'BM sync token', border: OutlineInputBorder()),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _testing ? null : _connect,
                icon: _testing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.link),
                label: const Text('Connect'),
              ),
            ]),
          ),
        ),
      );
}

// ── Compare screen ─────────────────────────────────────────────────────────

class _CompareResult {
  final Map<int, SyncDecision> decisions;
  final Map<int, String> reasons;
  _CompareResult(this.decisions, this.reasons);
}

class _CompareScreen extends StatefulWidget {
  final List<SyncRow> rows;
  final Widget Function(SyncStatus, {String suffix}) statusChip;
  const _CompareScreen({required this.rows, required this.statusChip});

  @override
  State<_CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<_CompareScreen> {
  /// null = decide later (stays waiting on the portal).
  late final Map<int, SyncDecision?> _choice = {
    for (final r in widget.rows)
      r.entry.id: switch (r.status) {
        SyncStatus.newValue || SyncStatus.changed || SyncStatus.same => SyncDecision.import,
        SyncStatus.blocked => SyncDecision.reject,
        SyncStatus.conflict => null,
      },
  };

  @override
  Widget build(BuildContext context) {
    final first = widget.rows.first;
    final decided = _choice.values.where((d) => d != null).length;
    return Scaffold(
      appBar: AppBar(title: Text('${first.studentName} · Details')),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: Colors.grey.shade100,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Text(
            'From ${first.entry.sender} (${first.classLabel}). "Teacher started from" is what the portal showed when the teacher saved; '
            'a Conflict means BM changed since then (or two teachers disagree).',
            style: TextStyle(color: Colors.grey[800], fontSize: 13),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: widget.rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = widget.rows[i];
              final field = PortalStudentSyncService.fieldOf(r.entry.itemId);
              String fv(PortalValue? v) => PortalStudentSyncService.formatValue(v, field: r.entry.itemId);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${i + 1}. ${r.itemLabel}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (field?.review == true)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Tooltip(
                          message: 'Check this one with care',
                          child: Icon(Icons.verified_user_outlined, size: 18, color: Colors.orange.shade800),
                        ),
                      ),
                    widget.statusChip(r.status),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 18, runSpacing: 4, children: [
                    _valueBox('In BM', fv(r.local)),
                    _valueBox('Teacher started from', r.entry.baseSet ? fv(r.entry.base) : '—'),
                    _valueBox("Teacher's value", fv(r.entry.value), bold: true),
                  ]),
                  if (field?.column == 'parentPhone' && r.status != SyncStatus.blocked && r.status != SyncStatus.same)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'The parent phone decides which parent account sees this child on the portal. Confirm the new number with the parent before importing.',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (r.note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(r.note!,
                          style: TextStyle(fontSize: 12, color: r.status == SyncStatus.blocked ? Colors.red.shade700 : Colors.deepOrange.shade700)),
                    ),
                  const SizedBox(height: 6),
                  SegmentedButton<SyncDecision?>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      ButtonSegment(
                        value: SyncDecision.import,
                        label: Text(r.status == SyncStatus.conflict ? "Take teacher's" : 'Import'),
                        enabled: r.status != SyncStatus.blocked,
                      ),
                      if (r.status == SyncStatus.conflict) const ButtonSegment(value: SyncDecision.keepLocal, label: Text('Keep BM')),
                      const ButtonSegment(value: SyncDecision.reject, label: Text('Reject')),
                      const ButtonSegment(value: null, label: Text('Later')),
                    ],
                    selected: {_choice[r.entry.id]},
                    onSelectionChanged: (s) => setState(() => _choice[r.entry.id] = s.first),
                  ),
                ]),
              );
            },
          ),
        ),
        SafeArea(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)]),
            child: Row(children: [
              Expanded(child: Text('$decided of ${widget.rows.length} decided. "Later" ones stay waiting on the portal.', style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: decided == 0 ? null : _submit,
                icon: const Icon(Icons.done_all),
                label: const Text('Apply'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _valueBox(String label, String value, {bool bold = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ]);

  Future<void> _submit() async {
    final decisions = <int, SyncDecision>{
      for (final e in _choice.entries)
        if (e.value != null) e.key: e.value!,
    };
    final reasons = <int, String>{};
    if (decisions.values.contains(SyncDecision.reject)) {
      final ctrl = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reason for rejecting'),
          content: TextField(
            controller: ctrl,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Shown to the teacher on the portal (optional)', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Continue')),
          ],
        ),
      );
      if (reason == null) return;
      for (final r in widget.rows) {
        if (decisions[r.entry.id] == SyncDecision.reject) {
          reasons[r.entry.id] = reason.isNotEmpty ? reason : (r.note ?? 'Rejected by the school.');
        }
      }
    }
    if (!mounted) return;
    Navigator.pop(context, _CompareResult(decisions, reasons));
  }
}
