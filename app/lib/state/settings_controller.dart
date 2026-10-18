import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:album_manager/theme/app_theme.dart';

/// Appearance preferences. Only the app root listens to this.
class SettingsController extends ChangeNotifier {
  late final SharedPreferences prefs;
  ThemeMode themeMode = ThemeMode.system;
  bool useSystemColor = true;

  /// Seed used when the system accent color is off (or unavailable).
  Color seedColor = defaultSeed;

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? ThemeMode.system.index];
    useSystemColor = prefs.getBool('useSystemColor') ?? true;
    seedColor = Color(prefs.getInt('seedColor') ?? defaultSeed.toARGB32());
  }

  void setThemeMode(ThemeMode m) {
    if (m == themeMode) return;
    themeMode = m;
    prefs.setInt('themeMode', m.index);
    notifyListeners();
  }

  void setUseSystemColor(bool v) {
    if (v == useSystemColor) return;
    useSystemColor = v;
    prefs.setBool('useSystemColor', v);
    notifyListeners();
  }

  void setSeedColor(Color c) {
    if (c == seedColor) return;
    seedColor = c;
    prefs.setInt('seedColor', c.toARGB32());
    notifyListeners();
  }
}

final settings = SettingsController();
