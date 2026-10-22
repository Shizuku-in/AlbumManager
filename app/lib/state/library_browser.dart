import 'package:flutter/foundation.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/favorites.dart';
import 'package:album_manager/state/navigation.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/util/memo.dart';

enum SortMode { dateDesc, dateAsc, addedDesc, title, artist, catalog, size }

extension SortModeX on SortMode {
  String get label => switch (this) {
    SortMode.dateDesc => '发行日期（新→旧）',
    SortMode.dateAsc => '发行日期（旧→新）',
    SortMode.addedDesc => '最近添加',
    SortMode.title => '标题',
    SortMode.artist => '艺术家',
    SortMode.catalog => '品番',
    SortMode.size => '占用空间',
  };
  bool get groupsByYear =>
      this == SortMode.dateDesc || this == SortMode.dateAsc;
}

/// Yes/no properties of an album.
enum ContentFlag {
  favorite,
  hasIssues,
  missingCover,
  hasScans,
  hasCue,
  multiDisc,
  edited,
}

extension ContentFlagX on ContentFlag {
  String get label => switch (this) {
    ContentFlag.favorite => '已收藏',
    ContentFlag.hasIssues => '有问题',
    ContentFlag.missingCover => '缺少封面',
    ContentFlag.hasScans => '有扫图',
    ContentFlag.hasCue => '有 CUE',
    ContentFlag.multiDisc => '多碟',
    ContentFlag.edited => '手动编辑过',
  };
  bool matches(AlbumSummary a) => switch (this) {
    ContentFlag.favorite => favorites.contains(a),
    ContentFlag.hasIssues => settings.issuesOf(a).isNotEmpty,
    ContentFlag.missingCover => a.coverThumb == null,
    ContentFlag.hasScans => a.hasScans,
    ContentFlag.hasCue => a.hasCue,
    ContentFlag.multiDisc => a.discCount > 1,
    ContentFlag.edited =>
      a.overrides.source != null ||
          a.overrides.coverPath != null ||
          a.overrides.hasScans != null,
  };
}

/// Rip statuses offered as filters (CD rips only).
const ripStatusFilters = [
  RipStatus.perfect,
  RipStatus.good,
  RipStatus.warning,
  RipStatus.error,
  RipStatus.noLog,
  RipStatus.unknown,
];

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

  /// Without any constraint on [option].
  TriFilter<T> without(T option) => TriFilter({...modes}..remove(option));

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

  /// `mode|value` strings for persistence.
  Iterable<String> encode(String Function(T) nameOf) =>
      modes.entries.map((e) => '${e.value.name}|${nameOf(e.key)}');

  /// Inverse of [encode]; unknown entries are dropped.
  static TriFilter<T> decode<T>(
    Iterable<String> items,
    T? Function(String) parse,
  ) {
    final m = <T, FilterMode>{};
    for (final s in items) {
      final i = s.indexOf('|');
      if (i < 0) continue;
      final mode = FilterMode.values
          .where((f) => f.name == s.substring(0, i))
          .firstOrNull;
      final value = parse(s.substring(i + 1));
      if (mode != null && value != null) m[value] = mode;
    }
    return TriFilter(m);
  }
}

