import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_browser.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/ui/album/album_page.dart';
import 'package:album_manager/ui/common/collapsing_app_bar.dart';
import 'package:album_manager/ui/common/scroll_label.dart';
import 'package:album_manager/ui/common/smooth_scroll.dart';
import 'package:album_manager/ui/library/album_card.dart';
import 'package:album_manager/util/format.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _search = TextEditingController(text: browser.query);
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _open(AlbumSummary a) => Navigator.of(context).push(AlbumPage.route(a));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([library, browser]),
      builder: (context, _) {
        final albums = browser.visible(library.albums);
        final counts = browser.counts(library.albums);
        final totalSize = albums.fold<int>(0, (n, a) => n + a.totalSize);
        final totalDur = albums.fold<double>(0, (n, a) => n + a.durationSecs);
        return Scaffold(
          body: ScrollLabel<AlbumSummary>(
            labelOf: _scrollLabel,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                collapsingAppBar(
                  title: Text(browser.yearFilter == null ? '专辑库' : '${browser.yearFilter} 年'),
                  actions: [
                    _SortMenu(),
                    const SizedBox(width: 8),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: true, icon: Icon(Icons.grid_view), tooltip: '网格'),
                        ButtonSegment(value: false, icon: Icon(Icons.view_list), tooltip: '列表'),
                      ],
                      selected: {browser.gridView},
                      onSelectionChanged: (s) => browser.setGridView(s.first),
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
                        SearchBar(
                          controller: _search,
                          hintText: '搜索标题、艺术家、文件夹',
                          leading: const Icon(Icons.search),
                          elevation: const WidgetStatePropertyAll(0),
                          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
                          onChanged: browser.setQuery,
                          trailing: [
                            if (browser.query.isNotEmpty)
                              IconButton(
                                tooltip: '清除',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _search.clear();
                                  browser.setQuery('');
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (browser.yearFilter != null)
                              InputChip(
                                avatar: const Icon(Icons.calendar_today_outlined),
                                label: Text('${browser.yearFilter} 年'),
                                onDeleted: () => browser.setYear(null),
                              ),
                            for (final f in SourceFilter.values)
                              ChoiceChip(label: Text('${f.label}  ${counts[f]}'), selected: browser.filter == f, onSelected: (_) => browser.setFilter(f)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${albums.length} 张专辑 · ${formatHours(totalDur)} · ${formatSize(totalSize)}',
                          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                if (albums.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _Empty(scanning: library.scanning))
                else if (browser.gridView)
                  ..._gridSlivers(context, albums)
                else
                  SliverList.builder(
                    itemCount: albums.length,
                    itemBuilder: (context, i) => _marked(albums[i], AlbumTile(album: albums[i], onTap: () => _open(albums[i]))),
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
  static Widget _marked(AlbumSummary a, Widget child) => MetaData(metaData: a, behavior: HitTestBehavior.translucent, child: child);

  /// Fast-scroll bubble text, matching the current sort order.
  static ScrollLabelText? _scrollLabel(AlbumSummary a) {
    ScrollLabelText month(int year, int? m) => (main: '$year', sub: m == null ? null : '$m 月');
    return switch (browser.sort) {
      SortMode.dateDesc ||
      SortMode.dateAsc => a.year == null ? (main: '未知', sub: '年份') : month(a.year!, (a.date?.length ?? 0) >= 7 ? int.tryParse(a.date!.substring(5, 7)) : null),
      SortMode.addedDesc => () {
        final d = DateTime.fromMillisecondsSinceEpoch(a.addedAt * 1000);
        return month(d.year, d.month);
      }(),
      SortMode.title => a.title.isEmpty ? null : (main: a.title.characters.first.toUpperCase(), sub: null),
      SortMode.artist => (main: a.artist ?? '未知艺术家', sub: null),
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
        itemBuilder: (context, i) => _marked(items[i], AlbumCard(album: items[i], onTap: () => _open(items[i]))),
      ),
    );
    if (!browser.sort.groupsByYear || browser.yearFilter != null) {
      return [const SliverToBoxAdapter(child: SizedBox(height: 8)), grid(albums)];
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
                  Text(e.key == 0 ? '未知年份' : '${e.key}', style: t.textTheme.headlineSmall),
                  const SizedBox(width: 12),
                  Text('${e.value.length} 张', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
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

class _SortMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, _) => TextButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.sort),
        label: Text(browser.sort.label),
      ),
      menuChildren: [
        for (final s in SortMode.values)
          MenuItemButton(leadingIcon: Icon(browser.sort == s ? Icons.check : null), onPressed: () => browser.setSort(s), child: Text(s.label)),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final bool scanning;
  const _Empty({required this.scanning});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(scanning ? Icons.radar : Icons.search_off, size: 48, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(scanning ? '正在扫描专辑库…' : '没有符合条件的专辑', style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
