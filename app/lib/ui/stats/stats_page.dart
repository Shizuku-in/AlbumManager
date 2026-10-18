import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/theme/app_colors.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/section_header.dart';
import 'package:album_manager/ui/stats/stats_charts.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/memo.dart';
import 'package:album_manager/util/labels.dart';

/// Aggregates over the whole library; recomputed only when the albums change.
class _Stats {
  final int tracks, size, images, cdRips;
  final double duration;
  final Map<AlbumSource, int> sources;
  final Map<AudioQuality, int> qualities;
  final Map<RipStatus, int> rips;
  final List<MapEntry<String, int>> formats;
  final List<MapEntry<String, int>> artists;

  _Stats._(this.tracks, this.size, this.images, this.cdRips, this.duration, this.sources, this.qualities, this.rips, this.formats, this.artists);

  factory _Stats(List<AlbumSummary> albums) {
    Map<K, int> count<K>(K Function(AlbumSummary) key) {
      final m = <K, int>{};
      for (final a in albums) {
        m[key(a)] = (m[key(a)] ?? 0) + 1;
      }
      return m;
    }

    final formats = <String, int>{};
    for (final a in albums) {
      if (a.formats.isNotEmpty) formats[a.formats.first] = (formats[a.formats.first] ?? 0) + 1;
    }
    final artists = <String, int>{};
    for (final a in albums) {
      if (a.artist != null) artists[a.artist!] = (artists[a.artist!] ?? 0) + 1;
    }
    return _Stats._(
      albums.fold<int>(0, (n, a) => n + a.trackCount),
      albums.fold<int>(0, (n, a) => n + a.totalSize),
      albums.fold<int>(0, (n, a) => n + a.imageCount),
      albums.where((a) => a.source == AlbumSource.cdRip).length,
      albums.fold<double>(0, (n, a) => n + a.durationSecs),
      count((a) => a.source),
      count((a) => a.quality),
      count((a) => a.ripStatus)..remove(RipStatus.notApplicable),
      formats.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      artists.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }
}

final _stats = Memo<List<AlbumSummary>, _Stats>();

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final app = AppColors.of(context);
        final albums = library.albums;
        final st = _stats(albums, () => _Stats(albums));
        final palette = [cs.primary, cs.tertiary, cs.secondary, app.cd.color, app.digital.color, app.dsd.color, app.disc.color, cs.outline];

        Widget card(String title, Widget child, {Widget? trailing}) => Card.outlined(
              margin: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SectionHeader(title, trailing: trailing),
                Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: child),
              ]),
            );

        return AppPage(
          title: '统计',
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.list(children: [
                LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth >= 1100 ? 5 : (c.maxWidth >= 700 ? 3 : 2);
                  final w = (c.maxWidth - 16 * (cols - 1)) / cols;
                  return Wrap(spacing: 16, runSpacing: 16, children: [
                    for (final k in [
                      KpiCard('专辑', '${albums.length}', Icons.album_outlined),
                      KpiCard('曲目', '${st.tracks}', Icons.music_note_outlined),
                      KpiCard('总时长', formatHours(st.duration), Icons.schedule),
                      KpiCard('占用空间', formatSize(st.size), Icons.storage),
                      KpiCard('图片 / 扫图', '${st.images}', Icons.photo_library_outlined),
                    ])
                      SizedBox(width: w, child: k),
                  ]);
                }),
                const SizedBox(height: 16),
                card('每年专辑数', YearBarChart(data: library.byYear.map((k, v) => MapEntry(k, v.length)))),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, c) {
                  final left = card(
                    '来源与音质',
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      BreakdownBar(entries: [for (final e in st.sources.entries) (e.key.label, e.value, e.key.tone(context).color)]),
                      const SizedBox(height: 24),
                      BreakdownBar(entries: [for (final e in st.qualities.entries) (e.key.label, e.value, e.key.tone(context).color)]),
                    ]),
                  );
                  final right = card(
                    '抓轨质量与格式',
                    trailing: Text('${st.cdRips} 张 CD', style: Theme.of(context).textTheme.bodySmall),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      BreakdownBar(entries: [
                        for (final e in st.rips.entries) (e.key.label, e.value, e.key.tone(context).color),
                      ]),
                      const SizedBox(height: 24),
                      BreakdownBar(entries: [
                        for (final (i, e) in st.formats.indexed)
                          (e.key, e.value, palette[i % palette.length]),
                      ]),
                    ]),
                  );
                  if (c.maxWidth < 840) return Column(children: [left, const SizedBox(height: 16), right]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: left),
                    const SizedBox(width: 16),
                    Expanded(child: right),
                  ]);
                }),
                const SizedBox(height: 16),
                Card.outlined(
                  margin: EdgeInsets.zero,
                  child: Column(children: [
                    const SectionHeader('专辑最多的艺术家 / 品牌'),
                    for (final e in st.artists.take(12))
                      ListTile(
                        title: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(value: e.value / st.artists.first.value),
                        ),
                        trailing: Text('${e.value}', style: Theme.of(context).textTheme.labelLarge),
                      ),
                    const SizedBox(height: 8),
                  ]),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }
}
