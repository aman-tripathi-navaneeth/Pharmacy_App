import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/local/outbox_dao.dart';
import '../data/remote/api_client.dart';
import '../data/remote/languages_api.dart';
import 'translations.dart';

/// Launch languages bundled with the app (spec §8.3: English, Hindi, Telugu, Tamil).
const bundledLanguages = ['en', 'hi', 'te', 'ta'];

/// Where catalogs and the user's language preference come from:
///  * bundled assets — always available, offline-safe;
///  * a cached server catalog — newer translations without an app release;
///  * the server — `GET /translations/:code` (ETag) and `/users/me/language`.
class LanguageRepository {
  LanguageRepository({required this.dao, required this.api, AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final OutboxDao dao;
  final LanguagesApi api;
  final AssetBundle _bundle;

  static const _prefKey = 'language';
  static const _pendingKey = 'language_pending_sync';
  static String _cacheKey(String code) => 'l10n:$code';

  Future<Catalog> bundled(String code) async =>
      Catalog.fromJson(jsonDecode(await _bundle.loadString('assets/l10n/$code.json')) as Map<String, dynamic>);

  Future<Catalog?> cached(String code) async {
    final raw = await dao.readMeta(_cacheKey(code));
    if (raw == null || raw.isEmpty) return null;
    return Catalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// The newest catalog available on the device.
  Future<Catalog?> best(String code) async {
    final b = bundledLanguages.contains(code) ? await bundled(code) : null;
    final c = await cached(code);
    if (b == null) return c;
    if (c == null) return b;
    return compareVersions(c.version, b.version) > 0 ? c : b;
  }

  Future<Translations> load(String code) async {
    final english = (await best('en'))!;
    if (code == 'en') return Translations(english: english);
    final active = await best(code);
    return Translations(english: english, active: active);
  }

  /// Fetches a newer published catalog. Returns it if it changed, else null.
  Future<Catalog?> refresh(String code) async {
    final known = await best(code);
    final fresh = await api.catalog(code, knownVersion: known?.version);
    if (fresh == null || (known != null && compareVersions(fresh.version, known.version) <= 0)) return null;
    await dao.writeMeta(_cacheKey(code), jsonEncode(fresh.toJson()));
    return fresh;
  }

  /// Picker list from the server; offline, the bundled catalogs with locally computed coverage.
  Future<({List<LanguageInfo> languages, bool offline})> languages() async {
    try {
      return (languages: await api.languages(), offline: false);
    } on ApiException {
      final english = (await best('en'))!;
      final list = <LanguageInfo>[];
      for (final code in bundledLanguages) {
        final c = (await best(code))!;
        final translated = english.messages.keys.where(c.messages.containsKey).length;
        list.add(LanguageInfo(
          code: code,
          name: c.name ?? code,
          nativeName: c.nativeName ?? c.name ?? code,
          isDefault: code == 'en',
          catalogVersion: c.version,
          reviewed: c.reviewed,
          coverage: english.messages.isEmpty ? 1 : translated / english.messages.length,
          missingCount: english.messages.length - translated,
        ));
      }
      return (languages: list, offline: true);
    }
  }

  Future<String?> savedLanguage() => dao.readMeta(_prefKey);

  /// Saves on the device first, then on the user's profile. Returns whether the
  /// server copy is up to date; if not, [flushPending] retries later.
  Future<bool> save(String code) async {
    await dao.writeMeta(_prefKey, code);
    try {
      await api.setMyLanguage(code);
      await dao.writeMeta(_pendingKey, '');
      return true;
    } on ApiException {
      await dao.writeMeta(_pendingKey, code);
      return false;
    }
  }

  Future<void> flushPending() async {
    final pending = await dao.readMeta(_pendingKey);
    if (pending == null || pending.isEmpty) return;
    try {
      await api.setMyLanguage(pending);
      await dao.writeMeta(_pendingKey, '');
    } on ApiException {
      // Still offline; try again next time.
    }
  }

  /// On a new device, restore the language saved on the user's profile.
  Future<String?> profileLanguage() async {
    try {
      return await api.myLanguage();
    } on ApiException {
      return null;
    }
  }
}
