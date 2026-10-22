import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_browser.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/ui/common/section_header.dart';
import 'package:album_manager/util/format.dart';

typedef _Years = List<MapEntry<int, List<AlbumSummary>>>;

/// Years grouped by decade (null = unknown year), keeping their order.
List<(int?, _Years)> _byDecade(_Years years) {
  final groups = <(int?, _Years)>[];
  for (final y in years) {
    final decade = y.key == 0 ? null : y.key ~/ 10 * 10;
    if (groups.isEmpty || groups.last.$1 != decade) groups.add((decade, []));
    groups.last.$2.add(y);
  }
  return groups;
}

/// Albums with a cover, newest first, at most [max].
List<AlbumSummary> _wallOf(Iterable<AlbumSummary> albums, int max) =>
    (albums.where((a) => a.coverThumb != null).toList()
          ..sort((a, b) => (b.date ?? '').compareTo(a.date ?? '')))
        .take(max)
        .toList();

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, settings]),
      builder: (context, _) {
        final years = library.byYear.entries.toList();
        final groups = settings.timelineDecades
            ? _byDecade(years)
            : [(null, years)];
        return AppPage(
          title: '时间线',
          slivers: [
            for (final (i, (decade, years)) in groups.indexed) ...[
              if (settings.timelineDecades)
                SliverToBoxAdapter(
                  child: decade == null
                      ? const SectionHeader('年份未知')
                      : Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            i == 0 ? 0 : 24,
                            16,
                            16,
                          ),
                          child: _DecadeBanner(decade: decade, years: years),
                        ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: years.length,
                  itemBuilder: (context, i) => _YearCard(
                    key: ValueKey(years[i].key),
                    year: years[i].key,
                    albums: years[i].value,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Tracks the pointer over its child as a fraction of its size (null while
/// outside), without rebuilding on every move.
class _Hover extends StatefulWidget {
  final Widget Function(BuildContext context, ValueListenable<Offset?> pointer)
  builder;
  const _Hover({required this.builder});

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  final _pointer = ValueNotifier<Offset?>(null);

  void _move(PointerEvent e) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    _pointer.value = Offset(
      e.localPosition.dx / size.width,
      e.localPosition.dy / size.height,
    );
  }

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _move,
      onHover: _move,
      onExit: (_) => _pointer.value = null,
      child: widget.builder(context, _pointer),
    );
  }
}

/// Text over a cover wall, on a dark scrim.
const _onWall = Color(0xFFFFFFFF);
const _onWallMuted = Color(0xB3FFFFFF);

/// A wide cover wall opening a decade.
class _DecadeBanner extends StatelessWidget {
  final int decade;
  final _Years years;
  const _DecadeBanner({required this.decade, required this.years});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final albums = [for (final y in years) ...y.value];
    final dur = albums.fold<double>(0, (n, a) => n + a.durationSecs);
    final tilted = settings.wallStyle == WallStyle.tilted;
    return SizedBox(
      height: 168,
      child: Card.filled(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: _Hover(
          builder: (context, pointer) => Stack(
            fit: StackFit.expand,
            children: [
              _wall(
                context,
                albums: _wallOf(albums, 60),
                phase: (decade * 0.618) % 1,
                rows: tilted ? 3 : 1,
                pointer: pointer,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    stops: [0, 0.65],
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$decade 年代',
                      style: t.textTheme.displaySmall?.copyWith(
                        color: _onWall,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${albums.length} 张专辑 · ${years.length} 个年份 · '
                      '${formatHours(dur)}',
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: _onWallMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cover wall of a card per the timeline settings (a plain surface when
/// no album has a cover).
Widget _wall(
  BuildContext context, {
  required List<AlbumSummary> albums,
  required double phase,
  required int rows,
  required ValueListenable<Offset?> pointer,
}) {
  if (albums.isEmpty) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
  // Decorative: kept out of semantics, which would otherwise update every
  // frame.
  return ExcludeSemantics(
    child: RepaintBoundary(
      child: _CoverWall(
        albums: albums,
        phase: phase,
        rows: rows,
        tilted: settings.wallStyle == WallStyle.tilted,
        motion: settings.wallMotion,
        zoom: settings.wallZoom,
        seamless: settings.wallGap == WallGap.seamless,
        pointer: pointer,
      ),
    ),
  );
}

class _YearCard extends StatelessWidget {
  final int year;
  final List<AlbumSummary> albums;
  const _YearCard({super.key, required this.year, required this.albums});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dur = albums.fold<double>(0, (n, a) => n + a.durationSecs);
    final cd = albums.where((a) => a.source == AlbumSource.cdRip).length;
    final title = year == 0 ? '未知' : '$year';
    final stats = '$cd 张抓轨 · ${formatHours(dur)}';
    final poster = settings.timelineCard == TimelineCard.poster;
    void open() => browser.showYear(year == 0 ? null : year);
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: _Hover(
        builder: (context, pointer) {
          final wall = _wall(
            context,
            albums: _wallOf(albums, 40),
            phase: (year * 0.618) % 1,
            rows: 3,
            pointer: pointer,
          );
          if (!poster) {
            return InkWell(
              onTap: open,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: wall),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(title, style: t.textTheme.headlineMedium),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${albums.length} 张专辑',
                              style: t.textTheme.titleSmall,
                            ),
                            Text(
                              stats,
                              style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurfaceVariant,
                              ),
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
          // Poster: the wall fills the card, the year sits on a scrim.
          return Stack(
            fit: StackFit.expand,
            children: [
              wall,
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.4, 1],
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 16,
                bottom: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      style: t.textTheme.displaySmall?.copyWith(
                        color: _onWall,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${albums.length} 张专辑',
                          style: t.textTheme.titleSmall?.copyWith(
                            color: _onWall,
                          ),
                        ),
                        Text(
                          stats,
                          style: t.textTheme.bodySmall?.copyWith(
                            color: _onWallMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: open),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Rows of covers (on a tilted wall or flat), each row looping sideways
/// (every other row the opposite way). [motion] says when it drifts or
/// follows the pointer; speed, parallax and the hover zoom all ease in and
/// out rather than jump.
class _CoverWall extends StatefulWidget {
  final List<AlbumSummary> albums;

  /// Start of the loop, so neighbouring walls don't move in lockstep.
  final double phase;
  final int rows;
  final bool tilted;
  final WallMotion motion;
  final bool zoom;

  /// Covers edge to edge, without gaps or rounded corners.
  final bool seamless;
  final ValueListenable<Offset?> pointer;
  const _CoverWall({
    required this.albums,
    required this.phase,
    required this.rows,
    required this.tilted,
    required this.motion,
    required this.zoom,
    required this.seamless,
    required this.pointer,
  });

  @override
  State<_CoverWall> createState() => _CoverWallState();
}

class _CoverWallState extends State<_CoverWall>
    with SingleTickerProviderStateMixin {
  static const _angle = -0.21; // about 12°
  static const _period = 45.0; // seconds per loop at full speed

  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier(0);
  Duration _last = Duration.zero;
  bool _reduceMotion = false;

  double get _gap => widget.seamless ? 0 : 6;

  double _pos = 0; // loop progress, 0..1
  double _speed = 0; // 0..1
  double _follow = 0; // pointer parallax, -1..1
  double _lift = 0; // hover zoom, 0..1

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    final p = widget.pointer.value;
    final m = widget.motion;
    final speed = m == WallMotion.always || (m == WallMotion.hover && p != null)
        ? 1.0
        : 0.0;
    final follow = m == WallMotion.follow && p != null ? p.dx * 2 - 1 : 0.0;
    final lift = widget.zoom && p != null ? 1.0 : 0.0;
    // Exponential approach; snaps once close so the ticker can stop.
    double ease(double v, double to, double tau) {
      final next = to + (v - to) * math.exp(-dt / tau);
      return (next - to).abs() < 1e-3 ? to : next;
    }

    _speed = ease(_speed, speed, 0.35);
    _follow = ease(_follow, follow, 0.25);
    _lift = ease(_lift, lift, 0.18);
    _pos = (_pos + _speed * dt / _period) % 1;
    _frame.value++;
    if (_speed == 0 && _follow == follow && _lift == lift) _ticker.stop();
  }

  void _wake() {
    if (_reduceMotion || _ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  @override
  void initState() {
    super.initState();
    widget.pointer.addListener(_wake);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _ticker.stop();
      _speed = _follow = _lift = 0;
    } else {
      _wake();
    }
  }

  @override
  void didUpdateWidget(_CoverWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pointer != widget.pointer) {
      oldWidget.pointer.removeListener(_wake);
      widget.pointer.addListener(_wake);
    }
    _wake();
  }

  @override
  void dispose() {
    widget.pointer.removeListener(_wake);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final tilted = widget.tilted;
        final rows = widget.rows;
        // The tilted wall is the box's bounding rectangle at full tilt, so it
        // covers the box at that angle and any straighter one.
        final cos = math.cos(_angle), sin = math.sin(_angle).abs();
        final width = tilted
            ? c.maxWidth * cos + c.maxHeight * sin
            : c.maxWidth;
        final height = tilted
            ? c.maxWidth * sin + c.maxHeight * cos
            : c.maxHeight;
        final tile = (height - (rows - 1) * _gap) / rows;
        final stride = tile + _gap;
        // Tiles in one period of a row: enough to span the wall plus the
        // tile scrolling in.
        final perLoop = (width / stride).ceil() + 1;
        final decodeWidth = math.min(
          480,
          (tile * 1.1 * MediaQuery.devicePixelRatioOf(context)).ceil(),
        );
        final wall = Column(
          spacing: _gap,
          children: [
            for (var r = 0; r < rows; r++)
              _row(r, tile, stride, perLoop, decodeWidth),
          ],
        );
        return ClipRect(
          child: OverflowBox(
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: AnimatedBuilder(
              animation: _frame,
              child: wall,
              builder: (context, child) => Transform.scale(
                scale: 1 + 0.06 * _lift,
                child: tilted
                    ? Transform.rotate(
                        angle: _angle * (1 - 0.3 * _lift),
                        child: child,
                      )
                    : child,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Two periods of covers side by side; sliding by one period lands on the
  /// same picture, so the loop is seamless.
  Widget _row(int r, double tile, double stride, int perLoop, int decodeWidth) {
    final albums = widget.albums;
    final loop = perLoop * stride;
    final strip = OverflowBox(
      alignment: Alignment.centerLeft,
      minWidth: 0,
      maxWidth: double.infinity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _gap,
        children: [
          for (var j = 0; j < perLoop * 2; j++)
            SizedBox.square(
              dimension: tile,
              // Seamless covers overlap by a pixel so anti-aliased edges
              // don't leave hairlines on the tilted wall.
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: widget.seamless ? tile + 1 : tile,
                maxHeight: widget.seamless ? tile + 1 : tile,
                child: CoverImage(
                  path: albums[(r * perLoop + j % perLoop) % albums.length]
                      .coverThumb,
                  radius: widget.seamless ? 0 : 6,
                  cacheWidth: decodeWidth,
                ),
              ),
            ),
        ],
      ),
    );
    return SizedBox(
      height: tile,
      child: AnimatedBuilder(
        animation: _frame,
        child: strip,
        builder: (context, child) {
          final t = (_pos + widget.phase + r * 0.29) % 1;
          final drift = (r.isEven ? t : 1 - t) * loop;
          // Parallax: neighbouring rows move against each other, lower rows
          // less, as if further away.
          final follow =
              _follow * stride * (1.2 - 0.2 * r) * (r.isEven ? 1 : -1);
          final shift = (drift + follow) % loop;
          return Transform.translate(offset: Offset(-shift, 0), child: child);
        },
      ),
    );
  }
}
