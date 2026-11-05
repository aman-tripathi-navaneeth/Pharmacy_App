import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/l10n/translations.dart';

Catalog loadCatalog(String code) =>
    Catalog.fromJson(jsonDecode(File('assets/l10n/$code.json').readAsStringSync()) as Map<String, dynamic>);

/// Widget tests render real English copy from the bundled catalog.
void useEnglish() => Translations.current = Translations(english: loadCatalog('en'));

/// Serves app assets straight from disk. A fresh instance per test avoids
/// rootBundle's cross-test future cache.
class DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(await File(key).readAsBytes());
}
