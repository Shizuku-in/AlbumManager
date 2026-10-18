import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/ui/common/empty_sliver.dart';
import 'package:album_manager/ui/common/section_header.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/system.dart';

List<Widget> tracksSlivers(BuildContext context, Album a) {
  if (a.discs.isEmpty) return [emptySliver(context, Icons.music_off_outlined, '没有识别到音轨（可能是光盘镜像）')];
  final multi = a.discs.length > 1;
  return [
    for (final d in a.discs) ...[
      if (multi || d.label != null)
        SliverToBoxAdapter(
          child: SectionHeader(
            'Disc ${d.number}${d.label != null ? '  ·  ${d.label}' : ''}',
            trailing: Text(
              '${d.tracks.length} 首 · ${formatDuration(d.tracks.fold(0.0, (n, t) => n + t.durationSecs))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      SliverList.builder(
        itemCount: d.tracks.length,
        itemBuilder: (context, i) => _TrackTile(track: d.tracks[i], cuePath: d.cuePath),
      ),
    ],
  ];
}

class _TrackTile extends StatelessWidget {
  final Track track;
  final String? cuePath;
  const _TrackTile({required this.track, required this.cuePath});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tr = track;
    final spec = [
      tr.format,
      if (tr.bitDepth > 1) '${tr.bitDepth}bit',
      if (tr.sampleRate > 0) '${(tr.sampleRate / 1000).toStringAsFixed(tr.sampleRate % 1000 == 0 ? 0 : 1)}kHz',
    ].join(' · ');
    final tabular = t.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: t.colorScheme.onSurfaceVariant);
    return ListTile(
      leading: SizedBox(width: 32, child: Center(child: Text('${tr.number}'.padLeft(2, '0'), style: tabular))),
      title: Text(tr.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: tr.artist == null ? null : Text(tr.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(spec, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 24),
        SizedBox(width: 56, child: Text(tr.durationSecs > 0 ? formatDuration(tr.durationSecs) : '—', style: tabular, textAlign: TextAlign.end)),
      ]),
      // Cue rips: open the cue so the player sees the track list.
      onTap: () => openPath(tr.startSecs != null && cuePath != null ? cuePath! : tr.file),
    );
  }
}
