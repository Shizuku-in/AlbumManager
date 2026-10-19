import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/api/models.dart';
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/util/memo.dart';

class ScanProgress {
  final int done;
  final int total;
  final String current;
  const ScanProgress(this.done, this.total, this.current);
  double get fraction => total == 0 ? 0 : done / total;
}

/// The album library. Notifies only when the data changes (albums, root,
/// scan started / finished); per-album scan progress goes to [scanProgress].
class LibraryController extends ChangeNotifier {
  String? root;
  List<AlbumSummary> albums = const [];
  bool ready = false;
  String? lastScanMessage;

  /// Non-null while a scan is running. Updated ~30×/s, so only the progress
  /// indicators listen to it.
  final scanProgress = ValueNotifier<ScanProgress?>(null);

  /// Bumped when one album changes so detail pages can reload; [allAlbums]
  /// when every album may have changed.
  final albumChanged = ValueNotifier<String?>(null);
  static const allAlbums = '*';

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final info = await api.initLibrary(dataDir: dir.path);
    root = info.root;
    albums = info.albums;
    ready = true;
    notifyListeners();
    if (settings.scanOnStartup &&
        root != null &&
        Directory(root!).existsSync()) {
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

  bool get scanning => scanProgress.value != null;

  Future<void> rescan({bool force = false}) async {
    if (scanning || root == null) return;
    scanProgress.value = const ScanProgress(0, 0, '');
    notifyListeners();
    try {
      await for (final e in api.scanLibrary(force: force)) {
        switch (e) {
          case ScanEvent_Started(:final total):
            scanProgress.value = ScanProgress(0, total, '');
          case ScanEvent_Progress(:final done, :final total, :final current):
            scanProgress.value = ScanProgress(done, total, current);
          case ScanEvent_Finished(
            :final albums,
            :final elapsedMs,
            :final rescanned,
          ):
            this.albums = albums;
            lastScanMessage =
                '扫描完成：${albums.length} 张专辑，更新 $rescanned 张，用时 ${(elapsedMs / 1000).toStringAsFixed(1)} 秒';
        }
      }
    } catch (e) {
      lastScanMessage = '扫描失败：$e';
    } finally {
      scanProgress.value = null;
      notifyListeners();
    }
  }

  void replaceAlbum(AlbumSummary s) {
    albums = [for (final a in albums) a.id == s.id ? s : a];
    albumChanged.value = s.id;
    notifyListeners();
  }

  /// Applies new rip log rules: the library re-judges every album's logs.
  Future<void> setRipRules(RipRules rules) async {
    albums = await api.setRipRules(rules: rules);
    // Open album pages reload their logs.
    albumChanged.value = null;
    albumChanged.value = allAlbums;
    notifyListeners();
  }

  Future<Album> fixCue(String id) async {
    final album = await api.fixCueEncoding(id: id);
    replaceAlbum(album.summary);
    return album;
  }

  final _byYear = Memo<List<AlbumSummary>, Map<int, List<AlbumSummary>>>();
  final _issueCount = Memo<(List<AlbumSummary>, Set<IssueKind>), int>();

  /// Albums grouped by year, newest first (0 = unknown year).
  Map<int, List<AlbumSummary>> get byYear => _byYear(albums, () {
    final m = <int, List<AlbumSummary>>{};
    for (final a in albums) {
      m.putIfAbsent(a.year ?? 0, () => []).add(a);
    }
    return Map.fromEntries(
      m.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
  });

  /// Same metric as the health page: one per (album, issue kind).
  int get issueCount => _issueCount(
    (albums, settings.hiddenIssues),
    () => albums.fold(
      0,
      (n, a) => n + settings.issuesOf(a).map((i) => i.kind).toSet().length,
    ),
  );
}

final library = LibraryController();
