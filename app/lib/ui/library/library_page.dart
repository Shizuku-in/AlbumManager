import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_browser.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/album/album_page.dart';
import 'package:album_manager/ui/common/collapsing_app_bar.dart';
import 'package:album_manager/ui/common/scroll_label.dart';
import 'package:album_manager/ui/common/shared_axis.dart';
import 'package:album_manager/ui/common/smooth_scroll.dart';
import 'package:album_manager/ui/library/album_card.dart';
import 'package:album_manager/ui/library/filter_panel.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/labels.dart';

/// Focus of the library search field, so Ctrl+F can reach it from anywhere.
final librarySearchFocus = FocusNode(debugLabel: 'librarySearch');

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  final _search = TextEditingController(text: browser.query);
  final _scroll = SmoothScrollController();

  /// Grid ↔ list: M3 fade through (the layouts have no spatial relationship).
  static const _gridIndex = 0, _listIndex = 1;
  late final _layoutSwitch = SharedAxisSwitch(
    vsync: this,
    initial: browser.gridView ? _gridIndex : _listIndex,
    distance: 0,
    onShownChanged: () => setState(() {}),
  );

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _layoutSwitch.dispose();
    super.dispose();
  }

  void _open(AlbumSummary a) => Navigator.of(context).push(AlbumPage.route(a));

  void _clearSearch() {
    _search.clear();
    browser.setQuery('');
  }

  void _clearAll() {
    _clearSearch();
    browser.clearFilters();
  }

  /// Removable chips for the active filters (M3 input chips), so what is
  /// narrowing the library stays visible without opening the panel.
  List<Widget> _filterChips() {
    final f = browser.filters;
    Widget chip(String label, FilterMode mode, AlbumFilters next) {
      final exclude = mode == FilterMode.exclude;
      return InputChip(
        avatar: exclude ? const Icon(Icons.block) : null,
        label: Text(exclude ? '排除 $label' : label),
        tooltip: '编辑筛选',
        onPressed: () => showFilterPanel(context),
        deleteButtonTooltipMessage: '移除此筛选',
        onDeleted: () => browser.setFilters(next),
      );
    }

    return [
      if (browser.yearFilter != null)
        InputChip(
          avatar: const Icon(Icons.event_outlined),
          label: Text('${browser.yearFilter} 年'),
          deleteButtonTooltipMessage: '移除此筛选',
          onDeleted: () => browser.setYear(null),
        ),
      for (final e in f.sources.modes.entries)
        chip(
          e.key.label,
          e.value,
          f.copyWith(sources: f.sources.without(e.key)),
        ),
      for (final e in f.qualities.modes.entries)
        chip(
          e.key.label,
          e.value,
          f.copyWith(qualities: f.qualities.without(e.key)),
        ),
      for (final e in f.formats.modes.entries)
        chip(e.key, e.value, f.copyWith(formats: f.formats.without(e.key))),
      for (final e in f.ripStatuses.modes.entries)
        chip(
          '抓轨${e.key.label}',
          e.value,
          f.copyWith(ripStatuses: f.ripStatuses.without(e.key)),
        ),
      for (final e in f.flags.modes.entries)
        chip(e.key.label, e.value, f.copyWith(flags: f.flags.without(e.key))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([library, browser, settings]),
      builder: (context, _) {
        final albums = browser.visible(library.albums);
        final filterCount = browser.activeFilterCount;
        final totalSize = albums.fold<int>(0, (n, a) => n + a.totalSize);
        final totalDur = albums.fold<double>(0, (n, a) => n + a.durationSecs);
        return Scaffold(
          floatingActionButton: _BackToTop(controller: _scroll),
          body: ScrollLabel<AlbumSummary>(
            labelOf: _scrollLabel,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                collapsingAppBar(
                  title: Text(
                    browser.yearFilter == null
                        ? '专辑库'
                        : '${browser.yearFilter} 年',
                  ),
                  actions: [
                    _SortMenu(),
                    const SizedBox(width: 8),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.grid_view),
                          tooltip: '网格',
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.view_list),
                          tooltip: '列表',
                        ),
                      ],
                      selected: {browser.gridView},
                      onSelectionChanged: (s) {
                        browser.setGridView(s.first);
                        _layoutSwitch.select(s.first ? _gridIndex : _listIndex);
                      },
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.escape):
                                _clearSearch,
                          },
                          child: SearchBar(
                            controller: _search,
                            focusNode: librarySearchFocus,
                            hintText: _searchHint(),
                            leading: const Icon(Icons.search),
                            elevation: const WidgetStatePropertyAll(0),
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.symmetric(horizontal: 16),
                            ),
                            onChanged: browser.setQuery,
                            trailing: [
                              if (browser.query.isNotEmpty)
                                IconButton(
                                  tooltip: '清除搜索',
                                  icon: const Icon(Icons.close),
                                  onPressed: _clearSearch,
                                ),
                              IconButton(
                                tooltip: '筛选',
                                isSelected: filterCount > 0,
                                onPressed: () => showFilterPanel(context),
                                icon: Badge.count(
                                  count: filterCount,
                                  isLabelVisible: filterCount > 0,
                                  child: const Icon(Icons.filter_list),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (filterCount > 0) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ..._filterChips(),
                              if (filterCount > 1)
                                TextButton(
                                  onPressed: browser.clearFilters,
                                  child: const Text('全部清除'),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          '${albums.length} 张专辑 · ${formatHours(totalDur)} · ${formatSize(totalSize)}',
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (albums.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(
                      scanning: library.scanning,
                      libraryEmpty: library.albums.isEmpty,
                      onClear: _clearAll,
                    ),
                  )
                else
                  AnimatedBuilder(
                    animation: _layoutSwitch.controller,
                    builder: (context, child) => SliverOpacity(
                      opacity: _layoutSwitch.opacity,
                      sliver: child!,
                    ),
                    child: SliverMainAxisGroup(
                      slivers: _layoutSwitch.shown == _gridIndex
                          ? _gridSlivers(context, albums)
                          : [
                              SliverList.builder(
                                itemCount: albums.length,
                                itemBuilder: (context, i) => _marked(
                                  albums[i],
                                  _item(
                                    albums[i],
                                    AlbumTile(
                                      album: albums[i],
                                      onTap: () => _open(albums[i]),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Tags an item so [ScrollLabel] can tell which album is at the top.
  static Widget _marked(AlbumSummary a, Widget child) => MetaData(
    metaData: a,
    behavior: HitTestBehavior.translucent,
    child: child,
  );

  Widget _item(AlbumSummary a, Widget child) =>
      AlbumContextMenu(album: a, onOpen: () => _open(a), child: child);

  /// Fast-scroll bubble text, matching the current sort order.
  static ScrollLabelText? _scrollLabel(AlbumSummary a) {
    ScrollLabelText month(int year, int? m) =>
        (main: '$year', sub: m == null ? null : '$m 月');
    return switch (browser.sort) {
      SortMode.dateDesc || SortMode.dateAsc =>
        a.year == null
            ? (main: '未知', sub: '年份')
            : month(
                a.year!,
                (a.date?.length ?? 0) >= 7
                    ? int.tryParse(a.date!.substring(5, 7))
                    : null,
              ),
      SortMode.addedDesc => () {
        final d = DateTime.fromMillisecondsSinceEpoch(a.addedAt * 1000);
        return month(d.year, d.month);
      }(),
      SortMode.title =>
        a.title.isEmpty
            ? null
            : (main: a.title.characters.first.toUpperCase(), sub: null),
      SortMode.artist => (main: a.artist ?? '未知艺术家', sub: null),
      SortMode.catalog => (main: catalogPrefix(a.catalog) ?? '无品番', sub: null),
      SortMode.size => (main: formatSize(a.totalSize), sub: null),
    };
  }

  List<Widget> _gridSlivers(BuildContext context, List<AlbumSummary> albums) {
    final gridDelegate = AlbumCard.gridDelegate(context);
    Widget grid(List<AlbumSummary> items) => SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid.builder(
        gridDelegate: gridDelegate,
        itemCount: items.length,
        itemBuilder: (context, i) => _marked(
          items[i],
          _item(
            items[i],
            AlbumCard(album: items[i], onTap: () => _open(items[i])),
          ),
        ),
      ),
    );
    if (!browser.sort.groupsByYear || browser.yearFilter != null) {
      return [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        grid(albums),
      ];
    }
    final groups = <int, List<AlbumSummary>>{};
    for (final a in albums) {
      groups.putIfAbsent(a.year ?? 0, () => []).add(a);
    }
    final t = Theme.of(context);
    return [
      for (final e in groups.entries) ...[
        SliverToBoxAdapter(
          child: _marked(
            e.value.first,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    e.key == 0 ? '未知年份' : '${e.key}',
                    style: t.textTheme.headlineSmall,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${e.value.length} 张',
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        grid(e.value),
      ],
    ];
  }
}

/// "搜索标题、艺术家、文件夹名等" from the fields the search looks in.
String _searchHint() {
  final fields = SearchField.values.where(settings.searches).toList();
  if (fields.isEmpty) return '未选择搜索范围（设置 → 专辑浏览）';
  final shown = fields.take(3).map((f) => f.label).join('、');
  return '搜索$shown${fields.length > 3 ? '等' : ''}（Ctrl+F）';
}

class _SortMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, _) => TextButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.sort),
        label: Text(browser.sort.label),
      ),
      menuChildren: [
        for (final s in SortMode.values)
          MenuItemButton(
            leadingIcon: Icon(browser.sort == s ? Icons.check : null),
            onPressed: () => browser.setSort(s),
            child: Text(s.label),
          ),
      ],
    );
  }
}

/// Empty state that says why nothing is shown and offers the way out.
class _Empty extends StatelessWidget {
  final bool scanning;

  /// No albums at all (as opposed to none matching the search / filters).
  final bool libraryEmpty;
  final VoidCallback onClear;
  const _Empty({
    required this.scanning,
    required this.libraryEmpty,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (icon, title, body, action) = scanning
        ? (Icons.search, '正在扫描专辑库…', '找到的专辑会显示在这里', null)
        : libraryEmpty
        ? (
            Icons.library_music_outlined,
            '专辑库中还没有专辑',
            '确认专辑库位置是否正确，然后重新扫描',
            FilledButton.tonalIcon(
              onPressed: () => library.rescan(),
              icon: const Icon(Icons.sync),
              label: const Text('重新扫描'),
            ),
          )
        : (
            Icons.search_off,
            '没有符合条件的专辑',
            '试试其它关键词，或放宽筛选条件',
            FilledButton.tonalIcon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_list_off),
              label: const Text('清除搜索和筛选'),
            ),
          );
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(title, style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            body,
            style: t.textTheme.bodyMedium?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 24), action],
        ],
      ),
    );
  }
}

/// M3 FAB that scrolls the library back to the top; shown once the first
/// screenful has scrolled away. Slides and fades rather than scaling, which
/// would blur the icon.
class _BackToTop extends StatelessWidget {
  final ScrollController controller;
  const _BackToTop({required this.controller});

  void _toTop() {
    final p = controller.position;
    // From far down, skip most of the way first: animating through thousands
    // of covers would decode them all on the way.
    final near = p.viewportDimension * 2;
    if (p.pixels > near) controller.jumpTo(near);
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        // Before the first layout the position has no viewport size yet.
        final p = controller.hasClients ? controller.position : null;
        final shown =
            p != null &&
            p.hasPixels &&
            p.hasViewportDimension &&
            p.pixels > p.viewportDimension;
        return IgnorePointer(
          ignoring: !shown,
          child: AnimatedSlide(
            offset: shown ? Offset.zero : const Offset(0, 0.5),
            duration: const Duration(milliseconds: 200),
            curve: shown
                ? Easing.emphasizedDecelerate
                : Easing.emphasizedAccelerate,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: child,
            ),
          ),
        );
      },
      child: FloatingActionButton(
        heroTag: null,
        shape: const CircleBorder(),
        tooltip: '返回顶部',
        onPressed: _toTop,
        child: const Icon(Icons.arrow_upward),
      ),
    );
  }
}
