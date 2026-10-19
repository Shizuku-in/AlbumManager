import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/theme/app_theme.dart';

/// Grid card width presets.
enum CardSize {
  small('小', 160),
  medium('中', 220),
  large('大', 300);

  const CardSize(this.label, this.maxExtent);
  final String label;
  final double maxExtent;
}

/// Optional details on a grid card (the title is always shown).
enum CardField {
  source('来源'),
  quality('高解析度标记'),
  artist('艺术家'),
  date('日期'),
  ripStatus('抓轨状态');

  const CardField(this.label);
  final String label;
}

/// How release dates (`YYYY`, `YYYY-MM` or `YYYY-MM-DD`) are shown.
enum DateStyle {
  iso('2024-03-15'),
  slash('2024/03/15'),
  chinese('2024年3月15日'),
  year('仅年份');

  const DateStyle(this.label);
  final String label;

  String? format(String? date) {
    if (date == null) return null;
    final p = date.split('-');
    return switch (this) {
      DateStyle.iso => date,
      DateStyle.slash => p.join('/'),
      DateStyle.chinese =>
        '${p[0]}年${p.length > 1 ? '${int.parse(p[1])}月' : ''}${p.length > 2 ? '${int.parse(p[2])}日' : ''}',
      DateStyle.year => p[0],
    };
  }
}

/// Navigation destinations the user can hide.
enum HideablePage {
  timeline('时间线'),
  stats('统计'),
  health('健康检查');

  const HideablePage(this.label);
  final String label;
}

/// User preferences: appearance, display, scanning and health checks.
///
/// Set-valued options are replaced (never mutated) on change so memoized
/// views can key on them.
class SettingsController extends ChangeNotifier {
  late final SharedPreferences prefs;
  ThemeMode themeMode = ThemeMode.system;
  bool useSystemColor = true;

  /// Seed used when the system accent color is off (or unavailable).
  Color seedColor = defaultSeed;

  bool scanOnStartup = true;

  /// Issue kinds the user turned off.
  Set<IssueKind> hiddenIssues = const {};

  CardSize cardSize = CardSize.medium;
  Set<CardField> hiddenCardFields = const {};
  DateStyle dateStyle = DateStyle.iso;
  Set<HideablePage> hiddenPages = const {};

  /// Restore the library filters on the next launch.
  bool rememberFilters = false;

  Set<T> _loadSet<T extends Enum>(String key, List<T> values) {
    final names = prefs.getStringList(key) ?? const [];
    return {
      for (final v in values)
        if (names.contains(v.name)) v,
    };
  }

  T _loadEnum<T extends Enum>(String key, List<T> values, T fallback) =>
      values.where((v) => v.name == prefs.getString(key)).firstOrNull ??
      fallback;

  /// Returns [set] with [v] added or removed, persisted under [key].
  Set<T> _toggle<T extends Enum>(String key, Set<T> set, T v, bool include) {
    final next = include ? {...set, v} : ({...set}..remove(v));
    prefs.setStringList(key, [for (final e in next) e.name]);
    return next;
  }

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    themeMode =
        ThemeMode.values[prefs.getInt('themeMode') ?? ThemeMode.system.index];
    useSystemColor = prefs.getBool('useSystemColor') ?? true;
    seedColor = Color(prefs.getInt('seedColor') ?? defaultSeed.toARGB32());
    scanOnStartup = prefs.getBool('scanOnStartup') ?? true;
    hiddenIssues = _loadSet('hiddenIssues', IssueKind.values);
    cardSize = _loadEnum('cardSize', CardSize.values, CardSize.medium);
    hiddenCardFields = _loadSet('hiddenCardFields', CardField.values);
    dateStyle = _loadEnum('dateStyle', DateStyle.values, DateStyle.iso);
    hiddenPages = _loadSet('hiddenPages', HideablePage.values);
    rememberFilters = prefs.getBool('rememberFilters') ?? false;
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
    hiddenIssues = _toggle('hiddenIssues', hiddenIssues, k, !enabled);
    notifyListeners();
  }

  /// The album's issues minus the kinds turned off.
  List<Issue> issuesOf(AlbumSummary a) => hiddenIssues.isEmpty
      ? a.issues
      : a.issues.where((i) => !hiddenIssues.contains(i.kind)).toList();

  void setCardSize(CardSize s) {
    if (s == cardSize) return;
    cardSize = s;
    prefs.setString('cardSize', s.name);
    notifyListeners();
  }

  bool showsOnCard(CardField f) => !hiddenCardFields.contains(f);

  void setCardField(CardField f, bool shown) {
    if (shown == showsOnCard(f)) return;
    hiddenCardFields = _toggle('hiddenCardFields', hiddenCardFields, f, !shown);
    notifyListeners();
  }

  void setDateStyle(DateStyle s) {
    if (s == dateStyle) return;
    dateStyle = s;
    prefs.setString('dateStyle', s.name);
    notifyListeners();
  }

  /// A release date in the chosen style.
  String? formatDate(String? date) => dateStyle.format(date);

  void setPageShown(HideablePage p, bool shown) {
    if (shown != hiddenPages.contains(p)) return;
    hiddenPages = _toggle('hiddenPages', hiddenPages, p, !shown);
    notifyListeners();
  }

  void setRememberFilters(bool v) {
    if (v == rememberFilters) return;
    rememberFilters = v;
    prefs.setBool('rememberFilters', v);
    notifyListeners();
  }
}

final settings = SettingsController();
