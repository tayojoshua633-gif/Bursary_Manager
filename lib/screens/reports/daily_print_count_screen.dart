import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/print_counter_helper.dart';

class DailyPrintCountScreen extends StatefulWidget {
  const DailyPrintCountScreen({super.key});

  @override
  State<DailyPrintCountScreen> createState() => _DailyPrintCountScreenState();
}

class _DailyPrintCountScreenState extends State<DailyPrintCountScreen> {
  Map<String, int> _printStats = {
    'bills': 0,
    'receipts': 0,
    'paymentHistory': 0,
    'receiptReprint': 0,
  };
  bool _loadingStats = true;
  int _totalDaysWithData = 0;
  int _totalPrintsAllTime = 0;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadPrintStats();
  }

  Future<void> _loadPrintStats() async {
    setState(() => _loadingStats = true);

    // Get stats for selected date
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final stats = await PrintCounterHelper.getStatsForDate(dateKey) ?? {
      'bills': 0,
      'receipts': 0,
      'paymentHistory': 0,
      'receiptReprint': 0,
    };

    final totalDays = await PrintCounterHelper.getTotalDaysWithData();
    final totalAllTime = await PrintCounterHelper.getTotalPrintsAllTime();

    setState(() {
      _printStats = stats;
      _totalDaysWithData = totalDays;
      _totalPrintsAllTime = totalAllTime;
      _loadingStats = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      await _loadPrintStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPrints = _printStats['bills']! +
        _printStats['receipts']! +
        _printStats['paymentHistory']! +
        _printStats['receiptReprint']!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Print Counter'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPrintStats,
            tooltip: 'Refresh Statistics',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Main Print Counter Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.shade50, Colors.blue.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.indigo.shade200),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.analytics_outlined, color: Colors.indigo.shade700, size: 28),
                            const SizedBox(width: 12),
                            Text(
                              'Print Activity',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                          ],
                        ),
                        // Date Navigation
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                                });
                                _loadPrintStats();
                              },
                              icon: Icon(Icons.chevron_left, color: Colors.indigo.shade700),
                              tooltip: 'Previous day',
                            ),
                            IconButton(
                              onPressed: _pickDate,
                              icon: Icon(Icons.calendar_today, color: Colors.indigo.shade700),
                              tooltip: 'Select date',
                            ),
                            IconButton(
                              onPressed: _selectedDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))
                                  ? () {
                                      setState(() {
                                        _selectedDate = _selectedDate.add(const Duration(days: 1));
                                      });
                                      _loadPrintStats();
                                    }
                                  : null,
                              icon: Icon(Icons.chevron_right, color: Colors.indigo.shade700),
                              tooltip: 'Next day',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event, size: 16, color: Colors.indigo.shade700),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.indigo.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_loadingStats)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      Column(
                        children: [
                          // Stats Grid
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'Bills',
                                  _printStats['bills']!,
                                  Icons.receipt_long,
                                  Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Receipts',
                                  _printStats['receipts']!,
                                  Icons.receipt,
                                  Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'Payment History',
                                  _printStats['paymentHistory']!,
                                  Icons.history,
                                  Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Receipt Reprint',
                                  _printStats['receiptReprint']!,
                                  Icons.print_outlined,
                                  Colors.purple,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Total
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.print, color: Colors.indigo.shade900, size: 26),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Total Prints Today',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.indigo.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade700,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    totalPrints.toString(),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Historical Summary
                          if (_totalDaysWithData > 0)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  Column(
                                    children: [
                                      Text(
                                        _totalDaysWithData.toString(),
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Days Tracked',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    height: 50,
                                    width: 1,
                                    color: Colors.blue.shade200,
                                  ),
                                  Column(
                                    children: [
                                      Text(
                                        _totalPrintsAllTime.toString(),
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Total All-Time',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This counter tracks all print activities from the thermal printer including bills, receipts, and payment histories.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
