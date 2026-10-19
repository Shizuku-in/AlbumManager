import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/ui/album/image_viewer.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/ui/common/empty_sliver.dart';
import 'package:album_manager/ui/common/section_header.dart';
import 'package:album_manager/util/format.dart';

List<Widget> scansSlivers(BuildContext context, Album a) {
  if (a.images.isEmpty) {
    return [emptySliver(context, Icons.photo_library_outlined, '没有扫图或图片')];
  }
  final groups = <String, List<int>>{};
  for (var i = 0; i < a.images.length; i++) {
    groups.putIfAbsent(a.images[i].group, () => []).add(i);
  }
  final t = Theme.of(context);
  return [
    for (final g in groups.entries) ...[
      SliverToBoxAdapter(
        child: SectionHeader(
          g.key.isEmpty ? '根目录' : g.key,
          trailing: Text('${g.value.length} 张', style: t.textTheme.bodySmall),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: g.value.length,
          itemBuilder: (context, i) {
            final idx = g.value[i];
            final img = a.images[idx];
            return Tooltip(
              message: '${baseName(img.path)} · ${formatSize(img.size)}',
              child: Card.filled(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => ImageViewer.show(context, a.images, idx),
                  child: LazyThumb(path: img.path),
                ),
              ),
            );
          },
        ),
      ),
    ],
  ];
}