T? _byName<T extends Enum>(List<T> values, String name) =>
    values.where((v) => v.name == name).firstOrNull;

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

  /// `group|mode|value` strings for persistence.
  List<String> encode() => [
    for (final s in sources.encode((v) => v.name)) 'source|$s',
    for (final s in qualities.encode((v) => v.name)) 'quality|$s',
    for (final s in formats.encode((v) => v)) 'format|$s',
    for (final s in ripStatuses.encode((v) => v.name)) 'rip|$s',
    for (final s in flags.encode((v) => v.name)) 'flag|$s',
  ];

  factory AlbumFilters.decode(List<String> items) {
    Iterable<String> group(String g) => items
        .where((s) => s.startsWith('$g|'))
        .map((s) => s.substring(g.length + 1));
    return AlbumFilters(
      sources: TriFilter.decode(
        group('source'),
        (n) => _byName(AlbumSource.values, n),
      ),
      qualities: TriFilter.decode(
        group('quality'),
        (n) => _byName(AudioQuality.values, n),
      ),
      formats: TriFilter.decode(group('format'), (n) => n),
      ripStatuses: TriFilter.decode(
        group('rip'),
        (n) => _byName(RipStatus.values, n),
      ),
      flags: TriFilter.decode(
        group('flag'),
        (n) => _byName(ContentFlag.values, n),
      ),
    );
  }

  int get count =>
      sources.length +
      qualities.length +
      formats.length +
      ripStatuses.length +
      flags.length;

  bool matches(AlbumSummary a) =>
      sources.matchesAny([a.source]) &&
      qualities.matchesAny([a.quality]) &&
      formats.matchesAny(a.formats) &&
      ripStatuses.matchesAny([a.ripStatus]) &&
      flags.modes.entries.every(
        (e) => e.key.matches(a) == (e.value == FilterMode.include),
      );

  AlbumFilters copyWith({
    TriFilter<AlbumSource>? sources,
    TriFilter<AudioQuality>? qualities,
    TriFilter<String>? formats,
    TriFilter<RipStatus>? ripStatuses,
    TriFilter<ContentFlag>? flags,
  }) => AlbumFilters(
    sources: sources ?? this.sources,
    qualities: qualities ?? this.qualities,
    formats: formats ?? this.formats,
    ripStatuses: ripStatuses ?? this.ripStatuses,
    flags: flags ?? this.flags,
  );

  AlbumFilters cycleSource(AlbumSource v) => AlbumFilters(
    sources: sources.cycle(v),
    qualities: qualities,
    formats: formats,
    ripStatuses: ripStatuses,
    flags: flags,
  );
  AlbumFilters cycleQuality(AudioQuality v) => AlbumFilters(
    sources: sources,
    qualities: qualities.cycle(v),
    formats: formats,
    ripStatuses: ripStatuses,
    flags: flags,
  );
  AlbumFilters cycleFormat(String v) => AlbumFilters(
    sources: sources,
    qualities: qualities,
    formats: formats.cycle(v),
    ripStatuses: ripStatuses,
    flags: flags,
  );
  AlbumFilters cycleRipStatus(RipStatus v) => AlbumFilters(
    sources: sources,
    qualities: qualities,
    formats: formats,
    ripStatuses: ripStatuses.cycle(v),
    flags: flags,
  );
  AlbumFilters cycleFlag(ContentFlag v) => AlbumFilters(
    sources: sources,
    qualities: qualities,
    formats: formats,
    ripStatuses: ripStatuses,
    flags: flags.cycle(v),
  );
}

/// Album counts per filter option, over the whole library.
class FilterCounts {
  final Map<AlbumSource, int> sources = {};
  final Map<AudioQuality, int> qualities = {};

  /// Most common first.
  final Map<String, int> formats;
  final Map<RipStatus, int> ripStatuses = {};
  final Map<ContentFlag, int> flags;

