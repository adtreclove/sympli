import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  final _supabase = Supabase.instance.client;

  DateTime _occurredAt = DateTime.now();
  String? _selectedSymptomId;
  int _intensity = 3;
  bool _isSaving = false;
  String? _error;

  List<_Symptom> _symptoms = [];
  bool _loadingSymptoms = true;

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
        'occurred_at': _occurredAt.toIso8601String(),
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
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
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
                          ],
                        ),
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
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('UHRZEIT', style: theme.textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(
                label,
                style: (mono ?? const TextStyle()).copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
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
