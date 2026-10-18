import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance preferences. Only the app root listens to this.
class SettingsController extends ChangeNotifier {
  late final SharedPreferences prefs;
  ThemeMode themeMode = ThemeMode.system;
  bool useSystemColor = true;

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? ThemeMode.system.index];
    useSystemColor = prefs.getBool('useSystemColor') ?? true;
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
}

final settings = SettingsController();
