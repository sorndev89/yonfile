import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// YonTheme — ໂທນສີສົ້ມທັນສະໄໝ (Modern Vibrant Orange) ຮອງຮັບ Dark/Light.
class YonTheme {
  YonTheme._();

  // Primary
  static const Color yonOrange = Color(0xFFFF6B00);
  static const Color yonOrangeLight = Color(0xFFFF9E00);
  static const Color yonOrangeDeep = Color(0xFFFF5500);

  // Surfaces
  static const Color slateDarkBg = Color(0xFF0F172A);
  static const Color slateDarkCard = Color(0xFF1E293B);
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color pureWhite = Color(0xFFFFFFFF);

  // Status
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color amberGold = Color(0xFFF59E0B);
  static const Color roseRed = Color(0xFFEF4444);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [yonOrangeLight, yonOrangeDeep],
  );

  static TextTheme _laoTextTheme(TextTheme base) {
    final lao = GoogleFonts.notoSansLaoLoopedTextTheme(base);
    // Keep Lao glyphs on the bundled font for WASM/Skwasm, where browser
    // system-font fallback is unavailable. Numeric styles still use Inter.
    return lao;
  }

  /// ຟອນຕົວເລກ/ຄວາມໄວ ໃຫ້ໃຊ້ tabular figures ບໍ່ໃຫ້ຕົວເລກສັ່ນ.
  static TextStyle numeric(TextStyle? base) =>
      GoogleFonts.inter(fontFeatures: const [FontFeature.tabularFigures()], textStyle: base);

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: slateDarkBg,
    colorScheme: const ColorScheme.dark(
      primary: yonOrange,
      secondary: yonOrangeLight,
      surface: slateDarkCard,
      error: roseRed,
      onPrimary: Colors.white,
      onSurface: Colors.white,
    ),
    textTheme: _laoTextTheme(ThemeData.dark().textTheme),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: yonOrange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.notoSansLaoLooped(fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: slateDarkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: _inputTheme(Brightness.dark),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBg,
    colorScheme: const ColorScheme.light(
      primary: yonOrange,
      secondary: yonOrangeLight,
      surface: pureWhite,
      error: roseRed,
      onPrimary: Colors.white,
      onSurface: slateDarkBg,
    ),
    textTheme: _laoTextTheme(ThemeData.light().textTheme),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: yonOrange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.notoSansLaoLooped(fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: pureWhite,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: _inputTheme(Brightness.light),
  );

  static InputDecorationTheme _inputTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF0B1220) : const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: yonOrange, width: 1.5),
      ),
      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
    );
  }
}
