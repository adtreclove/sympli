import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/controllers/today_controller.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/services/navigation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://mcjxgsividqcrjamsagl.supabase.co',
    publishableKey: 'sb_publishable_o2r96FIO_3LPXoRb7FEwkQ_lSKIVuk6',
  );

  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Sympli',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // folgt der Geräte-Einstellung, bis man oben rechts umschaltet
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
    );
  }
}
