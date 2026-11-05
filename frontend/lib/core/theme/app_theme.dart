import 'package:flutter/material.dart';

class AppTheme {
  // Primary Palette - Figma Sage Green (#849A76)
  static const Color primaryTeal = Color(0xFF849A76);
  static const Color primaryTealLight = Color(0xFF9AB08C);
  static const Color primaryTealDark = Color(0xFF6A805E);
  static const Color tealSurface = Color(0xFFEAEFE7);
  static const Color tealTint = Color(0xFFF2F6F0);

  // Accent & Semantic Badges - Exact User Tokens
  // In Stock / Inward: Sage Green (#849A76)
  static const Color emeraldGreen = Color(0xFF849A76);
  static const Color emeraldLight = Color(0xFFEAEFE7);
  // Expiring Soon: Warm Amber (#D9A441)
  static const Color amberWarning = Color(0xFFD9A441);
  static const Color amberLight = Color(0xFFFAF2E4);
  // Expired / Insufficient: Muted Terracotta Red (#C85C54)
  static const Color roseDanger = Color(0xFFC85C54);
  static const Color roseLight = Color(0xFFF9EAE8);
  // Auxiliary Information
  static const Color blueInfo = Color(0xFF637C8E);
  static const Color blueLight = Color(0xFFEBF1F5);

  // Neutral Colors - Dark Brown (#493A2B), Muted Taupe (#857667), Cream (#F5F1E9), Soft Cream (#F8F5EE)
  static const Color slateDark = Color(0xFF493A2B); // Dark Brown primary text
  static const Color slateHeading = Color(0xFF493A2B); // Dark Brown headings
  static const Color slateBody = Color(0xFF6B5C4D); // Warm body text
  static const Color slateMuted = Color(0xFF857667); // Muted Taupe secondary text
  static const Color slateBorder = Color(0xFFE8E3D8); // Subtle warm border
  static const Color backgroundLight = Color(0xFFF5F1E9); // Warm Off-White / Cream Canvas
  static const Color surfaceCard = Color(0xFFF8F5EE); // Soft Cream Card Surface

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTeal,
        primary: primaryTeal,
        secondary: primaryTealLight,
        surface: surfaceCard,
        error: roseDanger,
      ),
      scaffoldBackgroundColor: backgroundLight,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundLight,
        foregroundColor: slateDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: slateDark,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: slateDark),
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: slateBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryTeal,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slateBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slateBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryTeal, width: 1.5),
        ),
        labelStyle: const TextStyle(color: slateMuted, fontSize: 13),
      ),
    );
  }
}
