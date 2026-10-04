import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:sympli/controllers/factors_controller.dart';
import 'package:sympli/controllers/user_settings_controller.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/helpers/factor_text.dart';
import 'package:sympli/models/factor.dart';
import 'package:sympli/widgets/checkin_sheet.dart';

/// Daily Check in. Asks about food, stress level, period (if enabled), movement
class CheckInCard extends ConsumerWidget {
  const CheckInCard({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final typesAsync = ref.watch(factorTypesProvider);
    final logsAsync = ref.watch(factorLogsProvider);
    final settings = ref.watch(userSettingsProvider).value;

    Widget body;

    // switch body depending on provider states
    if (typesAsync.hasError || logsAsync.hasError) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Check-in konnte nicht geladen werden.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.coral),
        ),
      );
    } else if (!typesAsync.hasValue || !logsAsync.hasValue) {
      body = const _RowsSkeleton();
    } else {
      final trackCycle = settings?.trackCycle ?? false;
      final types = typesAsync.value!
          .where((f) => !f.requiresCycle || trackCycle)
          .toList();
      final logs = logsAsync.value!;
      final morning = types.where((f) => f.slot == FactorSlot.morning).toList();
      final evening = types.where((f) => f.slot == FactorSlot.evening).toList();

      Future<void> open(FactorSlot slot, List<FactorType> slotTypes) async {
        final saved = await showCheckInSheet(
          context,
          slot: slot,
          types: slotTypes,
          logs: logs,
        );
        if (saved) ref.invalidate(factorLogsProvider);
      }

      body = Column(
        children: [
          if (morning.isNotEmpty)
            _SlotRow(
              icon: Icons.bedtime_outlined,
              title: 'Wie war die Nacht?',
              types: morning,
              logs: logs,
              day: now,
              hint: 'Dauert 5 Sekunden',
              onTap: () => open(FactorSlot.morning, morning),
            ),
          if (morning.isNotEmpty && evening.isNotEmpty)
            Divider(
              height: 1,
              color: isDark ? AppColors.borderDark : AppColors.border,
            ),
          if (evening.isNotEmpty)
            _SlotRow(
              icon: Icons.wb_twilight_rounded,
              title: 'Wie war dein Tag?',
              types: evening,
              logs: logs,
              day: now,
              hint: now.hour < 17 ? 'Am besten am Abend' : 'Jetzt ausfüllen',
              onTap: () => open(FactorSlot.evening, evening),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Check-in', style: theme.textTheme.titleMedium),
                ),
                Text(
                  'Heute',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.inkSoftDark : AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          body,
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.icon,
    required this.title,
    required this.types,
    required this.logs,
    required this.day,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final List<FactorType> types;
  final FactorLogs logs;
  final DateTime day;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final accent = isDark ? AppColors.mittagDark : AppColors.accent;

    // summary of checked in values
    final parts = <String>[];
    for (final factor in types) {
      final value = logs.value(factor.id, day);
      if (value == null) continue;
      // add name of factor if it's a bool (fast food, alcohol etc)
      if (factor.kind == FactorKind.boolean) {
        if (value >= 0.5) parts.add(factor.name);
      } else {
        parts.add(formatFactorValue(factor, value));
      }
    }
    final done = types.any((factor) => logs.value(factor.id, day) != null);
    final summary = done
        ? (parts.isEmpty ? 'Erfasst' : parts.join(' · '))
        : hint;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: done
                    ? accent.withValues(alpha: isDark ? 0.16 : 0.12)
                    : (isDark ? AppColors.borderDark : AppColors.surface2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: done ? accent : faint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (done)
              Icon(Icons.check_circle_rounded, size: 20, color: accent)
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Eintragen',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.bgDark : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // reusable bar for shimmer effect
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF1E2826) : AppColors.surface2,
      highlightColor: isDark
          ? const Color(0xFF2C3836)
          : const Color(0xFFF7F9F7),
      child: Column(
        children: [
          // currently we have two rows (night and day), therefore we show two skeletons
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(130, 12),
                      const SizedBox(height: 6),
                      bar(90, 10),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
