import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_browser.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/util/format.dart';

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final years = library.byYear.entries.toList();
        return AppPage(
          title: '时间线',
          slivers: [
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
                itemBuilder: (context, i) =>
                    _YearCard(year: years[i].key, albums: years[i].value),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _YearCard extends StatelessWidget {
  final int year;
  final List<AlbumSummary> albums;
  const _YearCard({required this.year, required this.albums});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final covers = albums.where((a) => a.coverThumb != null).toList()
      ..sort((a, b) => (b.date ?? '').compareTo(a.date ?? ''));
    final mosaic = covers.take(6).toList();
    final dur = albums.fold<double>(0, (n, a) => n + a.durationSecs);
    final cd = albums.where((a) => a.source == AlbumSource.cdRip).length;
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => browser.showYear(year == 0 ? null : year),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < 6; i++)
                    i < mosaic.length
                        ? CoverImage(
                            path: mosaic[i].coverThumb,
                            radius: 0,
                            cacheWidth: 160,
                          )
                        : ColoredBox(
                            color: t.colorScheme.surfaceContainerHighest,
                          ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    year == 0 ? '未知' : '$year',
                    style: t.textTheme.headlineMedium,
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${albums.length} 张专辑',
                        style: t.textTheme.titleSmall,
                      ),
                      Text(
                        '$cd 张抓轨 · ${formatHours(dur)}',
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
      ),
    );
  }
}
