/// Summary screen (Member 11) — styled to match docs/design/08-summary-confirmed-day.svg
/// and 09-summary-report-pending.svg.
///
/// Rule from the design notes: a day without a confirmed report shows 'waiting'
/// (a dash), never zero. Figures come only from confirmed reports and invoices,
/// which is exactly what the API returns from daily_store_summaries.
library;

import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import 'dashboard_frame.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({
    super.key,
    this.apiClient,
    this.storeId = 'demo-store',
    this.activeTab = DashboardTab.summary,
    this.onTabSelected,
  });

  final ApiClient? apiClient;
  final String storeId;
  final DashboardTab activeTab;
  final ValueChanged<DashboardTab>? onTabSelected;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late final ApiClient _client;
  late Future<TrendResponse> _trend;
  late Future<StockNow> _stock;
  late DateTime _selectedDay;
  late Future<DailySummary> _summary;

  @override
  void initState() {
    super.initState();
    _client = widget.apiClient ?? ApiClient();
    _trend = _client.fetchTrend(widget.storeId);
    _stock = _client.fetchStockNow(widget.storeId);
    final DateTime nowIst = _nowIst();
    _selectedDay = DateTime(nowIst.year, nowIst.month, nowIst.day);
    _summary = _loadSummary(_selectedDay);
  }

  DateTime _nowIst() => DateTime.now().toUtc().add(
    const Duration(hours: 5, minutes: 30),
  );

  String _dayParam(DateTime d) =>
      d.toIso8601String().substring(0, 10);

  Future<DailySummary> _loadSummary(DateTime day) =>
      _client.fetchDailySummary(widget.storeId, date: _dayParam(day));

  void _reload() {
    if (!mounted) return;
    setState(() {
      _trend = _client.fetchTrend(widget.storeId);
      _stock = _client.fetchStockNow(widget.storeId);
      _summary = _loadSummary(_selectedDay);
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = day;
      _summary = _loadSummary(day);
    });
  }

  void _onTab(DashboardTab t) => widget.onTabSelected?.call(t);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: fontFamily, color: ink),
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: FutureBuilder<TrendResponse>(
              future: _trend,
              builder: (BuildContext context, AsyncSnapshot<TrendResponse> trendSnap) {
                final Widget header = DashboardHeader(
                  storeId: widget.storeId,
                  statusPill: '● Synced ${formatTime(_nowIst())}',
                  active: DashboardTab.summary,
                  onTab: _onTab,
                );
                if (trendSnap.connectionState == ConnectionState.waiting) {
                  return _LoadingListView(header: header);
                }
                if (trendSnap.hasError) {
                  return ListView(
                    children: <Widget>[
                      header,
                      const SizedBox(height: 24),
                      ErrorCard(
                        title: 'Could not load the summary',
                        message:
                            'The app could not reach the server, so nothing is '
                            'shown rather than old numbers presented as current.',
                        onRetry: _reload,
                      ),
                    ],
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: <Widget>[
                      header,
                      const SizedBox(height: 20),
                      const Text(
                        'Daily summary',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                      ),
                      const Text(
                        'Figures come from confirmed reports and invoices only.',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                      const SizedBox(height: 12),
                      _DayPicker(selected: _selectedDay, trend: trendSnap.data!, onSelect: _selectDay),
                      const Divider(height: 1, color: hairline),
                      const SizedBox(height: 4),
                      FutureBuilder<DailySummary>(
                        future: _summary,
                        builder: (
                          BuildContext context,
                          AsyncSnapshot<DailySummary> snap,
                        ) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          }
                          if (snap.hasError) {
                            return ErrorCard(
                              title: 'Could not load this day',
                              message: 'Check your connection and try again.',
                              onRetry: _reload,
                            );
                          }
                          return _Figures(summary: snap.data!);
                        },
                      ),
                      const SizedBox(height: 12),
                      _TrendChart(trend: trendSnap.data!, selected: _selectedDay, onSelect: _selectDay),
                      const SizedBox(height: 20),
                      FutureBuilder<StockNow>(
                        future: _stock,
                        builder: (
                          BuildContext context,
                          AsyncSnapshot<StockNow> stockSnap,
                        ) {
                          if (stockSnap.hasError) {
                            return const SizedBox.shrink();
                          }
                          return _StockNow(stock: stockSnap.data);
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingListView extends StatelessWidget {
  const _LoadingListView({required this.header});

  final Widget header;

  @override
  Widget build(BuildContext context) {
    Widget block(double height, {double width = double.infinity}) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: hairline,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return ListView(
      children: <Widget>[
        header,
        const SizedBox(height: 24),
        block(28, width: 140),
        block(14, width: 250),
        block(44),
        block(180),
        block(120),
      ],
    );
  }
}

/// Last 7 days as chips; the selected day is filled (frame 08 note 1/3).
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.selected, required this.trend, required this.onSelect});

  final DateTime selected;
  final TrendResponse trend;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<DateTime> days = trend.points
        .map((TrendPoint p) => p.summaryDate)
        .toList();
    return SizedBox(
      height: 56,
      child: Row(
        children: <Widget>[
          for (final DateTime day in days) ...<Widget>[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelect(day),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _sameDay(day, selected) ? hairline : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _sameDay(day, selected) ? secondary : hairline,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        formatDay(day).split(' ').first,
                        style: const TextStyle(fontSize: 11, color: secondary),
                      ),
                      Text(
                        '${day.day}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (day != days.last) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The figures grid: Sales / Purchases / Credit given / Credit collected /
/// Net credit change / Expired stock value. A missing figure is a dash (frames 08/09).
class _Figures extends StatelessWidget {
  const _Figures({required this.summary});

  final DailySummary summary;

  Widget _cell(String label, String value, String caption) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: const TextStyle(fontSize: 11, color: muted)),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      ),
      Text(caption, style: const TextStyle(fontSize: 10, color: muted)),
    ],
  );

  String _money(int? paise) => paise == null ? '—' : formatRupees(paise);

  @override
  Widget build(BuildContext context) {
    final bool pending = !summary.confirmed;
    final String? note = summary.note;
    final int? netCredit =
        summary.udhaarIssuedPaise != null && summary.udhaarCollectedPaise != null
            ? summary.udhaarIssuedPaise! - summary.udhaarCollectedPaise!
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (pending && note != null) ...<Widget>[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: muted),
            ),
            child: Text(note, style: const TextStyle(fontSize: 12)),
          ),
        ],
        if (summary.confirmed && summary.confirmedAt != null) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Report confirmed ${formatDay(summary.confirmedAt!)} at '
              '${formatTime(summary.confirmedAt!)}.',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _cell(
                'Sales',
                _money(summary.totalSalesPaise),
                pending ? 'Waiting for report' : 'Confirmed day',
              ),
            ),
            Expanded(
              child: _cell(
                'Purchases',
                _money(summary.totalPurchasesPaise),
                pending ? 'Waiting for report' : 'Confirmed invoices',
              ),
            ),
          ],
        ),
        const Divider(height: 24, color: hairline),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _cell(
                'Credit collected',
                _money(summary.udhaarCollectedPaise),
                'Payments received',
              ),
            ),
            Expanded(
              child: _cell(
                'Credit given',
                _money(summary.udhaarIssuedPaise),
                'Sold on udhaar',
              ),
            ),
          ],
        ),
        const Divider(height: 24, color: hairline),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _cell(
                'Net credit change',
                _money(netCredit),
                pending ? 'Waiting for report' : 'Credit book change',
              ),
            ),
            Expanded(
              child: _cell(
                'Expired stock value',
                _money(summary.expiredStockValuePaise),
                'Written off',
              ),
            ),
          ],
        ),
        const Divider(height: 24, color: hairline),
        _cell(
          'Low-stock SKUs',
          summary.lowStockSkuCount == null ? '—' : '${summary.lowStockSkuCount} items',
          'Below their reorder point',
        ),
      ],
    );
  }
}

