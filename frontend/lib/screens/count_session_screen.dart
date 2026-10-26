import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../data/reconciliation_repository.dart';
import '../models/expiry.dart' show formatQty;
import '../models/reconciliation.dart';
import '../widgets/message_state.dart';
import 'reconciliation_screen.dart' show ReconStatusStyle;

/// One stock count: enter counted quantities, submit, and (managers) approve.
class CountSessionScreen extends StatefulWidget {
  const CountSessionScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<CountSessionScreen> createState() => _CountSessionScreenState();
}

class _CountSessionScreenState extends State<CountSessionScreen> {
  late final ReconciliationRepository _repo = context.read<ReconciliationRepository>();
  final _scroll = ScrollController();

  Reconciliation? _recon;
  List<ReconLine> _lines = [];
  int _total = 0;
  int _page = 1;
  String _view = 'all'; // all | uncounted | variance
  String _query = '';
  Timer? _searchDebounce;
  Timer? _autosave;

  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false;
  bool _saving = false;
  String? _error;
  String? _actionError;

  /// Edits not yet sent to the server (null value = cleared).
  final Map<String, double?> _pending = {};
  final Set<String> _invalid = {};
  final Map<String, TextEditingController> _ctrls = {};

  bool get _editable => _recon?.status == ReconStatus.inProgress;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _autosave?.cancel();
    // Best effort: don't lose edits when leaving the screen.
    if (_pending.isNotEmpty) {
      unawaited(_repo.saveCounts(widget.sessionId, Map.of(_pending)).catchError((_) {}));
    }
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _flush(silent: true);
      final d = await _repo.detail(widget.sessionId, view: _view, query: _query);
      if (!mounted) return;
      setState(() {
        _recon = d.recon;
        _lines = d.lines;
        _total = d.total;
        _page = 1;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _lines.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final d = await _repo.detail(widget.sessionId, view: _view, query: _query, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _lines = [..._lines, ...d.lines];
        _total = d.total;
        _page++;
      });
    } on ApiException {
      // Ignore: scrolling again retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setView(String v) {
    if (v == _view) return;
    _view = v;
    _load();
  }

