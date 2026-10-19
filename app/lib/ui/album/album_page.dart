import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/favorites.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/theme/app_theme.dart';
import 'package:album_manager/ui/album/cue_fix_dialog.dart';
import 'package:album_manager/ui/album/edit_album_dialog.dart';
import 'package:album_manager/ui/album/tabs/files_tab.dart';
import 'package:album_manager/ui/album/tabs/logs_tab.dart';
import 'package:album_manager/ui/album/tabs/scans_tab.dart';
import 'package:album_manager/ui/album/tabs/tracks_tab.dart';
import 'package:album_manager/ui/common/collapsing_app_bar.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/ui/common/shared_axis.dart';
import 'package:album_manager/ui/common/sliver_translate.dart';
import 'package:album_manager/ui/common/smooth_scroll.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/labels.dart';
import 'package:album_manager/util/system.dart';

class AlbumPage extends StatefulWidget {
  final AlbumSummary summary;
  const AlbumPage({super.key, required this.summary});

  static Route<void> route(AlbumSummary s) =>
      MaterialPageRoute(builder: (_) => AlbumPage(summary: s));

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> with TickerProviderStateMixin {
  late AlbumSummary _s = widget.summary;
  Album? _album;
  // The controller also notifies when its indicator animation ends; select()
  // ignores repeats.
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(() {
      setState(() {}); // Tab labels / indicator.
      _tabSwitch.select(_tabs.index);
    });
  late final _tabSwitch = SharedAxisSwitch(
    vsync: this,
    onShownChanged: () => setState(() {}),
  );
  bool _busy = false;
  final _scroll = SmoothScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    library.albumChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    library.albumChanged.removeListener(_onChanged);
    _tabs.dispose();
    _tabSwitch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    final changed = library.albumChanged.value;
    if (changed == _s.id || changed == LibraryController.allAlbums) _load();
  }

  Future<void> _load() async {
    final a = await api.getAlbum(id: _s.id);
    if (!mounted || a == null) return;
    setState(() {
      _album = a;
      _s = a.summary;
    });
  }

