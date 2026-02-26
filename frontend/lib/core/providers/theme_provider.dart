import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../main.dart';

part 'theme_provider.g.dart';

@riverpod
class ThemeModeNotifier extends _$ThemeModeNotifier {
  static const _themeKey = 'app_theme_mode';

  @override
  ThemeMode build() {
    final savedMode = sharedPrefs.getString(_themeKey);
    if (savedMode != null) {
      return ThemeMode.values.firstWhere(
        (m) => m.name == savedMode,
        orElse: () => ThemeMode.system,
      );
    }
    return ThemeMode.system;
  }

  void set(ThemeMode mode) {
    state = mode;
    sharedPrefs.setString(_themeKey, mode.name);
  }
}
