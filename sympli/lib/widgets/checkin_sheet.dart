import 'package:flutter/material.dart';
import 'package:sympli/controllers/factors_controller.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/helpers/factor_text.dart';
import 'package:sympli/models/factor.dart';

/// Öffnet den Check-in für [slot]. Liefert `true`, wenn gespeichert wurde.
Future<bool> showCheckInSheet(
  BuildContext context, {
  required FactorSlot slot,
  required List<FactorType> types,
  required FactorLogs logs,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => CheckInSheet(slot: slot, types: types, logs: logs),
  );
  return saved ?? false;
}

class CheckInSheet extends StatefulWidget {
  const CheckInSheet({
    super.key,
    required this.slot,
    required this.types,
    required this.logs,
  });

  final FactorSlot slot;

  /// Nur die Faktoren dieses Slots (bereits gefiltert).
  final List<FactorType> types;
  final FactorLogs logs;

  @override
  State<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<CheckInSheet> {
  /// 0 = heute, 1 = gestern
  int _dayOffset = 0;
  final Map<String, double?> _values = {};
  bool _saving = false;
  String? _error;

  DateTime get _day => addDays(dayKey(DateTime.now()), -_dayOffset);

  bool get _isMorning => widget.slot == FactorSlot.morning;

  @override
  void initState() {
    super.initState();
    _loadValues();
  }

  /// Vorhandene Werte des Tages laden; sonst sinnvolle Startwerte.
  void _loadValues() {
    _values.clear();
    for (final f in widget.types) {
      final existing = widget.logs.value(f.id, _day);
      _values[f.id] =
          existing ??
          switch (f.kind) {
            // Zahl: letzter bekannter Wert, sonst Standardwert
            FactorKind.number =>
              widget.logs.lastBefore(f.id, _day) ?? f.defaultValue ?? f.min,
            // Ja/Nein: "nein", bis man etwas anderes wählt
            FactorKind.boolean => 0.0,
            // Skala: bewusst leer – kein vorausgefüllter Wert, der verzerrt
            FactorKind.scale => null,
          };
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await saveFactorValues(_day, Map.of(_values));
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'Speichern hat nicht geklappt. Versuch es erneut.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final inkSoft = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;

    final valueTypes = widget.types
        .where((f) => f.kind != FactorKind.boolean)
        .toList();
    final boolTypes = widget.types
        .where((f) => f.kind == FactorKind.boolean)
        .toList();

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isMorning ? 'Wie war die Nacht?' : 'Wie war dein Tag?',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontSize: 19,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                        color: inkSoft,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final (i, label) in (_isMorning
                              ? const ['Letzte Nacht', 'Nacht davor']
                              : const ['Heute', 'Gestern'])
                          .indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        _Pill(
                          label: label,
                          selected: _dayOffset == i,
                          onTap: () => setState(() {
                            _dayOffset = i;
                            _loadValues();
                          }),
                        ),
                      ],
                    ],
                  ),
                  for (final f in valueTypes) ...[
                    const SizedBox(height: 22),
                    Text(
                      factorPrompt(f).toUpperCase(),
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: 10),
                    if (f.kind == FactorKind.number)
                      _NumberStepper(
                        factor: f,
                        value: _values[f.id] ?? f.min,
                        onChanged: (v) => setState(() => _values[f.id] = v),
                      )
                    else
                      _ScalePicker(
                        factor: f,
                        value: _values[f.id],
                        onChanged: (v) => setState(() => _values[f.id] = v),
                      ),
                  ],
                  if (boolTypes.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    for (final f in boolTypes)
                      _BoolRow(
                        factor: f,
                        value: (_values[f.id] ?? 0.0) >= 0.5,
                        onChanged: (v) =>
                            setState(() => _values[f.id] = v ? 1.0 : 0.0),
                      ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.coral,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Speichern'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.border;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          border: Border.all(color: selected ? AppColors.accent : border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Zahl mit Plus/Minus, z.B. Schlafdauer in 0,5-Std.-Schritten.
class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.factor,
    required this.value,
    required this.onChanged,
  });

  final FactorType factor;
  final double value;
  final ValueChanged<double> onChanged;

  void _change(int direction) {
    final next = (value + direction * factor.step).clamp(factor.min, factor.max);
    // Rundungsfehler bei 0,5-Schritten vermeiden
    onChanged(double.parse(next.toStringAsFixed(2)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final mono = theme.extension<AppMonoFont>()?.style ?? const TextStyle();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: fmtNum(value),
                    style: mono.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (factor.unit != null)
                    TextSpan(
                      text: '  ${factor.unit}',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                    ),
                ],
              ),
            ),
          ),
          _RoundButton(
            icon: Icons.remove_rounded,
            filled: false,
            onTap: value <= factor.min ? null : () => _change(-1),
          ),
          const SizedBox(width: 8),
          _RoundButton(
            icon: Icons.add_rounded,
            filled: true,
            onTap: value >= factor.max ? null : () => _change(1),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.filled, this.onTap});

  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: filled ? AppColors.accent : Colors.transparent,
            border: filled ? null : Border.all(color: border),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(
            icon,
            size: 18,
            color: filled
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Skala 1–5 als Knöpfe. Nochmal tippen hebt die Auswahl auf.
class _ScalePicker extends StatelessWidget {
  const _ScalePicker({
    required this.factor,
    required this.value,
    required this.onChanged,
  });

  final FactorType factor;
  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final inkSoft = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;
    final labels = scaleEndLabels(factor);
    final steps = [
      for (var v = factor.min; v <= factor.max + 0.001; v += factor.step) v,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () =>
                      onChanged(value == steps[i] ? null : steps[i]),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == steps[i]
                          ? AppColors.accent
                          : Colors.transparent,
                      border: Border.all(
                        color: value == steps[i] ? AppColors.accent : border,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      fmtNum(steps[i]),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: value == steps[i]
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(labels.low, style: TextStyle(fontSize: 10.5, color: inkSoft)),
            Text(labels.high, style: TextStyle(fontSize: 10.5, color: inkSoft)),
          ],
        ),
      ],
    );
  }
}

/// Ja/Nein-Zeile, z.B. "Fast Food gegessen?  [Nein | Ja]".
class _BoolRow extends StatelessWidget {
  const _BoolRow({
    required this.factor,
    required this.value,
    required this.onChanged,
  });

  final FactorType factor;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.borderDark : AppColors.surface2;
    final inkSoft = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;

    Widget option(String label, bool optionValue) {
      final selected = value == optionValue;
      return GestureDetector(
        onTap: () => onChanged(optionValue),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? (optionValue ? AppColors.accent : (isDark ? AppColors.surfaceDark : AppColors.surface))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected
                  ? (optionValue ? Colors.white : theme.colorScheme.onSurface)
                  : inkSoft,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(factorIcon(factor), size: 19, color: inkSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              factorPrompt(factor),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [option('Nein', false), option('Ja', true)],
            ),
          ),
        ],
      ),
    );
  }
}
