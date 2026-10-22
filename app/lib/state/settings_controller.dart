import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_types.dart';
import 'package:album_manager/theme/app_theme.dart';

export 'package:album_manager/state/settings_types.dart';

/// One stored preference: its key, default and how it's (de)serialized.
class _Pref<T> {
  _Pref(this.key, this.fallback, this._decode, this._encode);
  final String key;
  final T fallback;
  final T? Function(SharedPreferences p, String key) _decode;
  final Future<bool> Function(SharedPreferences p, String key, T v) _encode;
  late T value = fallback;

  /// The stored value, or the default when the key is absent.
  void load(SharedPreferences p) => value = _decode(p, key) ?? fallback;

  void store(SharedPreferences p, T v) {
    value = v;
    _encode(p, key, v);
  }
}

_Pref<bool> _bool(String key, bool fallback) =>
    _Pref(key, fallback, (p, k) => p.getBool(k), (p, k, v) => p.setBool(k, v));

/// Stored by name, so reordering or adding values keeps saved choices.
_Pref<T> _enum<T extends Enum>(String key, List<T> values, T fallback) => _Pref(
  key,
  fallback,
  (p, k) => values.asNameMap()[p.getString(k)],
  (p, k, v) => p.setString(k, v.name),
);

/// A set of enum values (empty by default), stored by name.
_Pref<Set<T>> _enumSet<T extends Enum>(String key, List<T> values) =>
    _Pref(key, const {}, (p, k) {
      final names = p.getStringList(k)?.toSet();
      return names == null
          ? null
          : {...values.where((v) => names.contains(v.name))};
    }, (p, k, v) => p.setStringList(k, [for (final e in v) e.name]));

/// User preferences. Each settings page has its own group of preferences,
/// which its "恢复默认" restores.
///
/// Set-valued options are replaced (never mutated) on change so memoized
/// views can key on them.
class SettingsController extends ChangeNotifier {
  late final SharedPreferences prefs;

  // ---- 外观 ----
  final _themeMode = _Pref<ThemeMode>(
    'themeMode',
    ThemeMode.system,
    (p, k) => ThemeMode.values.elementAtOrNull(p.getInt(k) ?? -1),
    (p, k, v) => p.setInt(k, v.index),
  );
  final _useSystemColor = _bool('useSystemColor', true);

  /// Seed used when the system accent color is off (or unavailable).
  final _seedColor = _Pref<Color>(
    'seedColor',
    defaultSeed,
    (p, k) => switch (p.getInt(k)) {
      final v? => Color(v),
      null => null,
    },
    (p, k, v) => p.setInt(k, v.toARGB32()),
  );

  /// UI font family; null = the platform font ([platformFont]).
  final _fontFamily = _Pref<String?>(
    'fontFamily',
    null,
    (p, k) => p.getString(k),
    (p, k, v) => v == null ? p.remove(k) : p.setString(k, v),
  );
  final _hiddenPages = _enumSet('hiddenPages', HideablePage.values);

  // ---- 专辑浏览 ----
  final _cardSize = _enum('cardSize', CardSize.values, CardSize.medium);
  final _hiddenCardFields = _enumSet('hiddenCardFields', CardField.values);
  final _dateStyle = _enum('dateStyle', DateStyle.values, DateStyle.iso);

  /// Fields the library search skips.
  final _hiddenSearchFields = _enumSet(
    'hiddenSearchFields',
    SearchField.values,
  );

  /// Restore the library filters on the next launch.
  final _rememberFilters = _bool('rememberFilters', false);
  final _fileListMode = _enum(
    'fileListMode',
    FileListMode.values,
    FileListMode.flat,
  );
  final _folderView = _enum(
    'folderView',
    FolderView.values,
    FolderView.expanded,
  );

  // ---- 时间线 ----
  final _timelineCard = _enum(
    'timelineCard',
    TimelineCard.values,
    TimelineCard.poster,
  );

  /// Years grouped under a banner per decade.
  final _timelineDecades = _bool('timelineDecades', true);
  final _wallStyle = _enum('wallStyle', WallStyle.values, WallStyle.tilted);
  final _wallGap = _enum('wallGap', WallGap.values, WallGap.spaced);
  final _wallMotion = _enum('wallMotion', WallMotion.values, WallMotion.hover);

  /// Hovered cover walls zoom in slightly (and straighten when tilted).
  final _wallZoom = _bool('wallZoom', true);

  // ---- 位置与扫描 ----
  final _scanOnStartup = _bool('scanOnStartup', true);

  // ---- 在线补全 ----
  final _disabledOnlineSources = _enumSet(
    'disabledOnlineSources',
    OnlineSource.values,
  );

  /// Skip the result list when the best result is the very same disc.
  final _openExactMatch = _bool('openExactMatch', false);
  final _preferChineseTitle = _bool('preferChineseTitle', false);