  Future<void> _run(
    BuildContext context,
    Future<Album> Function() action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final a = await action();
      library.replaceAlbum(a.summary);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('操作失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(BuildContext context, Album album) async {
    final o = await showEditAlbumDialog(context, album);
    if (o == null || !context.mounted) return;
    await _run(
      context,
      () => api.setAlbumOverride(id: _s.id, overrides: o),
      '已保存',
    );
  }

  Future<void> _fixCue(BuildContext context) async {
    final bad = _album?.cues.where((c) => !c.isUtf8).length ?? 0;
    if (await confirmCueFix(context, bad) && context.mounted) {
      await _run(
        context,
        () => library.fixCue(_s.id),
        '已将 $bad 个 CUE 转换为 UTF-8',
      );
    }
  }

  void _play() {
    final a = _album;
    if (a == null) return;
    final cue = a.discs.map((d) => d.cuePath).whereType<String>().firstOrNull;
    final first = a.discs
        .expand((d) => d.tracks)
        .map((t) => t.file)
        .firstOrNull;
    final target = cue ?? first;
    if (target != null) openPath(target);
  }

  @override
  Widget build(BuildContext context) {
    // M3 content-based color: the page scheme is generated from the cover.
    return Theme(
      data: contentTheme(context, accentOf(_s)),
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final a = _album;
    final hasBadCue = a?.cues.any((c) => !c.isUtf8) ?? false;
    final issues = settings
        .issuesOf(_s)
        .where((i) => i.kind != IssueKind.nonStandardName)
        .toList();
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            // Background drawn by flexibleSpace so the scrolled-under change fades.
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            flexibleSpace: const ScrolledUnderBackground(),
            // The header shows the title in large type; the bar repeats it only
            // once that has scrolled away.
            title: ListenableBuilder(
              listenable: _scroll,
              builder: (context, child) => AnimatedOpacity(
                opacity: _scroll.hasClients && _scroll.offset > 72 ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: child,
              ),
              child: Text(
                _s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            actions: [
              ListenableBuilder(
                listenable: favorites,
                builder: (context, _) {
                  final starred = favorites.contains(_s);
                  return IconButton(
                    tooltip: starred ? '取消收藏' : '收藏',
                    isSelected: starred,
                    onPressed: () => favorites.toggle(_s),
                    icon: const Icon(Icons.favorite_border),
                    selectedIcon: const Icon(Icons.favorite),
                  );
                },
              ),
              IconButton(
                tooltip: '重新扫描此专辑',
                onPressed: _busy
                    ? null
                    : () => _run(
                        context,
                        () => api.rescanAlbum(id: _s.id),
                        '已重新扫描',
                      ),
                icon: const Icon(Icons.refresh),
              ),
              MenuAnchor(
                builder: (context, c, _) => IconButton(
                  tooltip: '更多',
                  onPressed: () => c.isOpen ? c.close() : c.open(),
                  icon: const Icon(Icons.more_vert),
                ),
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.edit_outlined),
                    onPressed: a != null && !_busy
                        ? () => _edit(context, a)
                        : null,
                    child: const Text('编辑专辑'),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.translate),
                    onPressed: hasBadCue && !_busy
                        ? () => _fixCue(context)
                        : null,
                    child: const Text('修复 CUE 编码'),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.open_in_new),
                    onPressed: () => revealInFileManager(_s.path),
                    child: const Text('在文件管理器中定位'),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(child: _header(context, hasBadCue)),
          if (issues.isNotEmpty)
            SliverToBoxAdapter(child: _issues(context, issues)),
          // M3 secondary tabs (they divide this page's content), pinned under
          // the app bar so switching tabs never needs scrolling back up.
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabHeader(
              TabBar.secondary(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tabs: [
                  Tab(
                    text:
                        '曲目${a == null ? '' : ' (${a.discs.fold<int>(0, (n, d) => n + d.tracks.length)})'}',
                  ),
                  Tab(text: '抓轨日志${a == null ? '' : ' (${a.logs.length})'}'),
                  Tab(text: '扫图${a == null ? '' : ' (${a.images.length})'}'),
                  Tab(text: '文件${a == null ? '' : ' (${a.files.length})'}'),
                ],
              ),
            ),
          ),
          if (a == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            AnimatedBuilder(
              animation: _tabSwitch.controller,
              builder: (context, child) => SliverOpacity(
                opacity: _tabSwitch.opacity,
                sliver: SliverTranslateX(dx: _tabSwitch.shift, sliver: child!),
              ),
              child: SliverMainAxisGroup(
                slivers: switch (_tabSwitch.shown) {
                  0 => tracksSlivers(context, a),
                  1 => logsSlivers(context, a),
                  2 => scansSlivers(context, a),
                  _ => filesSlivers(context, a),
                },
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool hasBadCue) {
    final t = Theme.of(context);
    final s = _s;
    final chips = <Widget>[
      if (s.qualityLabel.isNotEmpty)
        Chip(avatar: const Icon(Icons.graphic_eq), label: Text(s.qualityLabel)),
      if (s.source == AlbumSource.cdRip)
        Chip(
          avatar: Icon(
            s.ripStatus.icon,
            color: s.ripStatus.tone(context).color,
          ),
          label: Text('抓轨${s.ripStatus.label}'),
        ),
      if (s.discCount > 1)
        Chip(
          avatar: const Icon(Icons.album_outlined),
          label: Text('${s.discCount} 碟'),
        ),
      Chip(
        avatar: const Icon(Icons.queue_music),
        label: Text('${s.trackCount} 首'),
      ),
      if (s.durationSecs > 0)
        Chip(
          avatar: const Icon(Icons.schedule),
          label: Text(formatDuration(s.durationSecs, long: true)),
        ),
      Chip(
        avatar: const Icon(Icons.storage),
        label: Text(formatSize(s.totalSize)),
      ),
      if (s.imageCount > 0)
        Chip(
          avatar: const Icon(Icons.photo_library_outlined),
          label: Text(
            s.hasScans ? '含扫图 · ${s.imageCount} 张图片' : '${s.imageCount} 张图片',
          ),
        ),
      if (s.genre != null)
        Chip(avatar: const Icon(Icons.sell_outlined), label: Text(s.genre!)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: Material(
              elevation: 1,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: CoverImage(path: s.coverThumb, radius: 16),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    s.source.label,
                    settings.formatDate(s.date),
                  ].whereType<String>().join(' · '),
                  style: t.textTheme.labelLarge?.copyWith(
                    color: t.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(s.title, style: t.textTheme.headlineMedium),
                if (s.artist != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    s.artist!,
                    style: t.textTheme.titleMedium?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: chips),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _album == null ? null : _play,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('播放'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => openPath(s.path),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('打开文件夹'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _album != null && !_busy
                          ? () => _edit(context, _album!)
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑'),
                    ),
                    if (hasBadCue)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _fixCue(context),
                        icon: const Icon(Icons.translate),
                        label: const Text('修复 CUE 编码'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [path] relative to the album folder (e.g. a disc's log), so issues of
  /// the same kind tell apart which file they are about.
  String _inAlbum(String path) => path.startsWith(_s.path)
      ? path.substring(_s.path.length).replaceFirst(RegExp(r'^[\\/]'), '')
      : path;

  Widget _issues(BuildContext context, List<Issue> issues) {
    final fileStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            for (final i in issues)
              ListTile(
                dense: true,
                leading: Icon(i.kind.icon, color: i.kind.tone(context).color),
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: i.kind.label),
                      if (i.path != null)
                        TextSpan(
                          text: '  ${_inAlbum(i.path!)}',
                          style: fileStyle,
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  i.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: i.path == null
                    ? null
                    : IconButton(
                        tooltip: '定位文件',
                        icon: const Icon(Icons.folder_open_outlined),
                        onPressed: () => revealInFileManager(i.path!),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pinned tab bar whose background joins the app bar's scrolled-under color
/// once content scrolls beneath it.
class _TabHeader extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabHeader(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ScrolledUnderBackground(scrolledUnder: overlapsContent, child: tabBar);

  // The tab labels carry counts that change once the album loads.
  @override
  bool shouldRebuild(_TabHeader oldDelegate) => true;
}
