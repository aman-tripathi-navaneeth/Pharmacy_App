import 'package:flutter/material.dart';

/// Semantic status colours used by sync surfaces. Text on each background meets
/// WCAG AA; status is always also conveyed by text, never colour alone.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.onlineBg,
    required this.onlineFg,
    required this.offlineBg,
    required this.offlineFg,
    required this.syncingBg,
    required this.syncingFg,
    required this.warningBg,
    required this.warningFg,
    required this.errorBg,
    required this.errorFg,
  });

  final Color onlineBg, onlineFg, offlineBg, offlineFg, syncingBg, syncingFg, warningBg, warningFg, errorBg, errorFg;

  static const light = StatusColors(
    onlineBg: Color(0xFFDDF3E2),
    onlineFg: Color(0xFF14532D),
    offlineBg: Color(0xFFE7E5E4),
    offlineFg: Color(0xFF292524),
    syncingBg: Color(0xFFDBEAFE),
    syncingFg: Color(0xFF1E3A8A),
    warningBg: Color(0xFFFDF0D2),
    warningFg: Color(0xFF713F12),
    errorBg: Color(0xFFFDE2E1),
    errorFg: Color(0xFF7F1D1D),
  );

  static const dark = StatusColors(
    onlineBg: Color(0xFF173A24),
    onlineFg: Color(0xFFBBF7D0),
    offlineBg: Color(0xFF3A3633),
    offlineFg: Color(0xFFE7E5E4),
    syncingBg: Color(0xFF1E2F55),
    syncingFg: Color(0xFFBFDBFE),
    warningBg: Color(0xFF4A3510),
    warningFg: Color(0xFFFDE68A),
    errorBg: Color(0xFF4C1D1D),
    errorFg: Color(0xFFFECACA),
  );

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(StatusColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension StatusColorsX on BuildContext {
  StatusColors get status => Theme.of(this).extension<StatusColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E), brightness: brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  const radius = BorderRadius.all(Radius.circular(10));
  return base.copyWith(
    extensions: [brightness == Brightness.light ? StatusColors.light : StatusColors.dark],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: scheme.outlineVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 48), shape: const RoundedRectangleBorder(borderRadius: radius)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: const RoundedRectangleBorder(borderRadius: radius)),
    ),
  );
}
