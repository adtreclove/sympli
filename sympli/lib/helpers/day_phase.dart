import 'package:flutter/material.dart';
import 'package:sympli/helpers/app_theme.dart';

enum DayPhase {
  morgen('Morgen'),
  mittag('Mittag'),
  abend('Abend'),
  nacht('Nacht');

  const DayPhase(this.label);
  final String label;

  /// morning 05–11, day 11–17, evening 17–22, night 22–05 Uhr.
  static DayPhase fromTime(DateTime time) {
    final h = time.hour;
    if (h >= 5 && h < 11) return DayPhase.morgen;
    if (h >= 11 && h < 17) return DayPhase.mittag;
    if (h >= 17 && h < 22) return DayPhase.abend;
    return DayPhase.nacht;
  }

  Color color(bool isDark) => switch (this) {
    DayPhase.morgen => isDark ? AppColors.morgenDark : AppColors.morgen,
    DayPhase.mittag => isDark ? AppColors.mittagDark : AppColors.mittag,
    DayPhase.abend => isDark ? AppColors.abendDark : AppColors.abend,
    DayPhase.nacht => isDark ? AppColors.nachtDark : AppColors.nacht,
  };
}

/// intensity 1–5 → Label + Badge colors
class IntensityStyle {
  const IntensityStyle(this.label, this.foreground, this.background);

  final String label;
  final Color foreground;
  final Color background;

  static IntensityStyle of(int intensity, {required bool isDark}) {
    if (intensity <= 2) {
      return isDark
          ? IntensityStyle(
              'leicht',
              AppColors.mittagDark,
              AppColors.mittagDark.withValues(alpha: 0.14),
            )
          : const IntensityStyle(
              'leicht',
              AppColors.accent,
              AppColors.accentSoft,
            );
    }
    if (intensity <= 4) {
      return isDark
          ? IntensityStyle(
              'mittel',
              AppColors.morgenDark,
              AppColors.morgenDark.withValues(alpha: 0.16),
            )
          : const IntensityStyle(
              'mittel',
              Color(0xFFB86E0B),
              Color(0xFFFCEBD3),
            );
    }
    return isDark
        ? IntensityStyle(
            'stark',
            const Color(0xFFF27A60),
            const Color(0xFFF27A60).withValues(alpha: 0.16),
          )
        : const IntensityStyle('stark', AppColors.coral, Color(0xFFFBE1DA));
  }
}

class DateLabels {
  DateLabels._();

  static const _weekdays = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];
  static const _months = [
    'Jan.',
    'Feb.',
    'März',
    'Apr.',
    'Mai',
    'Juni',
    'Juli',
    'Aug.',
    'Sept.',
    'Okt.',
    'Nov.',
    'Dez.',
  ];

  /// e.g "MONTAG, 21. SEPT."
  static String dayHeader(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${d.day}. ${_months[d.month - 1]}'
          .toUpperCase();

  /// e.g. "07:15"
  static String time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String greeting(DateTime d) {
    final h = d.hour;
    if (h >= 5 && h < 11) return 'Guten Morgen';
    if (h >= 11 && h < 18) return 'Guten Tag';
    if (h >= 18 && h < 23) return 'Guten Abend';
    return 'Gute Nacht';
  }
}