  FilterCounts(List<AlbumSummary> albums)
    : formats = {},
      flags = {
        for (final f in ContentFlag.values) f: albums.where(f.matches).length,
      } {
    final fmt = <String, int>{};
    for (final a in albums) {
      sources.update(a.source, (n) => n + 1, ifAbsent: () => 1);
      qualities.update(a.quality, (n) => n + 1, ifAbsent: () => 1);
      ripStatuses.update(a.ripStatus, (n) => n + 1, ifAbsent: () => 1);
      for (final f in a.formats) {
        fmt.update(f, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    formats.addEntries(
      fmt.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
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

  void load() {
    final prefs = settings.prefs;
    gridView = prefs.getBool('gridView') ?? true;
    sort =
        _byName(SortMode.values, prefs.getString('sort') ?? '') ??
        SortMode.dateDesc;
    if (settings.rememberFilters) {
      filters = AlbumFilters.decode(prefs.getStringList('filters') ?? const []);
    }
    // The "favorite" filter follows starring / unstarring.
    favorites.addListener(notifyListeners);
    var hidden = settings.hiddenIssues;
    var unsearched = settings.hiddenSearchFields;
    var remember = settings.rememberFilters;
    settings.addListener(() {
      if (remember != settings.rememberFilters) {
        remember = settings.rememberFilters;
        _saveFilters();
      }
      // The "has issues" filter depends on which checks are enabled, the
      // search on which fields it looks in.
      if (identical(hidden, settings.hiddenIssues) &&
          identical(unsearched, settings.hiddenSearchFields)) {
        return;
      }
      hidden = settings.hiddenIssues;
      unsearched = settings.hiddenSearchFields;
      notifyListeners();
    });
  }

  void _saveFilters() {
    if (settings.rememberFilters) {
      settings.prefs.setStringList('filters', filters.encode());
    } else {
      settings.prefs.remove('filters');
    }
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setFilters(AlbumFilters f) {
    filters = f;
    _saveFilters();
    notifyListeners();
  }

  /// Number of active filters, including the year.
  int get activeFilterCount => filters.count + (yearFilter == null ? 0 : 1);

  void clearFilters() {
    filters = const AlbumFilters();
    yearFilter = null;
    _saveFilters();
    notifyListeners();
  }

  void setSort(SortMode s) {
    sort = s;
    settings.prefs.setString('sort', s.name);
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

  final _visible =
      Memo<
        (
          List<AlbumSummary>,
          String,
          AlbumFilters,
          SortMode,
          int?,
          Set<IssueKind>,
          Set<String>,
          Set<SearchField>,
        ),
        List<AlbumSummary>
      >();
  final _counts =
      Memo<(List<AlbumSummary>, Set<IssueKind>, Set<String>), FilterCounts>();

  /// Albums after search / filters / sort.
  List<AlbumSummary> visible(List<AlbumSummary> albums) => _visible(
    (
      albums,
      query,
      filters,
      sort,
      yearFilter,
      settings.hiddenIssues,
      favorites.ids,
      settings.hiddenSearchFields,
    ),
    () {
      final q = query.trim().toLowerCase();
      bool has(SearchField f, String? v) =>
          settings.searches(f) && (v?.toLowerCase().contains(q) ?? false);
      // Tracks aren't in the summaries: the Rust side searches them.
      final trackHits = q.isEmpty
          ? const <String>{}
          : api
                .searchTracks(
                  query: q,
                  titles: settings.searches(SearchField.trackTitle),
                  artists: settings.searches(SearchField.trackArtist),
                )
                .toSet();
      final list = albums.where((a) {
        if (!filters.matches(a)) return false;
        if (yearFilter != null && a.year != yearFilter) return false;
        if (q.isEmpty) return true;
        return has(SearchField.title, a.title) ||
            has(SearchField.artist, a.artist) ||
            has(SearchField.folderName, a.folderName) ||
            has(SearchField.genre, a.genre) ||
            has(SearchField.catalog, a.catalog) ||
            has(SearchField.event, a.event) ||
            trackHits.contains(a.id);
      }).toList();
      int byDate(AlbumSummary a, AlbumSummary b) =>
          (a.date ?? '${a.year ?? 0}').compareTo(b.date ?? '${b.year ?? 0}');
      switch (sort) {
        case SortMode.dateDesc:
          list.sort((a, b) => byDate(b, a));
        case SortMode.dateAsc:
          list.sort(byDate);
        case SortMode.addedDesc:
          list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        case SortMode.title:
          list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
        case SortMode.artist:
          list.sort((a, b) => (a.artist ?? '￿').compareTo(b.artist ?? '￿'));
        case SortMode.catalog:
          list.sort(_byCatalog);
        case SortMode.size:
          list.sort((a, b) => b.totalSize.compareTo(a.totalSize));
      }
      return list;
    },
  );

  /// Album counts per filter option (for the filter panel).
  FilterCounts counts(List<AlbumSummary> albums) => _counts((
    albums,
    settings.hiddenIssues,
    favorites.ids,
  ), () => FilterCounts(albums));
}

final browser = LibraryBrowser();

final _catalogParts = RegExp(r'^([A-Za-z]+)-?(\d+)');

/// The label part of a catalog number ("LACA" of "LACA-15800").
String? catalogPrefix(String? catalog) {
  if (catalog == null) return null;
  return (_catalogParts.firstMatch(catalog)?[1] ?? catalog).toUpperCase();
}

/// By label, then numerically (LACA-9999 before LACA-10000); albums
/// without a catalog number last.
int _byCatalog(AlbumSummary a, AlbumSummary b) {
  final x = a.catalog?.toUpperCase(), y = b.catalog?.toUpperCase();
  if (x == null || y == null) return x == y ? 0 : (x == null ? 1 : -1);
  final mx = _catalogParts.firstMatch(x), my = _catalogParts.firstMatch(y);
  if (mx != null && my != null) {
    final c = mx[1]!.compareTo(my[1]!);
    if (c != 0) return c;
    final n = int.parse(mx[2]!).compareTo(int.parse(my[2]!));
    if (n != 0) return n;
  }
  return x.compareTo(y);
}
