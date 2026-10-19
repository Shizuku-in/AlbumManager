import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/theme/app_theme.dart';

/// User preferences: appearance, scanning and health checks.
class SettingsController extends ChangeNotifier {
  late final SharedPreferences prefs;
  ThemeMode themeMode = ThemeMode.system;
  bool useSystemColor = true;

  /// Seed used when the system accent color is off (or unavailable).
  Color seedColor = defaultSeed;

  bool scanOnStartup = true;

  /// Issue kinds the user turned off. Replaced (never mutated) on change so
  /// memoized views can key on it.
  Set<IssueKind> hiddenIssues = const {};

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? ThemeMode.system.index];
    useSystemColor = prefs.getBool('useSystemColor') ?? true;
    seedColor = Color(prefs.getInt('seedColor') ?? defaultSeed.toARGB32());
    scanOnStartup = prefs.getBool('scanOnStartup') ?? true;
    final hidden = prefs.getStringList('hiddenIssues') ?? const [];
    hiddenIssues = {for (final k in IssueKind.values) if (hidden.contains(k.name)) k};
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

  void setScanOnStartup(bool v) {
    if (v == scanOnStartup) return;
    scanOnStartup = v;
    prefs.setBool('scanOnStartup', v);
    notifyListeners();
  }

  void setIssueEnabled(IssueKind k, bool enabled) {
    if (enabled != hiddenIssues.contains(k)) return;
    hiddenIssues = enabled ? ({...hiddenIssues}..remove(k)) : {...hiddenIssues, k};
    prefs.setStringList('hiddenIssues', [for (final k in hiddenIssues) k.name]);
    notifyListeners();
  }

  /// The album's issues minus the kinds turned off.
  List<Issue> issuesOf(AlbumSummary a) =>
      hiddenIssues.isEmpty ? a.issues : a.issues.where((i) => !hiddenIssues.contains(i.kind)).toList();
}

final settings = SettingsController();
