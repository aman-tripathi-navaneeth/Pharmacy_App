import '../../l10n/translations.dart';
import 'api_client.dart';

class LanguageInfo {
  const LanguageInfo({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.isDefault,
    required this.catalogVersion,
    required this.reviewed,
    required this.coverage,
    required this.missingCount,
  });

  factory LanguageInfo.fromJson(Map<String, dynamic> j) => LanguageInfo(
    code: j['code'] as String,
    name: j['name'] as String,
    nativeName: j['nativeName'] as String,
    isDefault: j['isDefault'] as bool? ?? false,
    catalogVersion: j['catalogVersion'] as String,
    reviewed: j['reviewed'] as bool? ?? false,
    coverage: (j['coverage'] as num).toDouble(),
    missingCount: j['missingCount'] as int? ?? 0,
  );

  final String code;
  final String name;
  final String nativeName;
  final bool isDefault;
  final String catalogVersion;
  final bool reviewed;
  final double coverage;
  final int missingCount;

  bool get complete => coverage >= 0.9995;
}

abstract interface class LanguagesApi {
  Future<List<LanguageInfo>> languages();

  /// Returns null when [knownVersion] is still current (HTTP 304).
  Future<Catalog?> catalog(String code, {String? knownVersion});
  Future<String?> myLanguage();
  Future<void> setMyLanguage(String code);
}

class HttpLanguagesApi implements LanguagesApi {
  HttpLanguagesApi(this._client);

  final ApiClient _client;

  @override
  Future<List<LanguageInfo>> languages() async {
    final body = await _client.get('/languages');
    return [for (final l in body['languages'] as List) LanguageInfo.fromJson(l as Map<String, dynamic>)];
  }

  @override
  Future<Catalog?> catalog(String code, {String? knownVersion}) async {
    final body = await _client.getOrNotModified(
      '/translations/$code',
      etag: knownVersion == null ? null : '"$code@$knownVersion"',
    );
    return body == null ? null : Catalog.fromJson(body);
  }

  @override
  Future<String?> myLanguage() async => (await _client.get('/users/me/language'))['languageCode'] as String?;

  @override
  Future<void> setMyLanguage(String code) => _client.patch('/users/me/language', data: {'languageCode': code});
}
