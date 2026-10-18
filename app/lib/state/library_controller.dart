import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/api/models.dart';
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_query.dart';

export 'library_query.dart';

class ScanProgress {
  final int done;
  final int total;
  final String current;
  const ScanProgress(this.done, this.total, this.current);
  double get fraction => total == 0 ? 0 : done / total;
}

/// App-wide library state.
class LibraryController extends ChangeNotifier {
  String? root;
  List<AlbumSummary> albums = const [];
  bool ready = false;
  ScanProgress? scan;
  String? lastScanMessage;

  // View state.
  int navIndex = 0;
  String query = '';
  SourceFilter filter = SourceFilter.all;
  SortMode sort = SortMode.dateDesc;
  int? yearFilter;
  bool gridView = true;

  /// Bumped when one album changes so detail pages can reload.
  final albumChanged = ValueNotifier<String?>(null);

  // Appearance.
  ThemeMode themeMode = ThemeMode.system;
  bool useSystemColor = true;
  SharedPreferences? _prefs;

  Future<void> loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[_prefs!.getInt('themeMode') ?? ThemeMode.system.index];
    useSystemColor = _prefs!.getBool('useSystemColor') ?? true;
    gridView = _prefs!.getBool('gridView') ?? true;
  }

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _prefs?.setInt('themeMode', m.index);
    notifyListeners();
  }

  void setUseSystemColor(bool v) {
    useSystemColor = v;
    _prefs?.setBool('useSystemColor', v);
    notifyListeners();
  }

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final info = await api.initLibrary(dataDir: dir.path);
    root = info.root;
    albums = info.albums;
    ready = true;
    notifyListeners();
    if (root != null && Directory(root!).existsSync()) {
      unawaited(rescan());
    }
  }

  Future<void> setRoot(String path) async {
    await api.setLibraryRoot(root: path);
    if (path != root) albums = const [];
    root = path;
    notifyListeners();
    await rescan();
  }

  bool get scanning => scan != null;

  Future<void> rescan({bool force = false}) async {
    if (scanning || root == null) return;
    scan = const ScanProgress(0, 0, '正在查找专辑…');
    notifyListeners();
    try {
      await for (final e in api.scanLibrary(force: force)) {
        switch (e) {
          case ScanEvent_Started(:final total):
            scan = ScanProgress(0, total, '');
          case ScanEvent_Progress(:final done, :final total, :final current):
            scan = ScanProgress(done, total, current);
          case ScanEvent_Finished(:final albums, :final elapsedMs, :final rescanned):
            this.albums = albums;
            lastScanMessage = '扫描完成：${albums.length} 张专辑，更新 $rescanned 张，用时 ${(elapsedMs / 1000).toStringAsFixed(1)} 秒';
        }
        notifyListeners();
      }
    } catch (e) {
      lastScanMessage = '扫描失败：$e';
    } finally {
      scan = null;
      notifyListeners();
    }
  }

  void replaceAlbum(AlbumSummary s) {
    albums = [for (final a in albums) a.id == s.id ? s : a];
    albumChanged.value = s.id;
    notifyListeners();
  }

  Future<Album> fixCue(String id) async {
    final album = await api.fixCueEncoding(id: id);
    replaceAlbum(album.summary);
    return album;
  }

  // ---- view state ----
  void setNav(int i) {
    navIndex = i;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setFilter(SourceFilter f) {
    filter = f;
    notifyListeners();
  }

  void setSort(SortMode s) {
    sort = s;
    notifyListeners();
  }

  void setYear(int? y) {
    yearFilter = y;
    notifyListeners();
  }

  void setGridView(bool v) {
    gridView = v;
    _prefs?.setBool('gridView', v);
    notifyListeners();
  }

  /// Albums after search / filters / sort.
  List<AlbumSummary> get visible {
    final q = query.trim().toLowerCase();
    final list = albums.where((a) {
      if (!filter.matches(a)) return false;
      if (yearFilter != null && a.year != yearFilter) return false;
      if (q.isEmpty) return true;
      return a.title.toLowerCase().contains(q) ||
          (a.artist?.toLowerCase().contains(q) ?? false) ||
          a.folderName.toLowerCase().contains(q) ||
          (a.genre?.toLowerCase().contains(q) ?? false);
    }).toList();
    int byDate(AlbumSummary a, AlbumSummary b) => (a.date ?? '${a.year ?? 0}').compareTo(b.date ?? '${b.year ?? 0}');
    switch (sort) {
      case SortMode.dateDesc:
        list.sort((a, b) => byDate(b, a));
      case SortMode.dateAsc:
        list.sort(byDate);
      case SortMode.addedDesc:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case SortMode.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SortMode.artist:
        list.sort((a, b) => (a.artist ?? '￿').compareTo(b.artist ?? '￿'));
      case SortMode.size:
        list.sort((a, b) => b.totalSize.compareTo(a.totalSize));
    }
    return list;
  }

  Map<int, List<AlbumSummary>> get byYear {
    final m = <int, List<AlbumSummary>>{};
    for (final a in albums) {
      m.putIfAbsent(a.year ?? 0, () => []).add(a);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));
  }

  /// Same metric as the health page: one per (album, issue kind).
  int get issueCount => albums.fold(0, (n, a) => n + a.issues.map((i) => i.kind).toSet().length);
}

final library = LibraryController();
