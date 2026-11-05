import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/remote/languages_api.dart';
import '../features/sync/widgets/common.dart';
import 'language_controller.dart';
import 'translations.dart';

final _languagesProvider = FutureProvider.autoDispose((ref) => ref.read(languageRepositoryProvider).languages());

enum _Phase { pick, preview, saved }

/// Screen 10 — Language & Translation (frames J1 picker, J2 preview, J3 saved with fallback).
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  _Phase _phase = _Phase.pick;
  String? _selected;
  Translations? _preview;
  LanguageInfo? _info;
  bool _busy = false;
  bool _savedRemotely = false;

  Future<void> _openPreview(LanguageInfo info) async {
    setState(() => _busy = true);
    try {
      final t = await ref.read(languageRepositoryProvider).load(info.code);
      await initializeDateFormatting(info.code);
      setState(() {
        _preview = t;
        _info = info;
        _phase = _Phase.preview;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('language.unavailable'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final remote = await ref.read(languageProvider.notifier).change(_info!.code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _savedRemotely = remote;
      _phase = _Phase.saved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(languageProvider).code;
    return Scaffold(
      appBar: AppBar(title: Text(tr('language.title'))),
      body: switch (_phase) {
        _Phase.pick => _picker(context, current),
        _Phase.preview => _previewView(context),
        _Phase.saved => _savedView(context),
      },
    );
  }

  // J1
  Widget _picker(BuildContext context, String current) {
    final async = ref.watch(_languagesProvider);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => StateMessage(
        icon: Icons.translate_rounded,
        title: tr('language.loadError'),
        body: '',
        actionLabel: tr('common.retry'),
        onAction: () => ref.invalidate(_languagesProvider),
      ),
      data: (result) {
        final selected = _selected ?? current;
        final choice = result.languages.where((l) => l.code == selected).firstOrNull;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (result.offline) ...[
              StatusBanner(text: tr('language.offlineList'), tone: BannerTone.neutral, icon: Icons.cloud_off_rounded),
              const SizedBox(height: 12),
            ],
            Text(tr('language.intro'), style: t.bodyLarge),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: selected,
              onChanged: (v) => setState(() => _selected = v),
              child: Card(
                child: Column(
                  children: [
                    for (final (i, l) in result.languages.indexed) ...[
                      if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                      RadioListTile<String>(
                        value: l.code,
                        title: Text(l.nativeName == l.name ? l.name : '${l.nativeName} · ${l.name}'),
                        subtitle: Text(_status(l)),
                        secondary: l.code == current
                            ? Chip(label: Text(tr('language.current')), visualDensity: VisualDensity.compact)
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.medication_outlined, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('language.neverTranslated'),
                    style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: choice == null || selected == current || _busy ? null : () => _openPreview(choice),
              child: Text(tr('language.save')),
            ),
          ],
        );
      },
    );
  }

  String _status(LanguageInfo l) {
    if (l.isDefault) return tr('language.completeDefault');
    if (l.complete) return l.reviewed ? tr('language.completeReviewed') : tr('language.completeUnreviewed');
    final pct = NumberFormat.decimalPattern().format((l.coverage * 100).floor());
    return '${tr('language.partial')}\n${tr('language.partialPercent', {'percent': pct})}';
  }

  // J2 — chrome in the current language, sample content in the candidate language.
  Widget _previewView(BuildContext context) {
    final p = _preview!;
    final info = _info!;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final time = DateFormat.Hm(info.code).format(now.subtract(const Duration(minutes: 2)));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr('language.preview', {'language': info.nativeName}),
          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(p.get('language.previewSyncStatus'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(p.get('language.previewPending', {'count': 3})),
                Text(
                  p.get('language.previewLastSynced', {
                    'time': time,
                    'ago': p.get('time.minutesAgo', {'n': 2}),
                  }),
                ),
                const SizedBox(height: 12),
                Text(p.get('language.previewLongLabel')),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {},
                  child: Text(p.get('language.previewLongButton'), textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(p.get('language.previewFallback'), style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(
          p.get('language.previewMissing', {'count': p.missingCount}),
          style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => setState(() => _phase = _Phase.pick),
                child: Text(tr('common.cancel')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? tr('language.saving') : tr('language.save'), textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // J3 — shown in the newly applied language.
  Widget _savedView(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = ref.watch(languageProvider);
    final partial = active.missingCount > 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatusBanner(
          text: tr('language.saved', {'language': _info!.nativeName}),
          tone: BannerTone.success,
          icon: Icons.check_circle_rounded,
        ),
        const SizedBox(height: 16),
        if (partial) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.status.warningBg, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('language.savedPartial'),
                  style: t.titleMedium?.copyWith(color: context.status.warningFg, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(tr('language.savedPartialBody'), style: t.bodyMedium?.copyWith(color: context.status.warningFg)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(_savedRemotely ? tr('language.savedEverywhere') : tr('language.savedLocal'), style: t.bodyMedium),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(tr('common.done'))),
      ],
    );
  }
}
