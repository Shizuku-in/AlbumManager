import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/ui/common/tone_label.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/labels.dart';

/// M3 filled card: media on top, headline + supporting text below.
class AlbumCard extends StatelessWidget {
  final AlbumSummary album;
  final VoidCallback onTap;
  const AlbumCard({super.key, required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final showRip = album.source == AlbumSource.cdRip && album.ripStatus != RipStatus.noLog;
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(fit: StackFit.expand, children: [
              Hero(tag: 'cover:${album.id}', child: CoverImage(path: album.coverThumb, radius: 0, cacheWidth: 480)),
              Positioned(
                left: 8,
                bottom: 8,
                child: Row(children: [
                  ToneLabel(album.source.short, tone: album.source.tone(context)),
                  if (album.quality == AudioQuality.hiRes || album.quality == AudioQuality.dsd) ...[
                    const SizedBox(width: 4),
                    ToneLabel(album.quality.label, tone: album.quality.tone(context)),
                  ],
                ]),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(album.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      [album.artist, album.date].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
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
        child: Hero(tag: 'cover:${album.id}', child: CoverImage(path: album.coverThumb, radius: 8, cacheWidth: 120)),
      ),
      title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([album.artist ?? '—', album.date].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
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
