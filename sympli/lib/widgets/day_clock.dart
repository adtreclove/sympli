import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/helpers/day_phase.dart';
import 'package:sympli/models/symptom_entry.dart';

/// 24-hour clock face: 00 at the top, 06 on the right, 12 at the bottom, 18 on the left.
/// Each entry is a point on the ring (color = time of day,
/// size = intensity), and the dotted line indicates the current time.
class DayClock extends StatelessWidget {
  const DayClock({
    super.key,
    required this.entries,
    required this.now,
    this.size = 220,
  });

  final List<SymptomEntry> entries;
  final DateTime now;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mono = theme.extension<AppMonoFont>()?.style ?? const TextStyle();
    final ink = isDark ? AppColors.inkDark : AppColors.ink;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DayClockPainter(
                entries: entries,
                now: now,
                isDark: isDark,
                labelStyle: mono.copyWith(fontSize: 9.5, color: faint),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateLabels.time(now),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: ink,
                  height: 1.1,
                ),
              ),
              Text(
                'JETZT',
                style: mono.copyWith(
                  fontSize: 8,
                  letterSpacing: 0.8,
                  color: faint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayClockPainter extends CustomPainter {
  _DayClockPainter({
    required this.entries,
    required this.now,
    required this.isDark,
    required this.labelStyle,
  });

  final List<SymptomEntry> entries;
  final DateTime now;
  final bool isDark;
  final TextStyle labelStyle;

  /// angle for a time: 00 Uhr oben, clockwise
  static double _angleFor(DateTime t) {
    final hours = t.hour + t.minute / 60 + t.second / 3600;
    return -math.pi / 2 + hours / 24 * 2 * math.pi;
  }

  static Offset _point(Offset c, double r, double angle) =>
      c + Offset(math.cos(angle) * r, math.sin(angle) * r);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 30;

    final ringColor = isDark ? AppColors.borderDark : const Color(0xFFE2E6E3);
    final tickColor = isDark
        ? const Color(0xFF3A4745)
        : const Color(0xFFC9D0CC);
    final ink = isDark ? AppColors.inkDark : AppColors.ink;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;

    // Ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = ringColor,
    );

    // lines: long at 00/06/12/18, short at 03/09/15/21
    final tickPaint = Paint()
      ..color = tickColor
      ..strokeCap = StrokeCap.round;
    for (var h = 0; h < 24; h += 3) {
      final major = h % 6 == 0;
      final a = -math.pi / 2 + h / 24 * 2 * math.pi;
      tickPaint.strokeWidth = major ? 1.8 : 1.4;
      canvas.drawLine(
        _point(center, radius, a),
        _point(center, radius - (major ? 11 : 8), a),
        tickPaint,
      );
    }

    // text outside
    for (final h in const [0, 6, 12, 18]) {
      final a = -math.pi / 2 + h / 24 * 2 * math.pi;
      final tp = TextPainter(
        text: TextSpan(text: h.toString().padLeft(2, '0'), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = _point(center, radius + 20, a);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    // Now pointer (dotted line)
    final nowAngle = _angleFor(now);
    final nowPoint = _point(center, radius, nowAngle);
    final dotPaint = Paint()..color = ink.withValues(alpha: 0.7);
    const step = 4.0;
    for (double d = 4; d < radius - 3; d += step) {
      canvas.drawCircle(_point(center, d, nowAngle), 0.8, dotPaint);
    }
    canvas.drawCircle(nowPoint, 3, Paint()..color = ink);

    // Entries
    for (final e in entries) {
      final p = _point(center, radius, _angleFor(e.occurredAt));
      final r = 3.8 + e.intensity.clamp(1, 5) * 0.55;
      canvas.drawCircle(p, r + 2, Paint()..color = surface);
      canvas.drawCircle(
        p,
        r,
        Paint()..color = DayPhase.fromTime(e.occurredAt).color(isDark),
      );
    }
  }

  @override
  bool shouldRepaint(_DayClockPainter old) =>
      old.entries != entries ||
      old.now.minute != now.minute ||
      old.now.hour != now.hour ||
      old.isDark != isDark;
}
