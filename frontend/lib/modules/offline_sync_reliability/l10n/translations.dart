import 'package:flutter/foundation.dart';
import 'package:intl/message_format.dart';

/// A parsed catalog file (`assets/l10n/<code>.json` or `GET /translations/<code>`).
class Catalog {
  const Catalog({
    required this.code,
    required this.version,
    required this.messages,
    this.name,
    this.nativeName,
    this.reviewed = false,
  });

  factory Catalog.fromJson(Map<String, dynamic> j) {
    // Bundled files carry "@@" metadata; server responses carry it as fields.
    final messages = <String, String>{};
    final raw = (j['messages'] as Map<String, dynamic>?) ?? j;
    for (final e in raw.entries) {
      if (!e.key.startsWith('@@') && e.value is String) messages[e.key] = e.value as String;
    }
    return Catalog(
      code: (j['languageCode'] ?? j['@@locale']) as String,
      version: (j['catalogVersion'] ?? j['@@version']) as String,
      name: j['@@name'] as String?,
      nativeName: j['@@nativeName'] as String?,
      reviewed: (j['reviewed'] ?? j['@@reviewed']) == true,
      messages: messages,
    );
  }

  final String code;
  final String version;
  final String? name;
  final String? nativeName;
  final bool reviewed;
  final Map<String, String> messages;

  Map<String, dynamic> toJson() => {
    'languageCode': code,
    'catalogVersion': version,
    'reviewed': reviewed,
    'messages': messages,
  };
}

/// Compares catalog versions like `2026.10.21.1` numerically, part by part.
int compareVersions(String a, String b) {
  final pa = a.split(RegExp(r'\D+')).where((s) => s.isNotEmpty).map(int.parse).toList();
  final pb = b.split(RegExp(r'\D+')).where((s) => s.isNotEmpty).map(int.parse).toList();
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Runtime message lookup. English is the source of truth: any key the active
/// language lacks falls back to English and is recorded in [missing] (spec §8.3:
/// "Missing keys fall back to English and are measurable").
class Translations {
  Translations({required this.english, this.active});

  final Catalog english;

  /// Null when English itself is active.
  final Catalog? active;

  final Set<String> missing = {};

  static Translations current = Translations(
    english: const Catalog(code: 'en', version: '0', messages: {}),
  );

  String get code => active?.code ?? 'en';

  /// Share of English keys translated in the active language, 0..1.
  double get coverage {
    final a = active;
    if (a == null || english.messages.isEmpty) return 1;
    return english.messages.keys.where(a.messages.containsKey).length / english.messages.length;
  }

  int get missingCount => active == null ? 0 : english.messages.keys.where((k) => !active!.messages.containsKey(k)).length;

  /// Whether [key] exists in English (the source of truth).
  bool has(String key) => english.messages.containsKey(key);

  String get(String key, [Map<String, Object>? args]) {
    var pattern = active?.messages[key];
    var locale = code;
    if (pattern == null) {
      pattern = english.messages[key];
      locale = 'en';
      if (active != null && pattern != null && missing.add(key) && kDebugMode) {
        debugPrint('l10n: "$key" missing in $code, using English');
      }
    }
    if (pattern == null) {
      assert(english.messages.isEmpty, 'Unknown translation key "$key"');
      return key;
    }
    if (args == null || args.isEmpty || !pattern.contains('{')) return pattern;
    try {
      return MessageFormat(pattern, locale: locale).format(args);
    } catch (_) {
      // A malformed translation must never break the screen: use English.
      final en = english.messages[key];
      return en == null || en == pattern ? pattern : MessageFormat(en, locale: 'en').format(args);
    }
  }
}

/// Looks up an app-owned string in the active language.
String tr(String key, [Map<String, Object>? args]) => Translations.current.get(key, args);

/// Like [tr], but null for keys that are optional by design (e.g. per-error-code messages).
String? trOrNull(String key, [Map<String, Object>? args]) =>
    Translations.current.has(key) ? Translations.current.get(key, args) : null;
