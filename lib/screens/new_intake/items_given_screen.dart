// lib/screens/new_intake/items_given_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';
import '../../widgets/student_quick_access_bar.dart';

class ItemsGivenScreen extends StatefulWidget {
  final int studentId;
  final String studentName;

  const ItemsGivenScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<ItemsGivenScreen> createState() => _ItemsGivenScreenState();
}

class _ItemsGivenScreenState extends State<ItemsGivenScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  Map<String, dynamic>? _student;
  List<Map<String, dynamic>> _items = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final db = await _db.database;

    final studentRows = await db.rawQuery('''
      SELECT s.*, c.name as className, a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.id = ?
    ''', [widget.studentId]);
    if (studentRows.isNotEmpty) _student = studentRows.first;

    final rows = await db.rawQuery('''
      SELECT sid.markedAt, sid.term, sid.session,
             sfi.name AS itemName, parent.name AS categoryName
      FROM special_item_disbursements sid
      JOIN special_fee_items sfi ON sfi.id = sid.specialFeeItemId
      LEFT JOIN special_fee_items parent ON parent.id = sfi.parentId
      WHERE sid.studentId = ? AND sid.status = 'given'
      ORDER BY sid.markedAt DESC
    ''', [widget.studentId]);

    if (!mounted) return;
    setState(() {
      _items = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      _loading = false;
    });
  }

  String _itemLabel(Map<String, dynamic> item) {
    final categoryName = item['categoryName'] as String?;
    final name = item['itemName'] as String? ?? 'Unknown';
    return categoryName != null && categoryName.isNotEmpty ? '$categoryName • $name' : name;
  }

  String _formatDateTime(dynamic markedAt) {
    if (markedAt == null) return '';
    try {
      return DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(markedAt as String));
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    final showRightPanel = MediaQuery.of(context).size.shortestSide >= 700;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Items Given'),
        backgroundColor: Colors.cyan,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildBody(ds)),
                if (showRightPanel) _buildRightPanel(ds),
                if (showRightPanel) StudentQuickAccessBar(studentId: widget.studentId),
              ],
            ),
    );
  }

  Widget _buildBody(DisplaySettings ds) {
    final className = _student?['className']?.toString() ?? '';
    final armName = _student?['armName']?.toString() ?? '';
    final admissionNo = _student?['admissionNo']?.toString() ?? '';

    return SingleChildScrollView(
      padding: EdgeInsets.all(ds.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(ds.cardPadding * 0.75),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: ds.titleFontSize),
                ),
                if (admissionNo.isNotEmpty) ...[
                  SizedBox(height: ds.cardPadding * 0.25),
                  Text(admissionNo, style: TextStyle(color: Colors.grey.shade600, fontSize: ds.bodyFontSize)),
                ],
                if (className.isNotEmpty) ...[
                  SizedBox(height: ds.cardPadding * 0.15),
                  Text(
                    '$className${armName.isNotEmpty ? ' - $armName' : ''}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: ds.bodyFontSize),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: ds.cardPadding),
          Text(
            '${_items.length} item(s) given',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: ds.bodyFontSize, color: Colors.green.shade700),
          ),
          SizedBox(height: ds.cardPadding * 0.5),
          if (_items.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: ds.cardPadding * 2),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                    SizedBox(height: ds.cardPadding * 0.5),
                    Text(
                      'No items have been given to this student yet',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: ds.bodyFontSize),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._items.map((item) => Card(
                  margin: EdgeInsets.only(bottom: ds.cardPadding * 0.5),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade100,
                      child: Icon(Icons.check, color: Colors.green.shade700, size: 18),
                    ),
                    title: Text(_itemLabel(item)),
                    subtitle: Text('${item['term'] ?? ''} • ${item['session'] ?? ''}'),
                    trailing: Text(
                      _formatDateTime(item['markedAt']),
                      style: TextStyle(fontSize: ds.bodyFontSize * 0.8, color: Colors.grey.shade600),
                      textAlign: TextAlign.right,
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildRightPanel(DisplaySettings ds) {
    final theme = Theme.of(context);
    final className = _student?['className']?.toString() ?? '';
    final armName = _student?['armName']?.toString() ?? '';
    final admissionNo = _student?['admissionNo']?.toString() ?? '';
    final lastGiven = _items.isNotEmpty ? _formatDateTime(_items.first['markedAt']) : null;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(ds.cardPadding * 0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(left: ds.cardPadding * 0.25, bottom: ds.cardPadding * 0.5),
              child: Text(
                'Student Summary',
                style: TextStyle(
                  fontSize: ds.titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.all(ds.cardPadding * 0.6),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.studentName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: ds.bodyFontSize)),
                  if (admissionNo.isNotEmpty) ...[
                    SizedBox(height: ds.cardPadding * 0.15),
                    Text(admissionNo, style: TextStyle(fontSize: ds.bodyFontSize * 0.85, color: Colors.grey.shade600)),
                  ],
                  if (className.isNotEmpty) ...[
                    SizedBox(height: ds.cardPadding * 0.15),
                    Text(
                      '$className${armName.isNotEmpty ? ' - $armName' : ''}',
                      style: TextStyle(fontSize: ds.bodyFontSize * 0.85, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: ds.cardPadding * 0.75),
            _summaryStat(ds, icon: Icons.inventory_2, color: Colors.green, label: 'Items Given', value: '${_items.length}'),
            if (lastGiven != null)
              _summaryStat(ds, icon: Icons.event_available, color: Colors.blueGrey, label: 'Last Given', value: lastGiven),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(
    DisplaySettings ds, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: ds.cardPadding * 0.5),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.6, vertical: ds.cardPadding * 0.6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ds.cardPadding * 0.4),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: ds.iconSize * 0.9, color: Colors.white),
            ),
            SizedBox(width: ds.cardPadding * 0.6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: ds.bodyFontSize * 0.85, color: Colors.grey.shade600)),
                  Text(value, style: TextStyle(fontSize: ds.bodyFontSize, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
