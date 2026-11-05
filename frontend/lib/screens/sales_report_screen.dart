import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../utils/report_exporter.dart';
import '../utils/responsive.dart';
import '../widgets/app_shell.dart';

const Color _darkGreen = Color(0xFF0B4F3A);

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  bool _isLoading = true;
  String? _error;
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dateParam =>
      '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/reports/overview').replace(
              queryParameters: {'date': _dateParam},
            ),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Could not load report (${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (mounted) setState(() => _report = data);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load the report. Try again.');
      }
      debugPrint('Report load failed: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = picked);
      await _load();
    }
  }

  Future<void> _exportPdf() async {
    final report = _report;
    if (report == null) return;
    final sales = report['sales'] as Map<String, dynamic>? ?? {};
    final inventory = report['inventory'] as Map<String, dynamic>? ?? {};
    final customers = report['customers'] as Map<String, dynamic>? ?? {};
    final top = report['topMedicines'] as List<dynamic>? ?? [];
    await ReportExporter.exportPdf(
      context,
      fileName: 'sales-report-$_dateParam',
      title: 'Sales report · $_dateParam',
      headers: const ['Metric', 'Value'],
      rows: [
        ['Revenue', '₹${(sales['revenue'] as num?)?.toStringAsFixed(2) ?? '0.00'}'],
        ['Bills', '${sales['bills'] ?? 0}'],
        ['Paid', '₹${(sales['paid'] as num?)?.toStringAsFixed(2) ?? '0.00'}'],
        ['Credit due', '₹${(sales['due'] as num?)?.toStringAsFixed(2) ?? '0.00'}'],
        ['Average bill', '₹${(sales['averageBill'] as num?)?.toStringAsFixed(2) ?? '0.00'}'],
        ['Stock items', '${inventory['items'] ?? 0}'],
        ['Low stock', '${inventory['lowStock'] ?? 0}'],
        ['Expiring in 30 days', '${inventory['expiring30'] ?? 0}'],
        ['Stock value', '₹${(inventory['stockValue'] as num?)?.toStringAsFixed(2) ?? '0.00'}'],
        ['Customers', '${customers['total'] ?? 0}'],
        ['Outstanding udhaar', '₹${(customers['outstanding'] as num?)?.toStringAsFixed(2) ?? '0.00'}'],
        ...top.map(
          (entry) => [
            '${entry['medicineName']} (sold)',
            '${entry['quantity']} units · ₹${(entry['revenue'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      selectedTab: -1,
      showBack: true,
      showNewBillCta: false,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _darkGreen))
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _header(),
                  const SizedBox(height: 14),
                  _salesCards(),
                  const SizedBox(height: 16),
                  _trendCard(),
                  const SizedBox(height: 16),
                  _topMedicinesCard(),
                  const SizedBox(height: 16),
                  _stockAndCustomersCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sales & stock report',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF13302B),
                ),
              ),
              Text(
                'Day summary, trends and udhaar',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_month_rounded, size: 18),
          label: Text(_dateParam),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Export PDF',
          onPressed: _exportPdf,
          icon: const Icon(Icons.picture_as_pdf_rounded, color: _darkGreen),
        ),
      ],
    );
  }

  Widget _salesCards() {
    final sales = _report!['sales'] as Map<String, dynamic>? ?? {};
    final inventory = _report!['inventory'] as Map<String, dynamic>? ?? {};
    final cards = [
      ('Revenue', '₹${(sales['revenue'] as num?)?.toStringAsFixed(0) ?? '0'}', Icons.currency_rupee_rounded, _darkGreen),
      ('Bills', '${sales['bills'] ?? 0}', Icons.receipt_long_rounded, const Color(0xFF1F7A45)),
      ('Credit due', '₹${(sales['due'] as num?)?.toStringAsFixed(0) ?? '0'}', Icons.handshake_outlined, const Color(0xFFB86A00)),
      ('Low stock', '${inventory['lowStock'] ?? 0}', Icons.warning_amber_rounded, const Color(0xFFB42318)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = statColumns(constraints.maxWidth);
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: columns == 1 ? 3.4 : (columns == 2 ? 2.4 : 2.0),
          children: [
        for (final card in cards)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: card.$4.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: card.$4.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Icon(card.$3, color: card.$4, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.$2,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: card.$4,
                        ),
                      ),
                      Text(
                        card.$1,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF5A6E69)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ],
        );
      },
    );
  }

  Widget _trendCard() {
    final days = (_report!['last7Days'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final maxRevenue = days.fold<double>(
      1,
      (value, day) => ((day['revenue'] as num?)?.toDouble() ?? 0) > value
          ? (day['revenue'] as num).toDouble()
          : value,
    );
    return _panel(
      title: 'Last 7 days',
      child: SizedBox(
        height: 190,
        child: BarChart(
          BarChartData(
            maxY: maxRevenue * 1.2,
            barGroups: [
              for (var index = 0; index < days.length; index++)
                BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: (days[index]['revenue'] as num?)?.toDouble() ?? 0,
                      color: _darkGreen,
                      width: 22,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
            ],
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 32),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= days.length) {
                      return const SizedBox.shrink();
                    }
                    final date = days[index]['date']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        date.length >= 10 ? date.substring(8) : date,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: const FlGridData(show: true),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }

  Widget _topMedicinesCard() {
    final top = _report!['topMedicines'] as List<dynamic>? ?? [];
    return _panel(
      title: 'Top medicines today',
      child: top.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No sales recorded for this day.'),
            )
          : Column(
              children: [
                for (final raw in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            raw['medicineName']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '${raw['quantity']} sold',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF5A6E69)),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '₹${(raw['revenue'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _stockAndCustomersCard() {
    final inventory = _report!['inventory'] as Map<String, dynamic>? ?? {};
    final customers = _report!['customers'] as Map<String, dynamic>? ?? {};
    return _panel(
      title: 'Stock & customers',
      child: Column(
        children: [
          _kv('Stock value', '₹${(inventory['stockValue'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
          _kv('Expiring in 30 days', '${inventory['expiring30'] ?? 0}'),
          _kv('Expiring in 90 days', '${inventory['expiring90'] ?? 0}'),
          _kv('Customers', '${customers['total'] ?? 0}'),
          _kv('Customers with udhaar', '${customers['withDues'] ?? 0}'),
          _kv('Outstanding udhaar', '₹${(customers['outstanding'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF5A6E69))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE1E9E6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Color(0xFF13302B),
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
