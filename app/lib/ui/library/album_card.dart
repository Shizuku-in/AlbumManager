import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/ui/common/tone_label.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/labels.dart';
import 'package:album_manager/util/system.dart';

/// Right-click menu for an album in the library (desktop convention).
class AlbumContextMenu extends StatefulWidget {
  final AlbumSummary album;
  final VoidCallback onOpen;
  final Widget child;
  const AlbumContextMenu({super.key, required this.album, required this.onOpen, required this.child});

  @override
  State<AlbumContextMenu> createState() => _AlbumContextMenuState();
}

class _AlbumContextMenuState extends State<AlbumContextMenu> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    return MenuAnchor(
      controller: _menu,
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Icons.info_outlined), onPressed: widget.onOpen, child: const Text('查看详情')),
        MenuItemButton(leadingIcon: const Icon(Icons.folder_open_outlined), onPressed: () => openPath(a.path), child: const Text('打开文件夹')),
        MenuItemButton(leadingIcon: const Icon(Icons.open_in_new), onPressed: () => revealInExplorer(a.path), child: const Text('在资源管理器中定位')),
      ],
      child: GestureDetector(
        onSecondaryTapUp: (d) => _menu.open(position: d.localPosition),
        child: widget.child,
      ),
    );
  }
}

/// M3 filled card: media on top, headline + supporting text below.
class AlbumCard extends StatelessWidget {
  final AlbumSummary album;
  final VoidCallback onTap;
  const AlbumCard({super.key, required this.album, required this.onTap});

  static const _infoPadding = EdgeInsets.fromLTRB(12, 10, 8, 8);

  static bool get _hasSubtitle => settings.showsOnCard(CardField.artist) || settings.showsOnCard(CardField.date);

  /// Grid of cards at most [CardSize.maxExtent] wide: a square cover plus an
  /// info area sized for two title lines and (if shown) one subtitle line.
  /// Unlike a fixed aspect ratio, the info area doesn't shrink with narrow
  /// tiles and overflow.
  static SliverGridDelegate gridDelegate(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle s) => scaler.scale(s.fontSize!) * (s.height ?? 1.2);
    final subtitle = _hasSubtitle ? 2 + line(t.bodySmall!) : 0;
    // +1 absorbs rounding in text layout.
    return _CoverGridDelegate(settings.cardSize.maxExtent, _infoPadding.vertical + 2 * line(t.titleSmall!) + subtitle + 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final showRip = settings.showsOnCard(CardField.ripStatus) && album.source == AlbumSource.cdRip && album.ripStatus != RipStatus.noLog;
    final showSource = settings.showsOnCard(CardField.source);
    final showQuality = settings.showsOnCard(CardField.quality) && (album.quality == AudioQuality.hiRes || album.quality == AudioQuality.dsd);
    final subtitle = [
      if (settings.showsOnCard(CardField.artist)) album.artist,
      if (settings.showsOnCard(CardField.date)) settings.formatDate(album.date),
    ].whereType<String>().join(' · ');
    // Decode at display size (grid tiles are at most maxExtent wide) rather
    // than the 480px thumbnail, so more covers fit in the image cache.
    final decodeWidth = math.min(480, (settings.cardSize.maxExtent * MediaQuery.devicePixelRatioOf(context)).ceil());
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(fit: StackFit.expand, children: [
              CoverImage(path: album.coverThumb, radius: 0, cacheWidth: decodeWidth),
              Positioned(
                left: 8,
                bottom: 8,
                child: Row(spacing: 4, children: [
                  if (showSource) ToneLabel(album.source.short, tone: album.source.tone(context)),
                  if (showQuality) ToneLabel(album.quality.label, tone: album.quality.tone(context)),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: _infoPadding,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(album.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                    if (_hasSubtitle) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ]),
                ),
                if (showRip)
                  Tooltip(
                    message: album.ripStatus.description,
                    child: Icon(album.ripStatus.icon, size: 18, color: album.ripStatus.tone(context).color),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CoverGridDelegate extends SliverGridDelegate {
  static const _spacing = 16.0;
  final double maxExtent;
  final double infoHeight;
  const _CoverGridDelegate(this.maxExtent, this.infoHeight);

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    // Same column count as SliverGridDelegateWithMaxCrossAxisExtent.
    final columns = math.max(1, (width / (maxExtent + _spacing)).ceil());
    final tile = math.max(0.0, (width - _spacing * (columns - 1)) / columns);
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: tile + infoHeight + _spacing,
      crossAxisStride: tile + _spacing,
      childMainAxisExtent: tile + infoHeight,
      childCrossAxisExtent: tile,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(_CoverGridDelegate oldDelegate) => oldDelegate.maxExtent != maxExtent || oldDelegate.infoHeight != infoHeight;
}

/// M3 two-line list item.
class AlbumTile extends StatelessWidget {
  final AlbumSummary album;
  final VoidCallback onTap;
  const AlbumTile({super.key, required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final meta = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 56,
        height: 56,
        child: CoverImage(path: album.coverThumb, radius: 8, cacheWidth: 120),
      ),
      title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([album.artist ?? '—', settings.formatDate(album.date)].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ToneLabel(album.source.short, tone: album.source.tone(context)),
        const SizedBox(width: 16),
        SizedBox(width: 168, child: Text(album.qualityLabel, style: meta, overflow: TextOverflow.ellipsis)),
        SizedBox(
          width: 32,
          child: album.source == AlbumSource.cdRip
              ? Tooltip(message: album.ripStatus.description, child: Icon(album.ripStatus.icon, size: 20, color: album.ripStatus.tone(context).color))
              : null,
        ),
        SizedBox(width: 64, child: Text('${album.trackCount} 首', style: meta, textAlign: TextAlign.end)),
        SizedBox(width: 72, child: Text(formatDuration(album.durationSecs), style: meta, textAlign: TextAlign.end)),
        SizedBox(width: 88, child: Text(formatSize(album.totalSize), style: meta, textAlign: TextAlign.end)),
      ]),
    );
  }
}
