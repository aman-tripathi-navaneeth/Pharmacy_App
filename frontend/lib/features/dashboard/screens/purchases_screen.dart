/// Purchase register screen (Member 11) — styled to match
/// docs/design/10-register-list.svg and 11-register-row-expanded.svg.
///
/// Lists only confirmed supplier invoices from the API. When the purchase module
/// has not been merged yet, the API answers available=false and this screen shows
/// an honest note — never an empty list pretending there are no invoices.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/api_client.dart';
import 'dashboard_frame.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({
    super.key,
    this.apiClient,
    this.storeId = 'demo-store',
    this.activeTab = DashboardTab.purchases,
    this.onTabSelected,
  });

  final ApiClient? apiClient;
  final String storeId;
  final DashboardTab activeTab;
  final ValueChanged<DashboardTab>? onTabSelected;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late final ApiClient _client;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  static const int _pageSize = 50;
  int _offset = 0;
  late Future<PurchaseRegisterResponse> _future;
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _client = widget.apiClient ?? ApiClient();
    _future = _client.fetchPurchaseRegister(widget.storeId);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _query = value.trim();
        _offset = 0;
        _future = _fetchPage();
      });
    });
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetchPage();
    });
  }

  Future<PurchaseRegisterResponse> _fetchPage() =>
      _client.fetchPurchaseRegister(
        widget.storeId,
        q: _query,
        limit: _pageSize,
        offset: _offset,
      );

  void _changePage(int offset) {
    setState(() {
      _offset = offset;
      _future = _fetchPage();
    });
  }

  void _onTab(DashboardTab t) => widget.onTabSelected?.call(t);

  String _csvField(String value) => '"${value.replaceAll('"', '""')}"';

  String _csv(PurchaseRegisterResponse data) {
    final StringBuffer b = StringBuffer('date,invoice,supplier,total\n');
    for (final PurchaseRegisterRow r in data.rows) {
      final fields = <String>[
        r.invoiceDate?.toIso8601String().substring(0, 10) ?? '',
        r.invoiceNo,
        r.supplier ?? '',
        (r.totalPaise / 100).toStringAsFixed(2),
      ];
      b.writeln(fields.map(_csvField).join(','));
    }
    b.writeln(',,TOTAL,${((data.totalPaise ?? 0) / 100).toStringAsFixed(2)}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: fontFamily, color: ink),
          child: FutureBuilder<PurchaseRegisterResponse>(
            future: _future,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<PurchaseRegisterResponse> snap,
                ) {
                  final Widget header = DashboardHeader(
                    storeId: widget.storeId,
                    statusPill: '● Synced ${formatTime(DateTime.now())}',
                    active: DashboardTab.purchases,
                    onTab: _onTab,
                  );
                  if (snap.connectionState == ConnectionState.waiting &&
                      snap.data == null) {
                    return _LoadingListView(header: header);
                  }
                  if (snap.hasError) {
                    return ListView(
                      children: <Widget>[
                        header,
                        const SizedBox(height: 24),
                        ErrorCard(
                          title: 'Could not load the register',
                          message:
                              'The app could not reach the server, so nothing is '
                              'shown rather than old numbers presented as current.',
                          onRetry: _reload,
                        ),
                      ],
                    );
                  }
                  final PurchaseRegisterResponse data = snap.data!;
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: <Widget>[
                        header,
                        const SizedBox(height: 20),
                        const Text(
                          'Purchase register',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text(
                          'Every confirmed supplier invoice.',
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _search,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search invoice or supplier',
                            hintStyle: const TextStyle(
                              fontSize: 13,
                              color: muted,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: hairline),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: ink),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!data.available)
                          ErrorCard(
                            title: 'Register not available yet',
                            message:
                                data.note ??
                                'The purchase module has not been merged yet.',
                            onRetry: _reload,
                          )
                        else if (data.rows.isEmpty)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: muted),
                            ),
                            child: Text(
                              _query.isEmpty
                                  ? 'No confirmed supplier invoices yet. Invoices '
                                        'appear here the moment they are confirmed.'
                                  : 'No confirmed invoices match "$_query".',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: muted,
                              ),
                            ),
                          )
                        else ...<Widget>[
                          _TableHead(),
                          for (final PurchaseRegisterRow r
                              in data.rows) ...<Widget>[
                            Divider(height: 1, thickness: 1, color: hairline),
                            _RegisterRow(
                              row: r,
                              expanded: _expandedId == r.invoiceId,
                              onToggle: () => setState(() {
                                _expandedId = _expandedId == r.invoiceId
                                    ? null
                                    : r.invoiceId;
                              }),
                            ),
                          ],
                          Divider(height: 1, thickness: 1, color: hairline),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            color: chipBg,
                            child: Row(
                              children: <Widget>[
                                Text(
                                  '${data.rows.length} invoices on this page',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  data.totalPaise == null
                                      ? '—'
                                      : formatRupees(data.totalPaise!),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (data.totalCount > _pageSize ||
                              _offset > 0) ...<Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  '${_offset + 1}–${_offset + data.rows.length} of ${data.totalCount}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                                Row(
                                  children: <Widget>[
                                    IconButton(
                                      tooltip: 'Previous page',
                                      onPressed: _offset == 0
                                          ? null
                                          : () => _changePage(
                                              _offset - _pageSize,
                                            ),
                                      icon: const Icon(Icons.chevron_left),
                                    ),
                                    IconButton(
                                      tooltip: 'Next page',
                                      onPressed:
                                          _offset + data.rows.length >=
                                              data.totalCount
                                          ? null
                                          : () => _changePage(
                                              _offset + _pageSize,
                                            ),
                                      icon: const Icon(Icons.chevron_right),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _csv(data)),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text('Page copied as CSV'),
                                    ),
                                  );
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ink,
                              side: const BorderSide(color: ink),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              minimumSize: const Size(160, 34),
                            ),
                            child: const Text('Copy page as CSV'),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
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
        block(28, width: 180),
        block(14, width: 220),
        block(40),
        block(36, width: 200),
        block(44),
        block(44),
      ],
    );
  }
}

