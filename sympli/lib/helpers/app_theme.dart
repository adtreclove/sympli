import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Light
  static const bg = Color(0xFFF2F4F1);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFE8ECE8);
  static const ink = Color(0xFF12181A);
  static const inkSoft = Color(0xFF5C6864);
  static const inkFaint = Color(0xFF8B9793);
  static const border = Color(0xFFDCE2DD);

  // Dark
  static const bgDark = Color(0xFF0D1312);
  static const surfaceDark = Color(0xFF151D1B);
  static const inkDark = Color(0xFFECF2EF);
  static const inkSoftDark = Color(0xFF93A39D);
  static const borderDark = Color(0xFF263130);

  // accents
  static const accent = Color(0xFF128577); // branding color
  static const accentSoft = Color(0xFFDCF3EF);
  static const coral = Color(0xFFE24F30); // strong intensity (errors)
  static const amber = Color(0xFFE8961F); // middle intensity (morning)
  static const violet = Color(0xFF6E5AE0); // evening

  static const morgen = amber;
  static const mittag = accent;
  static const abend = violet;
  static const nacht = Color(0xFF33448F);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _base(brightness: Brightness.light);
  static ThemeData dark() => _base(brightness: Brightness.dark);

  static ThemeData _base({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? AppColors.bgDark : AppColors.bg;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final ink = isDark ? AppColors.inkDark : AppColors.ink;
    final inkSoft = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;
    final border = isDark ? AppColors.borderDark : AppColors.border;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.coral,
      onSecondary: Colors.white,
      error: AppColors.coral,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
    );

    final displayFont = GoogleFonts.bricolageGrotesque;
    final bodyFont = GoogleFonts.hankenGrotesk;
    final monoFont = GoogleFonts.ibmPlexMono;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      fontFamily: bodyFont().fontFamily,
      textTheme: TextTheme(
        headlineSmall: displayFont(
          fontSize: 23,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleMedium: bodyFont(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyMedium: bodyFont(fontSize: 14, color: ink),
        bodySmall: bodyFont(fontSize: 12, color: inkSoft),
        labelSmall: bodyFont(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: inkSoft,
        ),
      ),
      extensions: [AppMonoFont(monoFont(fontFeatures: const []))],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceDark : const Color(0xFFF7F8F6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.coral),
        ),
        labelStyle: bodyFont(color: inkSoft, fontSize: 13.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: bodyFont(fontSize: 15, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: bodyFont(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Theme-Extension, for using `Theme.of(context).extension<AppMonoFont>()`
/// for times / numbers  (e.g in the day circle or in course).
class AppMonoFont extends ThemeExtension<AppMonoFont> {
  const AppMonoFont(this.style);
  final TextStyle style;

  @override
  AppMonoFont copyWith({TextStyle? style}) => AppMonoFont(style ?? this.style);

  @override
  AppMonoFont lerp(ThemeExtension<AppMonoFont>? other, double t) => this;
}
