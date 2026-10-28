import 'package:intl/intl.dart';

import '../../data/remote/tickets_api.dart';
import '../../l10n/translations.dart';
import '../sync/sync_strings.dart';

/// Copy for screens 7–9 (Figma rows G–I). Text lives in the translation catalogs.
class TicketStrings {
  const TicketStrings._();

  // List (G)
  static String get supportTickets => tr('ticket.list.title');
  static String get newTicketAction => tr('ticket.list.new');
  static String get searchHint => tr('ticket.list.searchHint');
  static String get clearSearch => tr('ticket.list.clearSearch');
  static String get status => tr('ticket.field.status');
  static String get category => tr('ticket.field.category');
  static String get priority => tr('ticket.field.priority');
  static String get any => tr('ticket.list.any');
  static String get emptyTitle => tr('ticket.list.emptyTitle');
  static String get emptyBody => tr('ticket.list.emptyBody');
  static String get createTicket => tr('ticket.list.create');
  static String get noMatchTitle => tr('ticket.list.noMatchTitle');
  static String get noMatchBody => tr('ticket.list.noMatchBody');
  static String get clearFilters => tr('ticket.list.clearFilters');
  static String get loadError => tr('ticket.list.loadError');
  static String get loadErrorBody => tr('ticket.list.loadErrorBody');
  static String get loadMore => tr('ticket.list.loadMore');
  static String get loading => tr('ticket.list.loading');
  static String get replyNeeded => tr('ticket.list.replyNeeded');
  static String listMeta(TicketSummary t, DateTime now) => tr('ticket.list.meta', {
    'priority': priorityLabel(t.priority),
    'status': statusLabel(t.status),
    'updated': updated(t.updatedAt, now),
  });
  static String filterValue(String filter, String value) => tr('ticket.list.filterValue', {'filter': filter, 'value': value});

  // Create (H)
  static String get newTicket => tr('ticket.form.title');
  static String get subject => tr('ticket.form.subject');
  static String get subjectHelp => tr('ticket.form.subjectHelp');
  static String get description => tr('ticket.form.description');
  static String get descriptionHint => tr('ticket.form.descriptionHint');
  static String get secretsWarning => tr('ticket.form.secretsWarning');
  static String get categoryLabel => tr('ticket.form.category');
  static String get selectCategory => tr('ticket.form.selectCategory');
  static String get relatedOperation => tr('ticket.form.relatedOperation');
  static String get relatedOperationHelp => tr('ticket.form.relatedOperationHelp');
  static String get removeRelated => tr('ticket.form.removeRelated');
  static String get attachment => tr('ticket.form.attachment');
  static String get addFile => tr('ticket.form.addFile');
  static String get removeAttachment => tr('ticket.form.removeAttachment');
  static String get uploading => tr('ticket.form.uploading');
  static String get uploadFailed => tr('ticket.form.uploadFailed');
  static String get waitUpload => tr('ticket.form.waitUpload');
  static String get submit => tr('ticket.form.submit');
  static String get submitting => tr('ticket.form.submitting');
  static String get subjectError => tr('ticket.form.subjectError');
  static String get subjectTooLong => tr('ticket.form.subjectTooLong');
  static String get descriptionError => tr('ticket.form.descriptionError');
  static String get descriptionTooLong => tr('ticket.form.descriptionTooLong');
  static String get categoryError => tr('ticket.form.categoryError');
  static String get offlineSubmit => tr('ticket.form.offline');
  static String get unreachable => tr('ticket.form.unreachable');
  static String created(String number) => tr('ticket.form.created', {'number': number});
  static String get createdBody => tr('ticket.form.createdBody');
  static String createdMeta(TicketDetail t) => tr('ticket.form.createdMeta', {
    'status': statusLabel(t.status),
    'priority': priorityLabel(t.priority),
    'category': categoryName(t.category),
  });
  static String get viewTicket => tr('ticket.form.viewTicket');
  static String get backToList => tr('ticket.form.backToList');
  static String get discardTitle => tr('ticket.form.discardTitle');
  static String get discardBody => tr('ticket.form.discardBody');
  static String get keepEditing => tr('ticket.form.keepEditing');
  static String get discard => tr('ticket.form.discard');
  static String get fileTooLarge => tr('ticket.form.fileTooLarge');
  static String get fileTypeNotAllowed => tr('ticket.form.fileTypeNotAllowed');
  static String get tooManyFiles => tr('ticket.form.tooManyFiles');

  // Detail (I)
  static String get fallbackTitle => tr('ticket.detail.fallbackTitle');
  static String get notFound => tr('ticket.detail.notFound');
  static String get notFoundBody => tr('ticket.detail.notFoundBody');
  static String get detailLoadError => tr('ticket.detail.loadError');
  static String get detailLoadErrorBody => tr('ticket.detail.loadErrorBody');
  static String detailMeta(TicketDetail t, DateTime now) => tr('ticket.detail.meta', {
    'priority': priorityLabel(t.priority),
    'category': categoryName(t.category),
    'created': SyncStrings.time(t.createdAt),
    'updated': updated(t.updatedAt, now),
  });
  static String get waitingBanner => tr('ticket.detail.waitingBanner');
  static String related(String text) => tr('ticket.detail.related', {'text': text});
  static String statusChanged(TicketStatus s, DateTime t) =>
      tr('ticket.detail.statusChanged', {'status': statusLabel(s), 'time': SyncStrings.time(t)});
  static String get replyHint => tr('ticket.detail.replyHint');
  static String get connectToReply => tr('ticket.detail.connectToReply');
  static String get send => tr('ticket.detail.send');
  static String get sendFailed => tr('ticket.detail.sendFailed');
  static String get closedNote => tr('ticket.detail.closedNote');
  static String get closeTicket => tr('ticket.detail.closeTicket');
  static String get closeTitle => tr('ticket.detail.closeTitle');
  static String get closeBody => tr('ticket.detail.closeBody');
  static String get team => tr('ticket.detail.support');
  static String get you => tr('ticket.detail.you');
  static String get teammate => tr('ticket.detail.teammate');
  static String statusA11y(TicketStatus s) => tr('ticket.detail.statusA11y', {'status': statusLabel(s)});

  static String statusLabel(TicketStatus s) => tr('ticket.status.${s.wire}');

  /// Short labels for the lifecycle steps (I1).
  static String stepLabel(TicketStatus s) => tr('ticket.step.${s.wire}');
  static String priorityLabel(TicketPriority p) => tr('ticket.priority.${p.wire}');
  static String categoryName(TicketCategory c) => tr('ticket.category.${c.wire}');

  static String updated(DateTime t, DateTime now) {
    final local = t.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = today.difference(day).inDays;
    if (days == 0) return SyncStrings.time(local);
    if (days == 1) return tr('time.yesterday');
    if (days < 7) return tr('time.daysAgo', {'n': days});
    return DateFormat.MMMd().format(local);
  }

  static String fileSize(int bytes) => bytes < 1024 * 1024
      ? '${NumberFormat.decimalPattern().format((bytes / 1024).ceil())} KB'
      : '${NumberFormat('0.0').format(bytes / (1024 * 1024))} MB';
}