  /// Values not checked by default when they differ.
  final _unpreselectedFields = _enumSet(
    'unpreselectedFields',
    OnlineField.values,
  );
  final _coverDownload = _enum(
    'coverDownload',
    CoverDownload.values,
    CoverDownload.missing,
  );
  final _coverFileName = _enum(
    'coverFileName',
    CoverFileName.values,
    CoverFileName.cover,
  );

  /// `http://host:port` or `socks5://host:port`; null = direct.
  final _onlineProxy = _Pref<String?>(
    'onlineProxy',
    null,
    (p, k) => p.getString(k),
    (p, k, v) => v == null ? p.remove(k) : p.setString(k, v),
  );
  final _onlineTimeout = _enum(
    'onlineTimeout',
    OnlineTimeout.values,
    OnlineTimeout.normal,
  );

  // ---- 健康检查 ----
  /// Issue kinds the user turned off.
  final _hiddenIssues = _enumSet('hiddenIssues', IssueKind.values);

  /// Converting a cue sheet's encoding overwrites it without keeping a
  /// `*.cue.bak` copy.
  final _overwriteCue = _bool('overwriteCue', false);

  // ---- 抓轨日志 ----
  /// Show the OPS log score and every deduction on the rip log page. The
  /// checks themselves run either way.
  final _showLogScore = _bool('showLogScore', false);

