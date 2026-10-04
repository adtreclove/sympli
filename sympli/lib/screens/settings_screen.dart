import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/controllers/theme_controller.dart';
import 'package:sympli/controllers/user_settings_controller.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/models/factor.dart';
import 'package:sympli/services/weather_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<GeoPlace> _results = const [];
  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (text.trim().length < 2) {
        setState(() => _results = const []);
        return;
      }
      setState(() => _searching = true);
      try {
        final results = await WeatherService.searchPlaces(text);
        if (mounted) setState(() => _results = results);
      } catch (_) {
        if (mounted) setState(() => _error = 'Ortssuche nicht erreichbar.');
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _save(UserSettings settings) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userSettingsProvider.notifier).save(settings);
    } catch (_) {
      setState(() => _error = 'Einstellung konnte nicht gespeichert werden.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    invalidateUserData(ref);
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final settingsAsync = ref.watch(userSettingsProvider);
    final settings = settingsAsync.value ?? const UserSettings();
    final themeMode = ref.watch(themeModeProvider);
    final email = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 22, 40),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Einstellungen',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.coral,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Female cycle
                      _SectionLabel('ZYKLUS'),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Zyklus erfassen',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                Switch(
                                  value: settings.trackCycle,
                                  activeTrackColor: AppColors.accent,
                                  onChanged: _saving || !settingsAsync.hasValue
                                      ? null
                                      : (v) => _save(
                                          settings.copyWith(trackCycle: v),
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Freiwillig. Im Abend-Check-in fragen wir dann, ob '
                              'du deine Periode hast. So können wir erkennen, ob '
                              'Symptome mit deinem Zyklus zusammenhängen – z.B. '
                              'in den Tagen davor. Nur für dich sichtbar.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Weather
                      _SectionLabel('WETTER'),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 20,
                                  color: settings.hasLocation
                                      ? AppColors.accent
                                      : faint,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    settings.city ?? 'Kein Ort festgelegt',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                if (settings.hasLocation)
                                  TextButton(
                                    onPressed: _saving
                                        ? null
                                        : () => _save(
                                            settings.withLocation(
                                              null,
                                              null,
                                              null,
                                            ),
                                          ),
                                    child: const Text('Entfernen'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: settings.hasLocation
                                    ? 'Anderen Ort suchen …'
                                    : 'Stadt suchen, z.B. Münster',
                                isDense: true,
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _searching
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            for (final place in _results)
                              InkWell(
                                onTap: () async {
                                  final name = place.name;
                                  _searchController.clear();
                                  setState(() => _results = const []);
                                  FocusScope.of(context).unfocus();
                                  await _save(
                                    settings.withLocation(
                                      name,
                                      place.latitude,
                                      place.longitude,
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                    horizontal: 4,
                                  ),
                                  child: Text(
                                    place.label,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                            Text(
                              'Wir nutzen nur die Stadt, um Luftdruck, '
                              'Temperatur und Regen abzurufen (Open-Meteo). '
                              'Luftdruckwechsel sind z.B. bei Kopfschmerzen oft '
                              'ein Auslöser.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Display
                      _SectionLabel('DARSTELLUNG'),
                      _Card(
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('System'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Hell'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Dunkel'),
                            ),
                          ],
                          selected: {themeMode},
                          onSelectionChanged: (s) =>
                              ref.read(themeModeProvider.notifier).set(s.first),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // User account
                      _SectionLabel('KONTO'),
                      _Card(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                email ?? '',
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: _logout,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.coral,
                              ),
                              child: const Text('Abmelden'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(letterSpacing: 0.9),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
      ),
      child: child,
    );
  }
}
