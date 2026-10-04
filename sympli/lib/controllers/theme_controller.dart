import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Starts with device settings
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void toggle(Brightness current) {
    state = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
