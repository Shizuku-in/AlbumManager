import 'package:flutter/foundation.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/navigation.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/util/memo.dart';

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

/// Yes/no properties of an album.
enum ContentFlag { hasIssues, missingCover, hasScans, hasCue, multiDisc, edited }

extension ContentFlagX on ContentFlag {
  String get label => switch (this) {
    ContentFlag.hasIssues => '有问题',
    ContentFlag.missingCover => '缺少封面',
    ContentFlag.hasScans => '有扫图',
    ContentFlag.hasCue => '有 CUE',
    ContentFlag.multiDisc => '多碟',
    ContentFlag.edited => '手动编辑过',
  };
  bool matches(AlbumSummary a) => switch (this) {
    ContentFlag.hasIssues => a.issues.isNotEmpty,
    ContentFlag.missingCover => a.coverThumb == null,
    // More than one image: a cover alone isn't a scan.
    ContentFlag.hasScans => a.imageCount > 1,
    ContentFlag.hasCue => a.hasCue,
    ContentFlag.multiDisc => a.discCount > 1,
    ContentFlag.edited => a.overrides.source != null || a.overrides.coverPath != null,
  };
}

/// Rip statuses offered as filters (CD rips only).
const ripStatusFilters = [RipStatus.perfect, RipStatus.good, RipStatus.warning, RipStatus.error, RipStatus.noLog, RipStatus.unknown];

enum FilterMode { include, exclude }

/// Tri-state selection of one filter group's options: an option is absent
/// (no constraint), included or excluded. Immutable.
class TriFilter<T> {
  final Map<T, FilterMode> modes;
  const TriFilter([this.modes = const {}]);

  int get length => modes.length;
  FilterMode? operator [](T option) => modes[option];

  /// Click cycle: none → include → exclude → none.
  TriFilter<T> cycle(T option) {
    final m = {...modes};
    switch (m[option]) {
      case null:
        m[option] = FilterMode.include;
      case FilterMode.include:
        m[option] = FilterMode.exclude;
      case FilterMode.exclude:
        m.remove(option);
    }
    return TriFilter(m);
  }

  /// Some included option is among [values] (if any are included) and no
  /// excluded one is.
  bool matchesAny(Iterable<T> values) {
    var anyIncluded = false, hit = false;
    for (final e in modes.entries) {
      final present = values.contains(e.key);
      if (e.value == FilterMode.exclude) {
        if (present) return false;
      } else {
        anyIncluded = true;
        hit |= present;
      }
    }
    return !anyIncluded || hit;
  }
}

/// Filter selection. Within a group any included option matches and no
/// excluded one may; groups combine with AND. Content flags are each a
/// condition: included = must hold, excluded = must not. Immutable: every
/// change makes a new instance, so derived lists memoize by identity.
class AlbumFilters {
  final TriFilter<AlbumSource> sources;
  final TriFilter<AudioQuality> qualities;
  final TriFilter<String> formats;
  final TriFilter<RipStatus> ripStatuses;
  final TriFilter<ContentFlag> flags;
  const AlbumFilters({
    this.sources = const TriFilter(),
    this.qualities = const TriFilter(),
    this.formats = const TriFilter(),
    this.ripStatuses = const TriFilter(),
    this.flags = const TriFilter(),
  });

  int get count => sources.length + qualities.length + formats.length + ripStatuses.length + flags.length;

  bool matches(AlbumSummary a) =>
      sources.matchesAny([a.source]) &&
      qualities.matchesAny([a.quality]) &&
      formats.matchesAny(a.formats) &&
      ripStatuses.matchesAny([a.ripStatus]) &&
      flags.modes.entries.every((e) => e.key.matches(a) == (e.value == FilterMode.include));

  AlbumFilters cycleSource(AlbumSource v) =>
      AlbumFilters(sources: sources.cycle(v), qualities: qualities, formats: formats, ripStatuses: ripStatuses, flags: flags);
  AlbumFilters cycleQuality(AudioQuality v) =>
      AlbumFilters(sources: sources, qualities: qualities.cycle(v), formats: formats, ripStatuses: ripStatuses, flags: flags);
  AlbumFilters cycleFormat(String v) => AlbumFilters(sources: sources, qualities: qualities, formats: formats.cycle(v), ripStatuses: ripStatuses, flags: flags);
  AlbumFilters cycleRipStatus(RipStatus v) =>
      AlbumFilters(sources: sources, qualities: qualities, formats: formats, ripStatuses: ripStatuses.cycle(v), flags: flags);
  AlbumFilters cycleFlag(ContentFlag v) =>
      AlbumFilters(sources: sources, qualities: qualities, formats: formats, ripStatuses: ripStatuses, flags: flags.cycle(v));
}

/// Album counts per filter option, over the whole library.
class FilterCounts {
  final Map<AlbumSource, int> sources = {};
  final Map<AudioQuality, int> qualities = {};

  /// Most common first.
  final Map<String, int> formats;
  final Map<RipStatus, int> ripStatuses = {};
  final Map<ContentFlag, int> flags;

  FilterCounts(List<AlbumSummary> albums) : formats = {}, flags = {for (final f in ContentFlag.values) f: albums.where(f.matches).length} {
    final fmt = <String, int>{};
    for (final a in albums) {
      sources.update(a.source, (n) => n + 1, ifAbsent: () => 1);
      qualities.update(a.quality, (n) => n + 1, ifAbsent: () => 1);
      ripStatuses.update(a.ripStatus, (n) => n + 1, ifAbsent: () => 1);
      for (final f in a.formats) {
        fmt.update(f, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    formats.addEntries(fmt.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
}

/// Search / filter / sort / layout of the library page. Kept apart from the
/// album data so typing or toggling the layout only rebuilds that page.
class LibraryBrowser extends ChangeNotifier {
  String query = '';
  AlbumFilters filters = const AlbumFilters();
  SortMode sort = SortMode.dateDesc;
  int? yearFilter;
  bool gridView = true;

  void load() => gridView = settings.prefs.getBool('gridView') ?? true;

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setFilters(AlbumFilters f) {
    filters = f;
    notifyListeners();
  }

  /// Number of active filters, including the year.
  int get activeFilterCount => filters.count + (yearFilter == null ? 0 : 1);

  void clearFilters() {
    filters = const AlbumFilters();
    yearFilter = null;
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

  final _visible = Memo<(List<AlbumSummary>, String, AlbumFilters, SortMode, int?), List<AlbumSummary>>();
  final _counts = Memo<List<AlbumSummary>, FilterCounts>();

  /// Albums after search / filters / sort.
  List<AlbumSummary> visible(List<AlbumSummary> albums) => _visible((albums, query, filters, sort, yearFilter), () {
    final q = query.trim().toLowerCase();
    final list = albums.where((a) {
      if (!filters.matches(a)) return false;
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

  /// Album counts per filter option (for the filter panel).
  FilterCounts counts(List<AlbumSummary> albums) => _counts(albums, () => FilterCounts(albums));
}

final browser = LibraryBrowser();