class _TableHead extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: secondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: chipBg,
      child: Row(
        children: <Widget>[
          SizedBox(width: 64, child: Text('Date ↓', style: style)),
          SizedBox(width: 84, child: Text('Invoice', style: style)),
          Expanded(child: Text('Supplier', style: style)),
          Text('Total', style: style),
        ],
      ),
    );
  }
}

/// One register row (frame 10); tapped, it expands to the invoice's line
/// items (frame 11) when the API could read them.
class _RegisterRow extends StatelessWidget {
  const _RegisterRow({
    required this.row,
    required this.expanded,
    required this.onToggle,
  });

  final PurchaseRegisterRow row;
  final bool expanded;
  final VoidCallback onToggle;

  String _date(DateTime? d) => d == null ? '—' : '${d.day} ${d.month}';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 64,
                  child: Text(
                    _date(row.invoiceDate),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: Text(
                    row.invoiceNo,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    row.supplier ?? '—',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatRupees(row.totalPaise),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            color: paper,
            child: _ExpandedDetail(row: row),
          ),
      ],
    );
  }
}

class _ExpandedDetail extends StatelessWidget {
  const _ExpandedDetail({required this.row});

  final PurchaseRegisterRow row;

  static const TextStyle _head = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: muted,
  );
  static const TextStyle _cell = TextStyle(fontSize: 11);

  @override
  Widget build(BuildContext context) {
    final List<PurchaseLine> lines = row.lines ?? const <PurchaseLine>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          lines.isEmpty
              ? '${row.itemCount ?? '?'} items. Line details arrive when the '
                    'invoice-lines table is merged.'
              : '${row.itemCount ?? lines.length} items.',
          style: const TextStyle(fontSize: 11, color: secondary),
        ),
        const SizedBox(height: 8),
        if (lines.isNotEmpty) ...<Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: Text('Medicine', style: _head)),
              const SizedBox(width: 64, child: Text('Batch', style: _head)),
              const SizedBox(width: 72, child: Text('Expiry', style: _head)),
              SizedBox(
                width: 56,
                child: Text('Qty', textAlign: TextAlign.end, style: _head),
              ),
              SizedBox(
                width: 72,
                child: Text('Amount', textAlign: TextAlign.end, style: _head),
              ),
            ],
          ),
          const Divider(height: 8, color: hairline),
          for (final PurchaseLine l in lines) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l.medicine,
                    style: _cell,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(l.batchNo ?? '—', style: _cell),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    l.expiryDate == null
                        ? '—'
                        : '${l.expiryDate!.month}/${l.expiryDate!.year}',
                    style: _cell,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    l.quantity == null ? '—' : '${l.quantity!}',
                    textAlign: TextAlign.end,
                    style: _cell,
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    l.amountPaise == null ? '—' : formatRupees(l.amountPaise!),
                    textAlign: TextAlign.end,
                    style: _cell,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
      ],
    );
  }
}
