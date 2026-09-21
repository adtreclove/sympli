import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/services/navigation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://mcjxgsividqcrjamsagl.supabase.co',
    publishableKey: 'sb_publishable_o2r96FIO_3LPXoRb7FEwkQ_lSKIVuk6',
  );

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sympli',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system, // folgt der Geräte-Einstellung
      routerConfig: router,
    );
  }
}
