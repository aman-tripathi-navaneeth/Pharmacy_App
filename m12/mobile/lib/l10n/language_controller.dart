import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'language_repository.dart';
import 'translations.dart';

/// Overridden in `main()` (and tests).
final languageRepositoryProvider = Provider<LanguageRepository>((ref) => throw UnimplementedError());

/// Translations loaded before `runApp`, so the first frame is already in the user's language.
final initialTranslationsProvider = Provider<Translations>((ref) => Translations.current);

final languageProvider = NotifierProvider<LanguageController, Translations>(LanguageController.new);

/// Makes [t] the active language: messages, plural rules, dates and numbers.
Future<void> activate(Translations t) async {
  await initializeDateFormatting(t.code);
  Intl.defaultLocale = t.code;
  Translations.current = t;
}

/// Resolves the starting language: this device's choice, else the user's profile
/// (restored on a new device), else English.
Future<Translations> bootstrapLanguage(LanguageRepository repo) async {
  var code = await repo.savedLanguage();
  if (code == null || !bundledLanguages.contains(code)) code = 'en';
  final t = await repo.load(code);
  await activate(t);
  return t;
}

class LanguageController extends Notifier<Translations> {
  @override
  Translations build() => ref.watch(initialTranslationsProvider);

  LanguageRepository get _repo => ref.read(languageRepositoryProvider);

  /// Applies [code] app-wide and saves it. Returns whether the profile copy was saved too.
  Future<bool> change(String code) async {
    final t = await _repo.load(code);
    await activate(t);
    state = t;
    return _repo.save(code);
  }

  /// Background work after launch: push a pending choice, restore the profile
  /// language on a new device, and pick up newer published catalogs.
  Future<void> syncInBackground() async {
    await _repo.flushPending();
    if (await _repo.savedLanguage() == null) {
      final remote = await _repo.profileLanguage();
      if (remote != null && remote != state.code && bundledLanguages.contains(remote)) {
        final t = await _repo.load(remote);
        await activate(t);
        state = t;
        await _repo.save(remote);
        return;
      }
    }
    var changed = false;
    for (final code in {'en', state.code}) {
      try {
        changed |= await _repo.refresh(code) != null;
      } catch (_) {
        // Offline or server error: keep the catalogs we have.
      }
    }
    if (changed) {
      final t = await _repo.load(state.code);
      await activate(t);
      state = t;
    }
  }
}

/// Re-runs every build method so all `tr(...)` lookups pick up a new language,
/// without resetting navigation or screen state.
void rebuildAllChildren(BuildContext context) {
  void rebuild(Element el) {
    el.markNeedsBuild();
    el.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}
