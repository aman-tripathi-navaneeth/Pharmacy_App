/// Today screen (Member 11) — styled to match docs/design/01-today-default.svg
/// and the state frames 03 (empty), 04 (partial failure), 05 (error) and
/// 06 (loading skeleton).
///
/// Design tokens from the prototype (docs/design/):
/// * ink #222222, secondary text #555555, muted #8A8A8A, hairline #D9D9D9,
///   chip background #F3F3F3, screen surface white, canvas #FAFAFA.
/// * Urgency is shown by bar thickness (thick/medium/thin), never colour alone.
/// * A missing figure is a dash, never zero (API null → "—").
/// * Font: Inter (falls back to the system font until the Inter bundle is added).
library;

import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import 'dashboard_frame.dart';

const Color _ink = ink;
const Color _secondary = secondary;
const Color _muted = muted;
const Color _hairline = hairline;
const Color _chipBgLight = chipBg;
const Color _paper = paper;

const String _fontFamily = fontFamily;

/// Pixel-for-pixel styling reference of the prototype lives in docs/design/.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    this.apiClient,
    this.storeId = 'demo-store',
    this.activeTab = DashboardTab.today,
    this.onTabSelected,
  });

  final ApiClient? apiClient;
  final String storeId;
  final DashboardTab activeTab;
  final ValueChanged<DashboardTab>? onTabSelected;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late final ApiClient _client;
  late Future<TodayResponse> _future;

  String? _urgencyFilter;
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _client = widget.apiClient ?? ApiClient();
    _future = _client.fetchToday(widget.storeId);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _client.fetchToday(widget.storeId);
    });
  }

  Future<void> _snooze(Task task) async {
    // Tomorrow in India Standard Time, matching the backend's MAX window.
    final DateTime nowIst = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final DateTime tomorrowIst = DateTime(
      nowIst.year,
      nowIst.month,
      nowIst.day,
    ).add(const Duration(days: 1));
    final String until = tomorrowIst.toIso8601String().substring(0, 10);
    try {
      await _client.snooze(widget.storeId, task.key, until);
      if (mounted) {
        _reload();
      }
    } on ApiException catch (e) {
      if (mounted) {
        _showActionError(e.message);
      }
    } on Exception {
      if (mounted) {
        _showActionError(
          'Could not snooze this task. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _markDone(Task task) async {
    try {
      await _client.markDone(widget.storeId, task.key);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Marked done'),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () async {
                try {
                  await _client.reopen(widget.storeId, task.key);
                } on ApiException catch (e) {
                  if (mounted) {
                    _showActionError(e.message);
                  }
                  return;
                } on Exception {
                  if (mounted) {
                    _showActionError(
                      'Could not undo this action. Check your connection and try again.',
                    );
                  }
                  return;
                }
                if (mounted) {
                  _reload();
                }
              },
            ),
          ),
        );
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        _showActionError(e.message);
      }
    } on Exception {
      if (mounted) {
        _showActionError(
          'Could not mark this task done. Check your connection and try again.',
        );
      }
    }
  }

  void _showActionError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onTaskAction(String kind, Task task) {
    if (kind == 'snooze') {
      _snooze(task);
    } else if (kind == 'done') {
      _markDone(task);
    }
  }

  void _onPrimaryAction(Task task) {
    // Deep links to owning modules arrive with Member 3/4/7/10 screens.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${task.action.label} opens ${task.action.target} — screen not built yet',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: SafeArea(
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: _fontFamily, color: _ink),
          child: FutureBuilder<TodayResponse>(
            future: _future,
            builder:
                (BuildContext context, AsyncSnapshot<TodayResponse> snapshot) {
                  void onTab(DashboardTab t) => widget.onTabSelected?.call(t);
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _LoadingView(
                      storeId: widget.storeId,
                      activeTab: widget.activeTab,
                      onTab: onTab,
                    );
                  }
                  if (snapshot.hasError) {
                    return _ErrorView(
                      storeId: widget.storeId,
                      onRetry: _reload,
                      activeTab: widget.activeTab,
                      onTab: onTab,
                    );
                  }
                  final TodayResponse data = snapshot.data!;
                  // Frame 05: if the API answered but EVERY source failed, show the
                  // error state - never an "All clear" screen, which would lie.
                  final bool allSourcesFailed =
                      data.sourceStatus.isNotEmpty &&
                      data.failedSources.length == data.sourceStatus.length &&
                      data.tasks.isEmpty;
                  if (allSourcesFailed) {
                    final String names = data.failedSources
                        .map((SourceStatus s) => _categoryLabel(s.source))
                        .join(', ');
                    return _ErrorView(
                      storeId: widget.storeId,
                      onRetry: _reload,
                      activeTab: widget.activeTab,
                      onTab: onTab,
                      message:
                          "The store's data sources ($names) could not be "
                          'reached, so nothing is shown rather than an empty '
                          'screen presented as current. Tasks appear here as '
                          'soon as real data is available.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: _DataView(
                      data: data,
                      storeId: widget.storeId,
                      activeTab: widget.activeTab,
                      onTab: onTab,
                      urgencyFilter: _urgencyFilter,
                      categoryFilter: _categoryFilter,
                      onUrgencyFilter: (String? v) =>
                          setState(() => _urgencyFilter = v),
                      onCategoryFilter: (String? v) =>
                          setState(() => _categoryFilter = v),
                      onRetry: _reload,
                      onAction: _onTaskAction,
                      onPrimary: _onPrimaryAction,
                    ),
                  );
                },
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({
    required this.storeId,
    required this.activeTab,
    required this.onTab,
  });

  final String storeId;
  final DashboardTab activeTab;
  final ValueChanged<DashboardTab> onTab;

  @override
  Widget build(BuildContext context) {
    // Skeleton blocks in the same positions as real content. No spinner (design 06).
    Widget block(double height, {double width = double.infinity}) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _hairline,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return ListView(
      children: <Widget>[
        DashboardHeader(
          storeId: storeId,
          statusPill: '● Loading',
          active: activeTab,
          onTab: onTab,
        ),
        const SizedBox(height: 24),
        block(28, width: 100),
        block(14, width: 250),
        block(40),
        block(86),
        block(86),
        block(86),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.storeId,
    required this.onRetry,
    required this.activeTab,
    required this.onTab,
    this.message,
  });

  final String storeId;
  final VoidCallback onRetry;
  final DashboardTab activeTab;
  final ValueChanged<DashboardTab> onTab;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        DashboardHeader(
          storeId: storeId,
          statusPill: '● Could not sync',
          active: activeTab,
          onTab: onTab,
        ),
        const SizedBox(height: 24),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _muted),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const Text(
                "Could not load today's tasks",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message ??
                    'The app could not reach the server, so nothing is shown '
                        'rather than old numbers presented as current.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _muted),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Try again'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Renders the successful / partial data.
class _DataView extends StatelessWidget {
  const _DataView({
    required this.data,
    required this.storeId,
    required this.activeTab,
    required this.onTab,
    required this.urgencyFilter,
    required this.categoryFilter,
    required this.onUrgencyFilter,
    required this.onCategoryFilter,
    required this.onRetry,
    required this.onAction,
    required this.onPrimary,
  });

  final TodayResponse data;
  final String storeId;
  final DashboardTab activeTab;
  final ValueChanged<DashboardTab> onTab;
  final String? urgencyFilter;
  final String? categoryFilter;
  final ValueChanged<String?> onUrgencyFilter;
  final ValueChanged<String?> onCategoryFilter;
  final VoidCallback onRetry;
  final void Function(String kind, Task task) onAction;
  final void Function(Task task) onPrimary;

  @override
  Widget build(BuildContext context) {
    final List<SourceStatus> failed = data.failedSources;
    final String pill = failed.isEmpty
        ? (data.generatedAt == null
              ? '● Updated'
              : '● Updated ${_fmtTime(data.generatedAt!)}')
        : '● ${failed.length} sources unavailable';

    final int total =
        data.counts.urgent + data.counts.soon + data.counts.routine;
    final bool fullyEmpty = failed.isEmpty && total == 0;
    final String subtitle = fullyEmpty
        ? 'Nothing needs you right now.'
        : '$total things need you, most urgent first.';

    List<Task> tasks = data.tasks;
    // Buttons carry the display label ('Urgent'); tasks carry the API value
    // ('urgent'), so compare case-insensitively or the filter never matches.
    final String? urgencyKey = urgencyFilter?.toLowerCase();
    if (urgencyKey != null) {
      tasks = tasks.where((Task t) => t.urgency == urgencyKey).toList();
    }
    if (categoryFilter != null) {
      tasks = tasks.where((Task t) => t.category == categoryFilter).toList();
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: <Widget>[
        DashboardHeader(
          storeId: storeId,
          statusPill: pill,
          active: activeTab,
          onTab: onTab,
        ),
        const SizedBox(height: 20),
        const Text(
          'Today',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: _muted)),

        if (failed.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _PartialBanner(failed: failed, onRetry: onRetry),
        ],

        const SizedBox(height: 12),
        _UrgencyBar(
          counts: data.counts,
          selected: urgencyFilter,
          onSelect: onUrgencyFilter,
        ),

        const SizedBox(height: 12),
        _GlanceRow(glance: data.glance),

        const SizedBox(height: 12),
        _CategoryChips(
          tasks: data.tasks,
          total: total,
          selected: categoryFilter,
          onSelect: onCategoryFilter,
        ),

        const SizedBox(height: 4),
        if (fullyEmpty)
          _EmptyCard()
        else if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'No tasks in this filter.',
                style: TextStyle(fontSize: 13, color: _muted),
              ),
            ),
          )
        else ...<Widget>[
          for (int i = 0; i < tasks.length; i++) ...<Widget>[
            Divider(height: 1, thickness: 1, color: _hairline),
            _TaskRow(task: tasks[i], onAction: onAction, onPrimary: onPrimary),
          ],
          Divider(height: 1, thickness: 1, color: _hairline),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

String _fmtTime(DateTime t) => formatTime(t);

class _PartialBanner extends StatelessWidget {
  const _PartialBanner({required this.failed, required this.onRetry});

  final List<SourceStatus> failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final String names = failed
        .map((SourceStatus s) => _categoryLabel(s.source))
        .join(' and ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _chipBgLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _muted),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$names could not load, so those tasks and some totals are missing.',
              style: const TextStyle(fontSize: 12, color: _ink),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: _ink),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              minimumSize: const Size(64, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _UrgencyBar extends StatelessWidget {
  const _UrgencyBar({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final Counts counts;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<(String, int, Color, Color)> segments =
        <(String, int, Color, Color)>[
          ('Urgent', counts.urgent, _ink, Colors.white),
          ('Soon', counts.soon, _secondary, Colors.white),
          ('Routine', counts.routine, _hairline, _ink),
        ];
    return SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          for (final (String, int, Color, Color) seg in segments) ...<Widget>[
            Expanded(
              child: Material(
                color: seg.$3,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelect(selected == seg.$1 ? null : seg.$1),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: selected == seg.$1
                          ? Border.all(color: _ink, width: 2)
                          : null,
                    ),
                    child: Text(
                      '${seg.$2} ${seg.$1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: seg.$4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (seg != segments.last) const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }
}

class _GlanceRow extends StatelessWidget {
  const _GlanceRow({required this.glance});

  final Glance glance;

  @override
  Widget build(BuildContext context) {
    Widget cell(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _hairline),
          bottom: BorderSide(color: _hairline),
        ),
      ),
      child: Row(
        children: <Widget>[
          cell(
            glance.expiring30DaysValuePaise == null
                ? '—'
                : formatRupees(glance.expiring30DaysValuePaise!),
            'expiring in 30 days',
          ),
          Container(width: 1, height: 40, color: _hairline),
          cell(
            glance.itemsBelowMinimum == null
                ? '—'
                : '${glance.itemsBelowMinimum} items',
            'below minimum',
          ),
          Container(width: 1, height: 40, color: _hairline),
          cell(
            glance.creditToCollectPaise == null
                ? '—'
                : formatRupees(glance.creditToCollectPaise!),
            'credit to collect',
          ),
        ],
      ),
    );
  }
}

String _categoryLabel(String key) => switch (key) {
  'close' => 'Daily close',
  'expiry' => 'Expiry',
  'low_stock' => 'Low stock',
  'refill' => 'Refills',
  'credit' => 'Credit',
  'delivery' => 'Deliveries',
  'sync' => 'Sync',
  _ => key,
};

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.tasks,
    required this.total,
    required this.selected,
    required this.onSelect,
  });

  final List<Task> tasks;
  final int total;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final Map<String, int> counts = <String, int>{};
    for (final Task t in tasks) {
      counts[t.category] = (counts[t.category] ?? 0) + 1;
    }
    Iterable<Widget> chipFor(String? key, String label, int count) sync* {
      final bool active = selected == key;
      yield Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: active ? _ink : Colors.white,
          shape: StadiumBorder(
            side: BorderSide(color: active ? _ink : _hairline),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => onSelect(selected == key ? null : key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                '$label $count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: active ? Colors.white : _secondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ...chipFor(null, 'All', total),
          for (final MapEntry<String, int> e in counts.entries)
            ...chipFor(e.key, _categoryLabel(e.key), e.value),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _muted, style: BorderStyle.solid),
      ),
      child: Column(
        children: <Widget>[
          const Text(
            'All clear for today',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'No expiry, stock, refill, credit or delivery tasks are open.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _muted),
          ),
          const SizedBox(height: 6),
          const Text(
            'New tasks appear as the modules report them.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _secondary,
            ),
          ),
          const SizedBox(height: 16),
          // Next step per the design; disabled until the summary screen exists.
          Opacity(
            opacity: 0.4,
            child: OutlinedButton(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _ink),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text("Check yesterday's summary"),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onAction,
    required this.onPrimary,
  });

  final Task task;
  final void Function(String kind, Task task) onAction;
  final void Function(Task task) onPrimary;

  double get _barWidth => switch (task.urgency) {
    'urgent' => 6,
    'soon' => 4,
    _ => 2,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: _barWidth,
            margin: const EdgeInsets.only(top: 2, bottom: 6),
            decoration: BoxDecoration(
              color: _ink,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  task.detail,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _chipBgLight,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        _categoryLabel(task.category),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _secondary,
                        ),
                      ),
                    ),
                    if (task.reason.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: _hairline),
                        ),
                        child: Text(
                          task.reason,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _secondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    SizedBox(
                      height: 30,
                      child: FilledButton(
                        onPressed: () => onPrimary(task),
                        style: FilledButton.styleFrom(
                          backgroundColor: _ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Text(task.action.label),
                      ),
                    ),
                    TextButton(
                      onPressed: () => onAction('snooze', task),
                      style: TextButton.styleFrom(
                        foregroundColor: _secondary,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Snooze'),
                    ),
                    TextButton(
                      onPressed: () => onAction('done', task),
                      style: TextButton.styleFrom(
                        foregroundColor: _secondary,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Mark done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
