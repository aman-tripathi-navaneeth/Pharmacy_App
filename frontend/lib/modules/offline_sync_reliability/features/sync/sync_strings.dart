import 'package:intl/intl.dart';

import '../../l10n/translations.dart';
import 'domain/op_state.dart';

/// User-facing copy for the sync feature. Text lives in the translation catalogs
/// (`assets/l10n/*.json`); these getters only name the keys.
class SyncStrings {
  const SyncStrings._();

  static String time(DateTime t) => DateFormat.Hm().format(t.toLocal());

  static String relative(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inSeconds < 60) return tr('time.justNow');
    if (d.inMinutes < 60) return tr('time.minutesAgo', {'n': d.inMinutes});
    if (d.inHours < 24) return tr('time.hoursAgo', {'n': d.inHours});
    return DateFormat.MMMd().add_Hm().format(t.toLocal());
  }

  static String lastSync(DateTime? t, DateTime now) {
    if (t == null) return tr('sync.status.neverSynced');
    final local = t.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final when = day == today ? tr('time.today', {'time': time(local)}) : DateFormat.MMMd().add_Hm().format(local);
    return tr('sync.status.lastSync', {'when': when});
  }

  /// Translated message for a server/sync error code, else the server's own text.
  static String error(String? code, String? fallback, String defaultKey) {
    return (code == null ? null : trOrNull('sync.error.$code')) ?? fallback ?? tr(defaultKey);
  }

  static String errorWord(String code) =>
      trOrNull('sync.errorWord.$code') ?? code.toLowerCase().replaceAll('_', ' ');

  // Common
  static String get retry => tr('common.retry');
  static String get cancel => tr('common.cancel');
  static String get confirm => tr('common.confirm');

  // Indicator (A1–A4)
  static String online(String synced, int pending) => tr('sync.indicator.online', {'ago': synced, 'pending': pending});
  static String get never => tr('sync.indicator.never');
  static String offline(int pending) =>
      pending == 0 ? tr('sync.indicator.offlineEmpty') : tr('sync.indicator.offline', {'count': pending});
  static String syncing(int done, int total, String last) => total == 0
      ? tr('sync.indicator.syncingNoTotal', {'last': last})
      : tr('sync.indicator.syncing', {'done': done.clamp(0, total), 'total': total, 'last': last});
  static String lastSyncAt(DateTime t) => tr('sync.indicator.lastSyncAt', {'time': time(t)});
  static String get neverSynced => tr('sync.indicator.neverSynced');
  static String needsAttention(int n) => tr('sync.indicator.attention', {'count': n});
  static String queueWarning(int n, String age) => tr('sync.indicator.queueWarning', {'count': n, 'age': age});

  // Dashboard (B1–B5)
  static String get syncStatus => tr('sync.status.title');
  static String get pending => tr('sync.status.pending');
  static String get synced => tr('sync.status.synced');
  static String get failed => tr('sync.status.failed');
  static String get conflicts => tr('sync.status.conflicts');
  static String get syncNow => tr('sync.status.syncNow');
  static String get syncNowOffline => tr('sync.status.syncNowOffline');
  static String get retryEligible => tr('sync.status.retryEligible');
  static String get viewPending => tr('sync.status.viewPending');
  static String get integrationHealth => tr('sync.status.integrationHealth');
  static String get openHelp => tr('sync.status.openHelp');
  static String get allSynced => tr('sync.status.allSynced');
  static String get allSyncedBody => tr('sync.status.allSyncedBody');
  static String get offlinePaused => tr('sync.status.offlinePaused');
  static String get loadStatusError => tr('sync.status.loadError');
  static String get loadStatusErrorBody => tr('sync.status.loadErrorBody');
  static String get loadingStatus => tr('sync.status.loading');
  static String progress(int done, int total) => tr('sync.status.progress', {'done': done.clamp(0, total), 'total': total});

  // Run summaries (snackbars)
  static String get runOffline => tr('sync.run.offline');
  static String get runStopped => tr('sync.run.stopped');
  static String runPartial(int synced, int attention) => tr('sync.run.partial', {'synced': synced, 'attention': attention});
  static String runSynced(int n) => tr('sync.run.synced', {'count': n});
  static String runAttention(int n) => tr('sync.run.attention', {'count': n});
  static String get runUpToDate => tr('sync.run.upToDate');

  // Pending ops (C1–C5)
  static String get pendingOperations => tr('sync.pending.title');
  static String get all => tr('sync.pending.all');
  static String get noPending => tr('sync.pending.empty');
  static String get noPendingBody => tr('sync.pending.emptyBody');
  static String noMatch(String filter) => tr('sync.pending.noMatch', {'filter': filter});
  static String get clearFilter => tr('sync.pending.clearFilter');
  static String get loadOpsError => tr('sync.pending.loadError');
  static String get loadOpsErrorBody => tr('sync.pending.loadErrorBody');
  static String get review => tr('sync.pending.review');
  static String get cancelTitle => tr('sync.pending.cancelTitle');
  static String get cancelBody => tr('sync.pending.cancelBody');
  static String get keepIt => tr('sync.pending.keepIt');
  static String get cancelOperation => tr('sync.pending.cancelOperation');

  static String stateLabel(OpState s) => tr('sync.state.${s.name}');

  // Operation summaries
  static String get waitingForConnection => tr('sync.op.waitingForConnection');
  static String createdAt(DateTime t) => tr('sync.op.created', {'time': time(t)});
  static String get sending => tr('sync.op.sending');
  static String attempt(String attempts) => tr('sync.op.attempt', {'attempts': attempts});
  static String attemptsOf(int n, int max) => tr('sync.op.attemptsOf', {'n': n, 'max': max});
  static String get opNeedsAttention => tr('sync.op.needsAttention');
  static String get retrySoon => tr('sync.op.retrySoon');
  static String retryAt(DateTime t) => tr('sync.op.retryAt', {'time': time(t)});
  static String get reviewNeeded => tr('sync.op.reviewNeeded');
  static String get rejectedByServer => tr('sync.op.rejected');
  static String syncedAt(DateTime t) => tr('sync.op.syncedAt', {'time': time(t)});
  static String get cancelledState => tr('sync.op.cancelled');

  // Operation details (D1–D2)
  static String get operationDetails => tr('sync.details.title');
  static String get operationId => tr('sync.details.operationId');
  static String get serverId => tr('sync.details.serverId');
  static String get notConfirmed => tr('sync.details.notConfirmed');
  static String get attempts => tr('sync.details.attempts');
  static String get created => tr('sync.details.created');
  static String get lastAttempt => tr('sync.details.lastAttempt');
  static String get nextRetry => tr('sync.details.nextRetry');
  static String get manualRetryNeeded => tr('sync.details.manualRetryNeeded');
  static String get soon => tr('sync.details.soon');
  static String backoff(DateTime t) => tr('sync.details.backoff', {'time': time(t)});
  static String get nextAction => tr('sync.details.nextAction');
  static String get whatYouCanDo => tr('sync.details.whatYouCanDo');
  static String get retryNow => tr('sync.details.retryNow');
  static String get retrying => tr('sync.details.retrying');
  static String get viewCanonical => tr('sync.details.viewCanonical');
  static String get correctData => tr('sync.details.correctData');
  static String correctDataHint(String module) => tr('sync.details.correctDataHint', {'module': module});
  static String get contactSupport => tr('sync.details.contactSupport');
  static String get copyOperationId => tr('sync.details.copyId');
  static String get copied => tr('sync.details.copied');
  static String get opNotFound => tr('sync.details.notFound');
  static String get opNotFoundBody => tr('sync.details.notFoundBody');
  static String get canonicalTitle => tr('sync.details.canonicalTitle');
  static String canonicalModule(String m) => tr('sync.details.canonicalModule', {'module': m});
  static String canonicalServerId(String id) => tr('sync.details.canonicalServerId', {'id': id});
  static String canonicalVersion(int v) => tr('sync.details.canonicalVersion', {'version': v});
  static String canonicalNote(String m) => tr('sync.details.canonicalNote', {'module': m});

  // Conflict (E1–E3)
  static String get resolveConflict => tr('sync.conflict.title');
  static String get field => tr('sync.conflict.field');
  static String get server => tr('sync.conflict.server');
  static String get thisDevice => tr('sync.conflict.thisDevice');
  static String get updated => tr('sync.conflict.updated');
  static String get chooseVersion => tr('sync.conflict.chooseVersion');
  static String get keepServer => tr('sync.conflict.keepServer');
  static String get keepDevice => tr('sync.conflict.keepDevice');
  static String get reviewManually => tr('sync.conflict.reviewManually');
  static String get backToSyncStatus => tr('sync.conflict.backToStatus');

  /// "Shop phone and Address"
  static String joinFields(List<String> fields) => fields.length <= 1
      ? fields.join()
      : '${fields.sublist(0, fields.length - 1).join(', ')} ${tr('common.and')} ${fields.last}';
}