  void _onSearch(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (v == _query) return;
      _query = v;
      _load();
    });
  }

  // ------------------------------------------------------------------ editing
  TextEditingController _ctrl(ReconLine l) => _ctrls.putIfAbsent(
        l.batchId,
        () => TextEditingController(
          text: _pending.containsKey(l.batchId)
              ? (_pending[l.batchId] == null ? '' : formatQty(_pending[l.batchId]!))
              : (l.countedBase == null ? '' : formatQty(l.countedBase!)),
        ),
      );

  double? _currentCount(ReconLine l) =>
      _pending.containsKey(l.batchId) ? _pending[l.batchId] : l.countedBase;

  void _onCountChanged(ReconLine l, String text) {
    final t = text.trim();
    setState(() {
      if (t.isEmpty) {
        _invalid.remove(l.batchId);
        _pending[l.batchId] = null;
      } else {
        final n = double.tryParse(t);
        if (n == null || n < 0) {
          _invalid.add(l.batchId);
          _pending.remove(l.batchId);
        } else {
          _invalid.remove(l.batchId);
          _pending[l.batchId] = n;
        }
      }
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 1500), () => _flush(silent: true));
  }

  /// Sends pending edits. Returns false if it failed.
  Future<bool> _flush({bool silent = false}) async {
    if (_pending.isEmpty) return true;
    final batch = Map<String, double?>.of(_pending);
    if (mounted) setState(() => _saving = true);
    try {
      await _repo.saveCounts(widget.sessionId, batch);
      if (!mounted) return true;
      setState(() {
        batch.forEach((id, v) {
          // Only drop what we sent; the user may have typed more meanwhile.
          if (_pending.containsKey(id) && _pending[id] == v) _pending.remove(id);
        });
        _lines = [
          for (final l in _lines) batch.containsKey(l.batchId) ? l.withCount(batch[l.batchId]) : l,
        ];
        _actionError = null;
      });
      return true;
    } on ApiException catch (e) {
      if (mounted && !silent) setState(() => _actionError = e.message);
      if (mounted && silent) setState(() => _actionError = 'Could not save counts. ${e.message}');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------------ actions
  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await job();
    } on ApiException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_invalid.isNotEmpty) {
      setState(() => _actionError = 'Fix the quantities marked in red first.');
      return;
    }
    final r = _recon!;
    final counted = r.linesCounted;
    final skipped = r.linesTotal - counted;
    if (!await _confirm(
      'Submit this count?',
      '$counted of ${r.linesTotal} batches counted'
      '${skipped > 0 ? '. The $skipped batches you did not count will be left unchanged' : ''}. '
      'You cannot edit counts after submitting.',
      'Submit',
    )) {
      return;
    }
    await _run(() async {
      if (!await _flush()) return;
      await _repo.submit(widget.sessionId);
      _view = 'variance';
      await _load();
    });
  }

  Future<void> _approve() async {
    if (!await _confirm(
      'Approve and post adjustments?',
      'Stock will be corrected for ${_recon!.linesWithVariance} batches and recorded in the '
      'stock ledger. This cannot be undone.',
      'Approve & post',
    )) {
      return;
    }
    await _run(() async {
      await _repo.approve(widget.sessionId);
      await _load();
    });
  }

  Future<void> _cancel() async {
    if (!await _confirm(
      'Cancel this count?',
      'Nothing will be changed in stock. You can start a new count afterwards.',
      'Cancel count',
    )) {
      return;
    }
    await _run(() async {
      _pending.clear();
      await _repo.cancel(widget.sessionId);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  // ---------------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final r = _recon;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock count'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (r != null && r.status.isOpen)
            PopupMenuButton<String>(
              onSelected: (_) => _busy ? null : _cancel(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancel count'))],
            ),
        ],
      ),
      body: _body(),
      bottomNavigationBar: r == null ? null : _actions(r),
    );
  }

  Widget _body() {
    if (_loading && _recon == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _recon == null) {
      return MessageState(
        icon: Icons.cloud_off,
        title: 'Could not load this count',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    final r = _recon!;
    return Column(
      children: [
        _header(r),
        Expanded(
          child: _lines.isEmpty
              ? (_loading
                  ? const Center(child: CircularProgressIndicator())
                  : MessageState(
                      icon: Icons.inventory_2_outlined,
                      title: _query.trim().isNotEmpty ? 'No matching batches' : _emptyTitle(),
                      message: _view == 'all' ? 'Nothing to show.' : 'Try the All filter.',
                    ))
              : ListView.builder(
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _lines.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _lines.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final l = _lines[i];
                    return _LineTile(
                      key: ValueKey(l.batchId),
                      line: l,
                      controller: _ctrl(l),
                      counted: _currentCount(l),
                      editable: _editable && !_busy,
                      invalid: _invalid.contains(l.batchId),
                      onChanged: (t) => _onCountChanged(l, t),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _emptyTitle() => switch (_view) {
        'uncounted' => 'Everything has been counted',
        'variance' => 'No differences found',
        _ => 'No batches',
      };

  Widget _header(Reconciliation r) {
    final theme = Theme.of(context);
    final c = r.status.color;
    final progress = r.linesTotal == 0 ? 0.0 : r.linesCounted / r.linesTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(r.createdAt),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.withValues(alpha: 0.5)),
                ),
                child: Text(r.status.label,
                    style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress, minHeight: 6),
          const SizedBox(height: 4),
          Text(
            '${r.linesCounted} of ${r.linesTotal} counted · ${r.linesWithVariance} with differences',
            style: theme.textTheme.bodySmall,
          ),
          if (_actionError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_actionError!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          const SizedBox(height: 8),
          TextField(
            onChanged: _onSearch,
            decoration: InputDecoration(
              hintText: 'Search medicine or batch number',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final v in const [
                ('all', 'All'),
                ('uncounted', 'Not counted'),
                ('variance', 'Differences'),
              ])
                ChoiceChip(
                  label: Text(v.$2),
                  selected: _view == v.$1,
                  onSelected: (_) => _setView(v.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget? _actions(Reconciliation r) {
    if (!r.status.isOpen) return null; // approved / cancelled: read-only

    final Widget child;
    if (r.status == ReconStatus.inProgress) {
      child = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy || _saving || _pending.isEmpty
                  ? null
                  : () => _run(() async {
                        await _flush();
                      }),
              child: Text(_pending.isEmpty ? 'Saved' : 'Save progress'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy ? const _Spinner() : const Text('Submit'),
            ),
          ),
        ],
      );
    } else if (AppConfig.canApprove) {
      child = FilledButton(
        onPressed: _busy ? null : _approve,
        child: _busy ? const _Spinner() : const Text('Approve & post adjustments'),
      );
    } else {
      child = const Text(
        'Submitted. An owner or manager needs to approve before stock changes.',
        textAlign: TextAlign.center,
      );
    }
    return SafeArea(
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: child),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    super.key,
    required this.line,
    required this.controller,
    required this.counted,
    required this.editable,
    required this.invalid,
    required this.onChanged,
  });

  final ReconLine line;
  final TextEditingController controller;
  final double? counted;
  final bool editable;
  final bool invalid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variance = counted == null ? null : counted! - line.systemBase;
    final expiry =
        line.expiryDate == null ? 'No expiry' : 'Exp ${DateFormat('MM/yyyy').format(line.expiryDate!)}';

    Color vColor = theme.colorScheme.outline;
    String vText = 'Not counted';
    if (variance != null) {
      if (variance.abs() < 1e-9) {
        vColor = const Color(0xFF2E7D32);
        vText = 'Matches';
      } else if (variance < 0) {
        vColor = const Color(0xFFC62828);
        vText = 'Short ${formatQty(-variance)} ${line.baseUnit}';
      } else {
        vColor = const Color(0xFFEF6C00);
        vText = 'Extra ${formatQty(variance)} ${line.baseUnit}';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: vColor.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.productName,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Batch ${line.batchNumber} · $expiry', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('System: ${formatQty(line.systemBase)} ${line.baseUnit}',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(vText,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: vColor, fontWeight: FontWeight.w600)),
                  if (line.transactionId != null)
                    Text('Posted · ${line.transactionId}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 104,
              child: TextField(
                controller: controller,
                enabled: editable,
                onChanged: onChanged,
                textAlign: TextAlign.end,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Counted',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  errorText: invalid ? 'Invalid' : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
