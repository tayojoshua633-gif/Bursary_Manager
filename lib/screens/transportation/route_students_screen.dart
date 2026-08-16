import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';

class RouteStudentsScreen extends StatefulWidget {
  const RouteStudentsScreen({super.key});

  @override
  State<RouteStudentsScreen> createState() => _RouteStudentsScreenState();
}

class _RouteStudentsScreenState extends State<RouteStudentsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _currency = NumberFormat.currency(locale: 'en_NG', symbol: '₦');

  bool _loading = true;
  String _term = '';
  String _session = '';
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _allocations = [];
  Map<int, String?> _parentPhoneByStudentId = {};
  Set<String> _siblingPhones = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _term = await _db.getActiveTerm();
    _session = (await _db.getActiveSession())?['sessionName'] ?? '';
    _routes = await _db.getTransportRoutes();
    _allocations = await _db.getRouteAllocationsWithDetails(_term, _session);

    final activeStudents = await _db.getActiveStudents();
    _parentPhoneByStudentId = {
      for (final s in activeStudents) s['id'] as int: s['parentPhone'] as String?,
    };
    _siblingPhones = computeSiblingPhones(activeStudents);

    if (mounted) setState(() => _loading = false);
  }

  Widget _studentTile(Map<String, dynamic> a, DisplaySettings ds, {bool showRoute = false}) {
    final name = "${a['surname']} ${a['firstName']}".trim();
    final cls = a['className'] ?? 'No Class';
    final arm = a['armName'] ?? 'No Arm';

    return Card(
      margin: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.75, vertical: ds.cardPadding * 0.25),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal.shade100,
          child: Icon(Icons.directions_bus, color: Colors.teal.shade700, size: ds.iconSize),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(name,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: ds.bodyFontSize),
                  overflow: TextOverflow.ellipsis),
            ),
            SiblingMark(
              show: isSiblingPhone(_parentPhoneByStudentId[a['studentId'] as int?], _siblingPhones),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Adm: ${a['admissionNo'] ?? ''} — $cls, $arm", style: TextStyle(fontSize: ds.subtitleFontSize)),
            if (showRoute)
              Text(
                "Route: ${a['routeName']}",
                style: TextStyle(fontSize: ds.subtitleFontSize, color: Colors.teal.shade700, fontWeight: FontWeight.w500),
              ),
          ],
        ),
        trailing: Text(
          _currency.format((a['fareCharged'] as num?) ?? 0),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: ds.bodyFontSize * 0.9, color: Colors.teal.shade800),
        ),
      ),
    );
  }

  Widget _studentList(List<Map<String, dynamic>> students, DisplaySettings ds, {bool showRoute = false}) {
    if (students.isEmpty) {
      return Center(
        child: Text('No students on this route yet', style: TextStyle(fontSize: ds.bodyFontSize, color: Colors.grey.shade600)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: students.length,
        itemBuilder: (_, i) => _studentTile(students[i], ds, showRoute: showRoute),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return DefaultTabController(
      length: 1 + _routes.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Route Students'),
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              const Tab(text: 'All Students'),
              ..._routes.map((r) => Tab(text: r['name'] ?? '')),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: ds.cardPadding, vertical: ds.cardPadding * 0.5),
                    color: Colors.teal.shade50,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: ds.iconSize * 0.7, color: Colors.teal.shade700),
                        SizedBox(width: ds.cardPadding * 0.5),
                        Expanded(
                          child: Text(
                            '$_term, $_session — ${_allocations.length} student(s) using transportation',
                            style: TextStyle(fontSize: ds.subtitleFontSize, color: Colors.teal.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _studentList(_allocations, ds, showRoute: true),
                        ..._routes.map((r) => _studentList(
                              _allocations.where((a) => a['routeId'] == r['id']).toList(),
                              ds,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
