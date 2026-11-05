import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/reconciliation_repository.dart';
import '../models/reconciliation.dart';
import '../widgets/message_state.dart';
import 'count_session_screen.dart';

extension ReconStatusStyle on ReconStatus {
  Color get color => switch (this) {
        ReconStatus.inProgress => const Color(0xFF1565C0),
        ReconStatus.pendingApproval => const Color(0xFFEF6C00),
        ReconStatus.approved => const Color(0xFF2E7D32),
        ReconStatus.cancelled => const Color(0xFF757575),
      };
}

/// Reconciliation tab: history of stock counts + start a new one.
class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  late final ReconciliationRepository _repo = context.read<ReconciliationRepository>();
  final _scroll = ScrollController();

  List<Reconciliation> _items = [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _starting = false;
  String? _error;

  Reconciliation? get _open {
    for (final r in _items) {
      if (r.status.isOpen) return r;
    }
    return null;
  }

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
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.list();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _page = 1;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.list(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _total = page.total;
        _page++;
      });
    } on ApiException {
      // Ignore: scrolling again retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openSession(Reconciliation r) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CountSessionScreen(sessionId: r.id)),
    );
    if (mounted) _load();
  }

  Future<void> _start() async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _StartDialog(),
    );
    if (note == null || !mounted) return;
    setState(() => _starting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await _repo.start(note: note);
      if (!mounted) return;
      await _openSession(r);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return Scaffold(
      appBar: AppBar(title: const Text('Reconciliation')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: open != null
                    ? _OpenBanner(recon: open, onOpen: () => _openSession(open))
                    : FilledButton.icon(
                        onPressed: _starting || _loading ? null : _start,
                        icon: _starting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.fact_check_outlined),
                        label: const Text('Start new stock count'),
                      ),
              ),
            ),
            ..._body(),
          ],
        ),
      ),
    );
  }

  List<Widget> _body() {
    const pad = EdgeInsets.symmetric(horizontal: 16);
    if (_loading && _items.isEmpty) {
      return [
        SliverPadding(
          padding: pad,
          sliver: SliverList.builder(itemCount: 4, itemBuilder: (_, __) => const SkeletonCard()),
        ),
      ];
    }
    if (_error != null && _items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: MessageState(
            icon: Icons.cloud_off,
            title: 'Could not load stock counts',
            message: _error!,
            actionLabel: 'Retry',
            onAction: _load,
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: MessageState(
            icon: Icons.fact_check_outlined,
            title: 'No stock counts yet',
            message: 'Start a count to compare the shelf with the system and fix differences.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: pad,
        sliver: SliverList.builder(
          itemCount: _items.length + (_loadingMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= _items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final r = _items[i];
            return _CountCard(recon: r, onTap: () => _openSession(r));
          },
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }
}

class _OpenBanner extends StatelessWidget {
  const _OpenBanner({required this.recon, required this.onOpen});
  final Reconciliation recon;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.play_circle_outline),
        title: Text(recon.status == ReconStatus.inProgress
            ? 'A stock count is in progress'
            : 'A stock count is waiting for approval'),
        subtitle: const Text('Finish or cancel it before starting another.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.recon, required this.onTap});
  final Reconciliation recon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = recon.status.color;
    final when = DateFormat('dd MMM yyyy, hh:mm a').format(recon.createdAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(when,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.withValues(alpha: 0.5)),
                    ),
                    child: Text(recon.status.label,
                        style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${recon.linesCounted} of ${recon.linesTotal} batches counted'
                '${recon.linesWithVariance > 0 ? ' · ${recon.linesWithVariance} with differences' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
              Text('Started by ${recon.createdBy}', style: theme.textTheme.bodySmall),
              if (recon.note != null && recon.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(recon.note!, style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartDialog extends StatefulWidget {
  const _StartDialog();

  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Start stock count'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This takes a snapshot of the system stock for every batch in the store. '
            'Differences you find will be adjusted once a manager approves.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'e.g. Monthly count, shelf A–C',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _note.text), child: const Text('Start')),
      ],
    );
  }
}
