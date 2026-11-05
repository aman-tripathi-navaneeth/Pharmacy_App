import '../../../data/local/app_database.dart';
import '../../../l10n/translations.dart';
import '../domain/offline_catalog.dart';
import '../domain/op_state.dart';
import '../domain/sync_config.dart';
import '../sync_strings.dart';
import 'common.dart';

/// Human-readable descriptions of an outbox op, shared by list and detail screens.
/// State codes (RETRY_WAIT, …) stay untranslated: they are identifiers users quote to support.
/// `label` is user data (e.g. "Sale S-1042") and is never translated.
extension OpPresentation on OutboxOp {
  bool exhausted(SyncConfig config) => state == OpState.retryWait && attemptCount >= config.maxAutoAttempts;

  String title(OfflineCatalog catalog) => '$label · ${catalog.moduleLabel(module)}';

  String attemptsText(SyncConfig config) => attemptCount <= config.maxAutoAttempts
      ? SyncStrings.attemptsOf(attemptCount, config.maxAutoAttempts)
      : '$attemptCount';

  String get _error => SyncStrings.error(lastErrorCode, lastErrorMessage, 'sync.banner.retryWait');

  /// One-line state summary, e.g. "RETRY_WAIT · Attempt 2 of 8 · Retry 10:31".
  String summary(SyncConfig config) {
    final parts = <String>[state.wireName];
    switch (state) {
      case OpState.queued:
        parts.add(SyncStrings.waitingForConnection);
        parts.add(SyncStrings.createdAt(createdAt));
      case OpState.inFlight:
        parts.add(SyncStrings.sending);
      case OpState.retryWait:
        parts.add(SyncStrings.attempt(attemptsText(config)));
        parts.add(exhausted(config)
            ? SyncStrings.opNeedsAttention
            : nextAttemptAt == null
                ? SyncStrings.retrySoon
                : SyncStrings.retryAt(nextAttemptAt!));
      case OpState.conflict:
        parts.add(SyncStrings.reviewNeeded);
        parts.add(SyncStrings.createdAt(createdAt));
      case OpState.failedPermanent:
        parts.add(SyncStrings.error(lastErrorCode, lastErrorMessage, 'sync.op.rejected'));
      case OpState.synced:
        if (syncedAt != null) parts.add(SyncStrings.syncedAt(syncedAt!));
      case OpState.cancelled:
        parts.add(SyncStrings.cancelledState);
    }
    return parts.join(' · ');
  }

  BannerTone get tone => switch (state) {
        OpState.failedPermanent => BannerTone.error,
        OpState.conflict || OpState.retryWait => BannerTone.warning,
        OpState.synced => BannerTone.success,
        OpState.queued || OpState.inFlight => BannerTone.info,
        OpState.cancelled => BannerTone.neutral,
      };

  /// Banner text, e.g. "RETRY_WAIT · Network timed out. Safe to retry."
  String bannerText(SyncConfig config) => '${state.wireName} · ${switch (state) {
        OpState.queued => tr('sync.banner.queued'),
        OpState.inFlight => tr('sync.banner.inFlight'),
        OpState.retryWait => _error,
        OpState.conflict => SyncStrings.error(lastErrorCode, lastErrorMessage, 'sync.banner.conflict'),
        OpState.failedPermanent => SyncStrings.error(lastErrorCode, lastErrorMessage, 'sync.banner.failed'),
        OpState.synced => tr('sync.banner.synced'),
        OpState.cancelled => switch (resolution) {
            'KEEP_SERVER' => tr('sync.banner.keptServer'),
            'KEEP_DEVICE' => tr('sync.banner.keptDevice'),
            _ => tr('sync.banner.cancelled'),
          },
      }}';

  String nextActionText(SyncConfig config, OfflineCatalog catalog) {
    final noun = catalog.lookup(module, operationType)?.displayTitle.toLowerCase() ?? tr('sync.next.genericNoun');
    return switch (state) {
      OpState.queued => tr('sync.next.queued'),
      OpState.inFlight => tr('sync.next.inFlight'),
      OpState.retryWait when exhausted(config) =>
        tr('sync.next.retryExhausted', {'max': config.maxAutoAttempts, 'noun': noun}),
      OpState.retryWait => tr('sync.next.retry', {'noun': noun}),
      OpState.conflict => tr('sync.next.conflict'),
      OpState.failedPermanent => tr('sync.next.failed'),
      OpState.synced => tr('sync.next.synced'),
      OpState.cancelled => tr('sync.next.cancelled'),
    };
  }
}
