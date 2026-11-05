import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/data/remote/integrations_api.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/data/remote/tickets_api.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/features/sync/domain/op_state.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/l10n/translations.dart';

import '../support/l10n.dart';

final _arg = RegExp(r'\{\s*([A-Za-z_]\w*)\s*[,}]');
Set<String> _args(String m) => _arg.allMatches(m).map((x) => x.group(1)!).toSet();

void main() {
  final en = loadCatalog('en');

  setUpAll(() => initializeDateFormatting('hi'));

  group('catalog integrity', () {
    test('every literal key used in the app exists in English', () {
      final used = <String>{};
      final call = RegExp(r'''\btr(?:OrNull)?\(\s*'([a-z][A-Za-z0-9_.]+)'(?=[,)])''');
      final preview = RegExp(r'''\bp\.get\(\s*'([a-z][A-Za-z0-9_.]+)'(?=[,)])''');
      for (final f in Directory('lib/modules/offline_sync_reliability').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        used.addAll(call.allMatches(src).map((m) => m.group(1)!));
        used.addAll(preview.allMatches(src).map((m) => m.group(1)!));
      }
      expect(used.length, greaterThan(150));
      final unknown = used.where((k) => !en.messages.containsKey(k)).toList()..sort();
      expect(unknown, isEmpty, reason: 'keys used in code but missing from en.json');
    });

    test('dynamic key families cover every enum value', () {
      for (final s in OpState.values) {
        expect(en.messages, contains('sync.state.${s.name}'));
      }
      for (final s in TicketStatus.values) {
        expect(en.messages, containsPair('ticket.status.${s.wire}', isNotEmpty));
        expect(en.messages, contains('ticket.step.${s.wire}'));
      }
      for (final p in TicketPriority.values) {
        expect(en.messages, contains('ticket.priority.${p.wire}'));
      }
      for (final c in TicketCategory.values) {
        expect(en.messages, contains('ticket.category.${c.wire}'));
      }
      for (final h in HealthStatus.values) {
        expect(en.messages, contains('health.status.${h.name}'));
      }
    });

    for (final code in ['hi', 'te', 'ta']) {
      test('$code: only known keys, placeholders identical to English', () {
        final c = loadCatalog(code);
        expect(c.code, code);
        expect(c.reviewed, isFalse, reason: 'machine-drafted catalogs must not claim human review');
        for (final e in c.messages.entries) {
          expect(en.messages, contains(e.key), reason: 'unknown key ${e.key}');
          expect(_args(e.value), _args(en.messages[e.key]!), reason: '${e.key} placeholders differ');
        }
      });
    }

    test('Hindi is complete; Telugu and Tamil are partial (shown as such in the picker)', () {
      expect(Translations(english: en, active: loadCatalog('hi')).coverage, 1);
      expect(Translations(english: en, active: loadCatalog('te')).coverage, inExclusiveRange(0.2, 1));
      expect(Translations(english: en, active: loadCatalog('ta')).coverage, inExclusiveRange(0.2, 1));
    });
  });

  group('runtime', () {
    test('missing keys fall back to English and are counted', () {
      final t = Translations(english: en, active: loadCatalog('te'));
      expect(t.get('sync.status.title'), 'సింక్ స్థితి');
      expect(t.get('ticket.form.submit'), 'Submit ticket');
      expect(t.missing, contains('ticket.form.submit'));
      expect(t.missingCount, greaterThan(100));
    });

    test('plurals and placeholders format per language', () {
      final enT = Translations(english: en);
      expect(enT.get('sync.indicator.offline', {'count': 1}), contains('1 change saved'));
      expect(enT.get('sync.indicator.offline', {'count': 3}), contains('3 changes saved'));
      expect(enT.get('language.previewMissing', {'count': 0}), 'All labels are translated.');
      expect(enT.get('sync.cancel.alreadyCommitted'), contains("can't"), reason: 'plain text keeps apostrophes');
      expect(enT.get('health.errorStale', {'time': '10:30'}), 'Couldn’t refresh · Showing the last check from 10:30.');

      final hi = Translations(english: en, active: loadCatalog('hi'));
      expect(hi.get('sync.status.progress', {'done': 3, 'total': 8}), '8 में से 3 आइटम सिंक हो रहे हैं');
      expect(hi.get('sync.run.synced', {'count': 1}), '1 बदलाव सिंक हुआ');
    });

    test('a malformed translation never breaks the screen', () {
      final broken = Catalog(code: 'xx', version: '1', messages: {'sync.status.progress': '{done, plural, one{oops'});
      final t = Translations(english: en, active: broken);
      expect(t.get('sync.status.progress', {'done': 1, 'total': 2}), 'Syncing 1 of 2 items');
    });

    test('compareVersions is numeric, not lexical', () {
      expect(compareVersions('2026.10.21.10', '2026.10.21.9'), greaterThan(0));
      expect(compareVersions('2026.10.21.1', '2026.10.21.1'), 0);
      expect(compareVersions('2026.9.1', '2026.10.1'), lessThan(0));
    });
  });
}