  // Per page, for "恢复默认".
  late final _appearance = <_Pref<Object?>>[
    _themeMode,
    _useSystemColor,
    _seedColor,
    _fontFamily,
    _hiddenPages,
  ];
  late final _browsing = <_Pref<Object?>>[
    _cardSize,
    _hiddenCardFields,
    _dateStyle,
    _hiddenSearchFields,
    _rememberFilters,
    _fileListMode,
    _folderView,
  ];
  late final _timeline = <_Pref<Object?>>[
    _timelineCard,
    _timelineDecades,
    _wallStyle,
    _wallGap,
    _wallMotion,
    _wallZoom,
  ];
  late final _scanning = <_Pref<Object?>>[_scanOnStartup];
  late final _online = <_Pref<Object?>>[
    _disabledOnlineSources,
    _openExactMatch,
    _preferChineseTitle,
    _unpreselectedFields,
    _coverDownload,
    _coverFileName,
    _onlineProxy,
    _onlineTimeout,
  ];
  late final _health = <_Pref<Object?>>[_hiddenIssues, _overwriteCue];
  late final _logDisplay = <_Pref<Object?>>[_showLogScore];

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    for (final group in [
      _appearance,
      _browsing,
      _timeline,
      _scanning,
      _online,
      _health,
      _logDisplay,
    ]) {
      for (final p in group) {
        p.load(prefs);
      }
    }
  }

  Future<void> _reset(List<_Pref<Object?>> group) async {
    for (final p in group) {
      await prefs.remove(p.key);
      p.load(prefs);
    }
    notifyListeners();
  }

  Future<void> resetAppearance() => _reset(_appearance);
  Future<void> resetBrowsing() => _reset(_browsing);
  Future<void> resetTimeline() => _reset(_timeline);
  Future<void> resetScanning() => _reset(_scanning);
  Future<void> resetOnline() => _reset(_online);
  Future<void> resetHealthChecks() => _reset(_health);
  Future<void> resetLogDisplay() => _reset(_logDisplay);

  void _set<T>(_Pref<T> pref, T v) {
    if (v == pref.value) return;
    pref.store(prefs, v);
    notifyListeners();
  }

  /// Adds [item] to or removes it from a set preference.
  void _toggle<T>(_Pref<Set<T>> pref, T item, bool include) {
    final set = pref.value;
    if (set.contains(item) == include) return;
    _set(pref, include ? {...set, item} : ({...set}..remove(item)));
  }

  // ---- 外观 ----
  ThemeMode get themeMode => _themeMode.value;
  void setThemeMode(ThemeMode m) => _set(_themeMode, m);

  bool get useSystemColor => _useSystemColor.value;
  void setUseSystemColor(bool v) => _set(_useSystemColor, v);

  Color get seedColor => _seedColor.value;
  void setSeedColor(Color c) => _set(_seedColor, c);

  String? get fontFamily => _fontFamily.value;
  void setFontFamily(String? f) => _set(_fontFamily, f);

  Set<HideablePage> get hiddenPages => _hiddenPages.value;
  void setPageShown(HideablePage p, bool shown) =>
      _toggle(_hiddenPages, p, !shown);

  // ---- 专辑浏览 ----
  CardSize get cardSize => _cardSize.value;
  void setCardSize(CardSize s) => _set(_cardSize, s);

  bool showsOnCard(CardField f) => !_hiddenCardFields.value.contains(f);
  void setCardField(CardField f, bool shown) =>
      _toggle(_hiddenCardFields, f, !shown);

  DateStyle get dateStyle => _dateStyle.value;
  void setDateStyle(DateStyle s) => _set(_dateStyle, s);

  /// A release date in the chosen style.
  String? formatDate(String? date) => dateStyle.format(date);

  Set<SearchField> get hiddenSearchFields => _hiddenSearchFields.value;
  bool searches(SearchField f) => !hiddenSearchFields.contains(f);
  void setSearchField(SearchField f, bool searched) =>
      _toggle(_hiddenSearchFields, f, !searched);

  bool get rememberFilters => _rememberFilters.value;
  void setRememberFilters(bool v) => _set(_rememberFilters, v);

  FileListMode get fileListMode => _fileListMode.value;
  void setFileListMode(FileListMode m) => _set(_fileListMode, m);

  FolderView get folderView => _folderView.value;
  void setFolderView(FolderView v) => _set(_folderView, v);

  // ---- 时间线 ----
  TimelineCard get timelineCard => _timelineCard.value;
  void setTimelineCard(TimelineCard c) => _set(_timelineCard, c);

  bool get timelineDecades => _timelineDecades.value;
  void setTimelineDecades(bool v) => _set(_timelineDecades, v);

  WallStyle get wallStyle => _wallStyle.value;
  void setWallStyle(WallStyle s) => _set(_wallStyle, s);

  WallGap get wallGap => _wallGap.value;
  void setWallGap(WallGap g) => _set(_wallGap, g);

  WallMotion get wallMotion => _wallMotion.value;
  void setWallMotion(WallMotion m) => _set(_wallMotion, m);

  bool get wallZoom => _wallZoom.value;
  void setWallZoom(bool v) => _set(_wallZoom, v);

  // ---- 位置与扫描 ----
  bool get scanOnStartup => _scanOnStartup.value;
  void setScanOnStartup(bool v) => _set(_scanOnStartup, v);

  // ---- 在线补全 ----
  bool usesOnlineSource(OnlineSource s) =>
      !_disabledOnlineSources.value.contains(s);
  List<OnlineSource> get onlineSources =>
      OnlineSource.values.where(usesOnlineSource).toList();
  void setOnlineSource(OnlineSource s, bool enabled) =>
      _toggle(_disabledOnlineSources, s, !enabled);

  bool get openExactMatch => _openExactMatch.value;
  void setOpenExactMatch(bool v) => _set(_openExactMatch, v);

  bool get preferChineseTitle => _preferChineseTitle.value;
  void setPreferChineseTitle(bool v) => _set(_preferChineseTitle, v);

  bool preselects(OnlineField f) => !_unpreselectedFields.value.contains(f);
  void setPreselected(OnlineField f, bool on) =>
      _toggle(_unpreselectedFields, f, !on);

  CoverDownload get coverDownload => _coverDownload.value;
  void setCoverDownload(CoverDownload c) => _set(_coverDownload, c);

  CoverFileName get coverFileName => _coverFileName.value;
  void setCoverFileName(CoverFileName n) => _set(_coverFileName, n);

  String? get onlineProxy => _onlineProxy.value;
  void setOnlineProxy(String? p) =>
      _set(_onlineProxy, p == null || p.trim().isEmpty ? null : p.trim());

  OnlineTimeout get onlineTimeout => _onlineTimeout.value;
  void setOnlineTimeout(OnlineTimeout t) => _set(_onlineTimeout, t);

  /// What the Rust side needs for requests.
  OnlineOptions get onlineOptions => OnlineOptions(
    proxy: onlineProxy,
    timeoutSecs: onlineTimeout.seconds,
    preferChineseTitle: preferChineseTitle,
  );

  // ---- 健康检查 ----
  Set<IssueKind> get hiddenIssues => _hiddenIssues.value;
  void setIssueEnabled(IssueKind k, bool enabled) =>
      _toggle(_hiddenIssues, k, !enabled);

  /// The album's issues minus the kinds turned off.
  List<Issue> issuesOf(AlbumSummary a) => hiddenIssues.isEmpty
      ? a.issues
      : a.issues.where((i) => !hiddenIssues.contains(i.kind)).toList();

  bool get overwriteCue => _overwriteCue.value;
  void setOverwriteCue(bool v) => _set(_overwriteCue, v);

  /// A cue sheet that converting rewrites: not UTF-8, or (while that check
  /// is on) UTF-8 without a BOM.
  bool cueNeedsFix(CueInfo c) =>
      !c.isUtf8 ||
      (c.missingBom && !hiddenIssues.contains(IssueKind.cueMissingBom));

  // ---- 抓轨日志 ----
  bool get showLogScore => _showLogScore.value;
  void setShowLogScore(bool v) => _set(_showLogScore, v);
}

final settings = SettingsController();