/// Last-7-days bars: sales in ink, purchases in muted grey; a day with no
/// confirmed report shows no bar (frame 08 note 3).
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.trend, required this.selected, required this.onSelect});

  final TrendResponse trend;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<TrendPoint> points = trend.points;
    final double maxSales = points
        .map((TrendPoint p) => p.totalSalesPaise ?? 0)
        .fold(0.0, (double a, int b) => a > b ? a : b.toDouble());
    final double maxPurchases = points
        .map((TrendPoint p) => p.totalPurchasesPaise ?? 0)
        .fold(0.0, (double a, int b) => a > b ? a : b.toDouble());
    final double max = (maxSales > maxPurchases ? maxSales : maxPurchases).clamp(1, double.infinity);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Last 7 days',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _dot(ink, 'Sales'),
              const SizedBox(width: 12),
              _dot(muted, 'Purchases'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final TrendPoint p in points) ...<Widget>[
                  Expanded(
                    child: InkWell(
                      onTap: () => onSelect(p.summaryDate),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          if (p.totalSalesPaise != null)
                            Container(
                              height: 80 * (p.totalSalesPaise! / max),
                              color: ink,
                            ),
                          if (p.totalPurchasesPaise != null)
                            Container(
                              height: 30 * (p.totalPurchasesPaise! / max),
                              color: muted,
                            ),
                          if (p.totalSalesPaise == null && p.totalPurchasesPaise == null)
                            Container(height: 2, color: hairline),
                          const SizedBox(height: 4),
                          Text(
                            formatDay(p.summaryDate),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: _sameDay(p.summaryDate, selected)
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(width: 10, height: 10, color: c),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: secondary)),
    ],
  );
}

/// "Stock right now" section: dashes when the inventory module is not merged
/// (design frames 08/09 bottom section).
class _StockNow extends StatelessWidget {
  const _StockNow({this.stock});

  final StockNow? stock;

  @override
  Widget build(BuildContext context) {
    final StockNow? s = stock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Stock right now',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        Text(
          s == null
              ? 'Loading…'
              : (s.available
                    ? 'Not tied to the day above.'
                    : (s.note ?? 'Not available yet.')),
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        const Divider(height: 16, color: hairline),
        _row(
          s?.available == true ? '${s!.expiring30 ?? '—'} batches' : '—',
          s?.available == true && s!.expiring30ValuePaise != null
              ? 'Expires in 30 days, ${formatRupees(s.expiring30ValuePaise!)}'
              : 'Expires in 30 days',
        ),
        const Divider(height: 16, color: hairline),
        _row(
          s?.available == true ? '${s!.expiring60 ?? '—'} batches' : '—',
          'Expires in 31 to 60 days',
        ),
        const Divider(height: 16, color: hairline),
        _row(
          s?.available == true ? '${s!.expiring90 ?? '—'} batches' : '—',
          'Expires in 61 to 90 days',
        ),
        const Divider(height: 16, color: hairline),
        _row(
          s?.available == true ? '${s!.belowMinimum ?? '—'} items' : '—',
          s?.available == true && s!.outOfStock != null
              ? 'Below minimum, ${s.outOfStock} out'
              : 'Below minimum',
        ),
      ],
    );
  }

  Widget _row(String value, String label) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      Expanded(
        child: Text(label, style: const TextStyle(fontSize: 10, color: muted)),
      ),
    ],
  );
}
