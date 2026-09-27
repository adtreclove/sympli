import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/helpers/app_theme.dart';

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _Symptom {
  const _Symptom(this.id, this.name);
  final String id;
  final String name;
}

class _EntryScreenState extends State<EntryScreen> {
  final _noteController = TextEditingController();
  final _customController = TextEditingController();
  final _customFocus = FocusNode();
  final _supabase = Supabase.instance.client;

  DateTime _occurredAt = DateTime.now();
  String? _selectedSymptomId;
  int _intensity = 3;
  bool _isSaving = false;
  String? _error;

  List<_Symptom> _symptoms = [];
  bool _loadingSymptoms = true;

  bool _addingCustom = false;
  bool _savingCustom = false;

  static const _intensityLabels = [
    'leicht',
    'leicht',
    'mittel',
    'mittel',
    'stark',
  ];
  static const _intensityColors = [
    AppColors.accent,
    AppColors.accent,
    AppColors.amber,
    AppColors.amber,
    AppColors.coral,
  ];

  @override
  void initState() {
    super.initState();
    _loadSymptoms();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _customController.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSymptoms() async {
    try {
      final rows = await _supabase
          .from('symptoms')
          .select('id, name')
          .order('is_default', ascending: false)
          .order('name');

      setState(() {
        _symptoms = rows
            .map<_Symptom>(
              (row) => _Symptom(row['id'] as String, row['name'] as String),
            )
            .toList();
        _loadingSymptoms = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Symptome konnten nicht geladen werden.';
        _loadingSymptoms = false;
      });
    }
  }

  void _startAddingCustom() {
    setState(() {
      _addingCustom = true;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _customFocus.requestFocus(),
    );
  }

  void _cancelAddingCustom() {
    _customController.clear();
    setState(() => _addingCustom = false);
  }

  Future<void> _addCustomSymptom() async {
    final name = _customController.text.trim();
    if (name.isEmpty || _savingCustom) return;

    // Gibt es das Symptom schon (egal ob Standard oder eigenes)? → auswählen.
    final existing = _symptoms.where(
      (s) => s.name.toLowerCase() == name.toLowerCase(),
    );
    if (existing.isNotEmpty) {
      _customController.clear();
      setState(() {
        _selectedSymptomId = existing.first.id;
        _addingCustom = false;
      });
      return;
    }

    setState(() {
      _savingCustom = true;
      _error = null;
    });

    try {
      final row = await _supabase
          .from('symptoms')
          .insert({
            'name': name,
            'is_default': false,
            'user_id': _supabase.auth.currentUser!.id,
          })
          .select('id, name')
          .single();

      final symptom = _Symptom(row['id'] as String, row['name'] as String);
      _customController.clear();
      setState(() {
        _symptoms = [..._symptoms, symptom];
        _selectedSymptomId = symptom.id;
        _addingCustom = false;
        _savingCustom = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Symptom konnte nicht angelegt werden.';
        _savingCustom = false;
      });
    }
  }

  /// Genaue Uhrzeit wählen. Startet direkt im Eingabemodus (Tippen),
  /// über das Uhr-Icon im Dialog kann man auf das Ziffernblatt wechseln.
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
      initialEntryMode: TimePickerEntryMode.input,
      helpText: 'Uhrzeit eingeben',
      cancelText: 'Abbrechen',
      confirmText: 'Übernehmen',
      hourLabelText: 'Stunde',
      minuteLabelText: 'Minute',
      errorInvalidText: 'Bitte eine gültige Uhrzeit eingeben',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _occurredAt = DateTime(
        _occurredAt.year,
        _occurredAt.month,
        _occurredAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _adjustMinutes(int delta) {
    setState(() => _occurredAt = _occurredAt.add(Duration(minutes: delta)));
  }

  void _setQuickTime(int hour) {
    final now = DateTime.now();
    setState(() {
      _occurredAt = DateTime(now.year, now.month, now.day, hour, 0);
    });
  }

  Future<void> _save() async {
    if (_selectedSymptomId == null) {
      setState(() => _error = 'Bitte wähle ein Symptom aus.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await _supabase.from('entries').insert({
        'user_id': _supabase.auth.currentUser!.id,
        'symptom_id': _selectedSymptomId,
        // mit Zeitzone speichern, sonst landet 19:47 Ortszeit als 19:47 UTC
        'occurred_at': _occurredAt.toUtc().toIso8601String(),
        'intensity': _intensity,
        'note': _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      });

      if (mounted) context.pop();
    } catch (_) {
      setState(() {
        _error = 'Eintrag konnte nicht gespeichert werden. Versuch es erneut.';
        _isSaving = false;
      });
    }
  }

  String get _timeLabel {
    final h = _occurredAt.hour.toString().padLeft(2, '0');
    final m = _occurredAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final inkSoft = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.55),
      body: GestureDetector(
        onTap: () => context.pop(),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              // Fängt Taps im Sheet ab, damit sie nicht zum "Schließen"-Tap
              // im Hintergrund durchgereicht werden.
              onTap: () {},
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.92,
                ),
                padding: EdgeInsets.fromLTRB(
                  22,
                  12,
                  22,
                  22 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                ),
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
                              'Neuer Eintrag',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontSize: 19,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: inkSoft,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      _TimeCard(
                        label: _timeLabel,
                        onTapTime: _pickTime,
                        onMinus: () => _adjustMinutes(-5),
                        onPlus: () => _adjustMinutes(5),
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          _QuickTimeChip(
                            label: 'Jetzt',
                            onTap: () =>
                                setState(() => _occurredAt = DateTime.now()),
                          ),
                          const SizedBox(width: 8),
                          _QuickTimeChip(
                            label: 'Morgens',
                            onTap: () => _setQuickTime(8),
                          ),
                          const SizedBox(width: 8),
                          _QuickTimeChip(
                            label: 'Abends',
                            onTap: () => _setQuickTime(19),
                          ),
                          const SizedBox(width: 8),
                          _QuickTimeChip(
                            label: 'Nachts',
                            onTap: () => _setQuickTime(23),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      Text('SYMPTOM', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 10),

                      if (_loadingSymptoms)
                        const _SymptomSkeleton()
                      else ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final symptom in _symptoms)
                              _SymptomChip(
                                label: symptom.name,
                                selected: _selectedSymptomId == symptom.id,
                                onTap: () => setState(
                                  () => _selectedSymptomId = symptom.id,
                                ),
                              ),
                            if (!_addingCustom)
                              _AddSymptomChip(onTap: _startAddingCustom),
                          ],
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _addingCustom
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: _CustomSymptomField(
                                    controller: _customController,
                                    focusNode: _customFocus,
                                    saving: _savingCustom,
                                    onSubmit: _addCustomSymptom,
                                    onCancel: _cancelAddingCustom,
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                      const SizedBox(height: 22),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('INTENSITÄT', style: theme.textTheme.labelSmall),
                          Text(
                            _intensityLabels[_intensity - 1],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _intensityColors[_intensity - 1],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (var i = 1; i <= 5; i++)
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _intensity = i),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  height: 8,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: i <= _intensity
                                        ? _intensityColors[_intensity - 1]
                                        : border,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'leicht',
                            style: TextStyle(fontSize: 10.5, color: inkSoft),
                          ),
                          Text(
                            'stark',
                            style: TextStyle(fontSize: 10.5, color: inkSoft),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      Text(
                        'NOTIZ (OPTIONAL)',
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _noteController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Weitere Details …',
                        ),
                      ),

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

                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Eintrag speichern'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.label,
    required this.onTapTime,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final VoidCallback onTapTime;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final mono = theme.extension<AppMonoFont>()?.style;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: 'Genaue Uhrzeit eingeben',
                child: InkWell(
                  onTap: onTapTime,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('UHRZEIT', style: theme.textTheme.labelSmall),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              label,
                              style: (mono ?? const TextStyle()).copyWith(
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: theme.textTheme.labelSmall?.color,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                filled: false,
                onTap: onMinus,
              ),
              const SizedBox(width: 8),
              _StepButton(icon: Icons.add_rounded, filled: true, onTap: onPlus),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).brightness == Brightness.dark
        ? AppColors.borderDark
        : AppColors.border;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: filled ? AppColors.accent : Colors.transparent,
          border: filled ? null : Border.all(color: border),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(
          icon,
          size: 17,
          color: filled
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _QuickTimeChip extends StatelessWidget {
  const _QuickTimeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).brightness == Brightness.dark
        ? AppColors.borderDark
        : AppColors.border;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _SymptomChip extends StatelessWidget {
  const _SymptomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).brightness == Brightness.dark
        ? AppColors.borderDark
        : AppColors.border;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          border: Border.all(color: selected ? AppColors.accent : border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
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

/// Platzhalter-Chips mit Shimmer, solange die Symptome laden.
class _SymptomSkeleton extends StatelessWidget {
  const _SymptomSkeleton();

  // ungefähr die Breiten echter Symptom-Namen, damit es natürlich wirkt
  static const _widths = [122.0, 84.0, 98.0, 132.0, 88.0, 94.0, 140.0];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1E2826) : AppColors.surface2;
    final highlight = isDark ? const Color(0xFF2C3836) : const Color(0xFFF7F9F7);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1300),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final w in _widths)
            Container(
              width: w,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white, // wird vom Shimmer eingefärbt
                borderRadius: BorderRadius.circular(20),
              ),
            ),
        ],
      ),
    );
  }
}

/// "+ eigenes"-Chip mit gestricheltem Rahmen (wie im Mockup).
class _AddSymptomChip extends StatelessWidget {
  const _AddSymptomChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: CustomPaint(
        painter: _DashedPillPainter(color: AppColors.accent),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            '+ eigenes',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedPillPainter extends CustomPainter {
  _DashedPillPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(0.6),
          Radius.circular(size.height / 2),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPillPainter old) => old.color != color;
}

/// Eingabefeld für ein eigenes Symptom, erscheint unter den Chips.
class _CustomSymptomField extends StatelessWidget {
  const _CustomSymptomField({
    required this.controller,
    required this.focusNode,
    required this.saving,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool saving;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inkSoft = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: !saving,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            maxLength: 40,
            onSubmitted: (_) => onSubmit(),
            decoration: const InputDecoration(
              hintText: 'Eigenes Symptom, z.B. Gelenkschmerzen',
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: saving ? null : onCancel,
          icon: const Icon(Icons.close_rounded),
          color: inkSoft,
          tooltip: 'Abbrechen',
        ),
        SizedBox(
          width: 40,
          height: 40,
          child: Material(
            color: AppColors.accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: saving ? null : onSubmit,
              child: saving
                  ? const Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
