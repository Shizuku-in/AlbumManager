import 'package:flutter/foundation.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/navigation.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/util/memo.dart';

enum SourceFilter { all, cdRip, digital, hiRes, dsd, discImage }

enum SortMode { dateDesc, dateAsc, addedDesc, title, artist, size }

extension SortModeX on SortMode {
  String get label => switch (this) {
        SortMode.dateDesc => '发行日期（新→旧）',
        SortMode.dateAsc => '发行日期（旧→新）',
        SortMode.addedDesc => '最近添加',
        SortMode.title => '标题',
        SortMode.artist => '艺术家',
        SortMode.size => '占用空间',
      };
  bool get groupsByYear => this == SortMode.dateDesc || this == SortMode.dateAsc;
}

extension SourceFilterX on SourceFilter {
  String get label => switch (this) {
        SourceFilter.all => '全部',
        SourceFilter.cdRip => 'CD 抓轨',
        SourceFilter.digital => '数字发行',
        SourceFilter.hiRes => 'Hi-Res',
        SourceFilter.dsd => 'DSD',
        SourceFilter.discImage => '光盘镜像',
      };
  bool matches(AlbumSummary a) => switch (this) {
        SourceFilter.all => true,
        SourceFilter.cdRip => a.source == AlbumSource.cdRip,
        SourceFilter.digital => a.source == AlbumSource.digital,
        SourceFilter.hiRes => a.quality == AudioQuality.hiRes,
        SourceFilter.dsd => a.quality == AudioQuality.dsd,
        SourceFilter.discImage => a.source == AlbumSource.discImage,
      };
}

/// Search / filter / sort / layout of the library page. Kept apart from the
/// album data so typing or toggling the layout only rebuilds that page.
class LibraryBrowser extends ChangeNotifier {
  String query = '';
  SourceFilter filter = SourceFilter.all;
  SortMode sort = SortMode.dateDesc;
  int? yearFilter;
  bool gridView = true;

  void load() => gridView = settings.prefs.getBool('gridView') ?? true;

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

  /// Opens the library tab filtered to one year (null = unknown year → no filter).
  void showYear(int? y) {
    setYear(y);
    navIndex.value = 0;
  }

  void setGridView(bool v) {
    if (v == gridView) return;
    gridView = v;
    settings.prefs.setBool('gridView', v);
    notifyListeners();
  }

  final _visible = Memo<(List<AlbumSummary>, String, SourceFilter, SortMode, int?), List<AlbumSummary>>();
  final _counts = Memo<List<AlbumSummary>, Map<SourceFilter, int>>();

  /// Albums after search / filters / sort.
  List<AlbumSummary> visible(List<AlbumSummary> albums) => _visible((albums, query, filter, sort, yearFilter), () {
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
      });

  /// Number of albums per source filter (for the filter chips).
  Map<SourceFilter, int> counts(List<AlbumSummary> albums) =>
      _counts(albums, () => {for (final f in SourceFilter.values) f: albums.where(f.matches).length});
}

final browser = LibraryBrowser();
