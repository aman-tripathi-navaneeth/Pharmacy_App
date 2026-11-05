import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_store/app/theme.dart';
import 'package:medical_store/data/local/app_database.dart';
import 'package:medical_store/data/remote/api_client.dart';
import 'package:medical_store/data/remote/languages_api.dart';
import 'package:medical_store/l10n/language_controller.dart';
import 'package:medical_store/l10n/language_repository.dart';
import 'package:medical_store/l10n/language_screen.dart';
import 'package:medical_store/l10n/translations.dart';

import '../support/l10n.dart';

class FakeLanguagesApi implements LanguagesApi {
  bool offline = false;
  final saved = <String>[];
  Catalog? newer;

  ApiException get _down => const ApiNetworkException('NETWORK_UNAVAILABLE', 'offline', isTimeout: false);

  @override
  Future<List<LanguageInfo>> languages() async {
    if (offline) throw _down;
    return [
      const LanguageInfo(code: 'en', name: 'English', nativeName: 'English', isDefault: true, catalogVersion: '1', reviewed: true, coverage: 1, missingCount: 0),
      const LanguageInfo(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी', isDefault: false, catalogVersion: '1', reviewed: true, coverage: 1, missingCount: 0),
      const LanguageInfo(code: 'te', name: 'Telugu', nativeName: 'తెలుగు', isDefault: false, catalogVersion: '1', reviewed: false, coverage: 0.27, missingCount: 267),
    ];
  }

  @override
  Future<Catalog?> catalog(String code, {String? knownVersion}) async {
    if (offline) throw _down;
    return newer != null && newer!.code == code ? newer : null;
  }

  @override
  Future<String?> myLanguage() async => null;

  @override
  Future<void> setMyLanguage(String code) async {
    if (offline) throw _down;
    saved.add(code);
  }
}

void main() {
  late AppDatabase db;
  late FakeLanguagesApi api;
  late LanguageRepository repo;

  setUp(() {
    useEnglish();
    db = AppDatabase(NativeDatabase.memory());
    api = FakeLanguagesApi();
    repo = LanguageRepository(dao: db.outboxDao, api: api, bundle: DiskBundle());
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        languageRepositoryProvider.overrideWithValue(repo),
        initialTranslationsProvider.overrideWithValue(Translations.current),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const LanguageScreen()),
    ));
    await settle(tester);
  }

  testWidgets('J1 → J2 → J3: preview in Telugu, save, partial-translation notice', (tester) async {
    await pump(tester);
    expect(find.text('Choose the language for app labels, sync messages and tickets.'), findsOneWidget);
    expect(find.text('Complete · Default'), findsOneWidget);
    expect(find.text('Complete · Reviewed'), findsOneWidget);
    expect(find.textContaining('Partial · Missing labels show in English'), findsOneWidget);
    expect(find.text('Medicine names, prescriptions and licence details are never translated.'), findsOneWidget);

    await tester.tap(find.text('తెలుగు · Telugu'));
    await tester.pump();
    await tester.tap(find.text('Save language'));
    await settle(tester);

    // J2: chrome still English, sample content in Telugu with plural rules applied.
    expect(find.text('Preview · తెలుగు'), findsOneWidget);
    expect(find.text('3 మార్పులు సింక్ కోసం వేచి ఉన్నాయి'), findsOneWidget);
    expect(find.textContaining('లేబుల్స్ ఆంగ్లంలో కనిపిస్తాయి.'), findsWidgets);

    await tester.tap(find.text('Save language'));
    await settle(tester);

    // J3, now in Telugu.
    expect(Translations.current.code, 'te');
    expect(find.text('భాష సేవ్ అయింది · తెలుగు'), findsOneWidget);
    expect(find.text('కొన్ని లేబుల్స్ ఇంకా అనువదించబడలేదు'), findsOneWidget);
    expect(find.text('ఈ పరికరంలో మరియు సర్వర్‌లో మీ ప్రొఫైల్‌కు సేవ్ అయింది.'), findsOneWidget);
    expect(api.saved, ['te']);
    expect(await repo.savedLanguage(), 'te');
  });

  testWidgets('offline: picker uses bundled catalogs; choice is kept and synced later', (tester) async {
    api.offline = true;
    await pump(tester);
    expect(find.text('Offline · Showing languages available on this device.'), findsOneWidget);
    expect(find.textContaining('Complete · Translation not reviewed yet'), findsOneWidget); // Hindi, computed locally

    await tester.tap(find.text('हिन्दी · Hindi'));
    await tester.pump();
    await tester.tap(find.text('Save language'));
    await settle(tester);
    await tester.tap(find.text('Save language'));
    await settle(tester);

    expect(find.text('भाषा सेव हुई · हिन्दी'), findsOneWidget);
    expect(find.text('इस डिवाइस पर सेव हुआ। कनेक्ट होने पर आपकी प्रोफ़ाइल में सेव होगा।'), findsOneWidget);
    expect(find.text('कुछ लेबल का अभी अनुवाद नहीं हुआ है'), findsNothing, reason: 'Hindi is complete');

    api.offline = false;
    await tester.runAsync(repo.flushPending);
    expect(api.saved, ['hi']);
  });

  test('a newer published catalog replaces the bundled one; 304 keeps it', () async {
    final bundled = await repo.bundled('te');
    expect(await repo.refresh('te'), isNull); // server says not modified

    api.newer = Catalog(
      code: 'te',
      version: '2099.1.1.1',
      messages: {...bundled.messages, 'ticket.form.submit': 'టికెట్ పంపండి'},
    );
    expect(await repo.refresh('te'), isNotNull);
    final t = await repo.load('te');
    expect(t.get('ticket.form.submit'), 'టికెట్ పంపండి');
    expect(jsonDecode((await db.outboxDao.readMeta('l10n:te'))!)['catalogVersion'], '2099.1.1.1');
  });
}
