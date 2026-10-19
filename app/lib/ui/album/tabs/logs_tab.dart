import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/theme/app_colors.dart';
import 'package:album_manager/ui/album/text_file_dialog.dart';
import 'package:album_manager/ui/common/empty_sliver.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/labels.dart';

List<Widget> logsSlivers(BuildContext context, Album a) {
  if (a.logs.isEmpty) {
    return [
      emptySliver(
        context,
        Icons.description_outlined,
        a.summary.source == AlbumSource.cdRip
            ? '这张 CD 抓轨没有日志文件'
            : '非 CD 抓轨资源，没有抓轨日志',
      ),
    ];
  }
  return [
    SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.separated(
        itemCount: a.logs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, i) => _LogCard(log: a.logs[i]),
      ),
    ),
  ];
}

class _LogCard extends StatelessWidget {
  final RipLog log;
  const _LogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final l = log;
    final tone = l.status.tone(context);
    final rows = <(String, String?)>[
      ('程序', '${l.ripper}${l.version != null ? ' ${l.version}' : ''}'),
      ('光驱', l.drive),
      ('读取模式', l.readMode),
      ('AccurateRip', l.accurateRipSummary),
      ('CTDB', l.ctdbSummary),
      ('编码', l.encoding),
      ('日志校验和', l.hasChecksum ? '有' : '无'),
    ];
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: tone.container,
              foregroundColor: tone.onContainer,
              child: Icon(l.status.icon),
            ),
            title: Text(baseName(l.path)),
            subtitle: Text(l.status.description),
            trailing: TextButton.icon(
              onPressed: () => showTextFile(context, l.path),
              icon: const Icon(Icons.article_outlined),
              label: const Text('查看原始日志'),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                for (final (k, v) in rows)
                  if (v != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              k,
                              style: t.textTheme.bodyMedium?.copyWith(
                                color: t.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(v, style: t.textTheme.bodyMedium),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          if (l.tracks.isNotEmpty) ...[
            const Divider(height: 1),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _VerifyTable(tracks: l.tracks),
            ),
          ],
        ],
      ),
    );
  }
}

class _VerifyTable extends StatelessWidget {
  final List<TrackVerify> tracks;
  const _VerifyTable({required this.tracks});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final mono = t.textTheme.bodyMedium?.copyWith(fontFamily: 'Consolas');
    final ok = AppColors.of(context).success.color;
    return DataTable(
      headingRowHeight: 44,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 40,
      columns: const [
        DataColumn(label: Text('音轨'), numeric: true),
        DataColumn(label: Text('AccurateRip / CTDB')),
        DataColumn(label: Text('Copy CRC')),
        DataColumn(label: Text('Test CRC')),
      ],
      rows: [
        for (final tr in tracks)
          DataRow(
            cells: [
              DataCell(Text('${tr.number}')),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tr.arOk != null)
                      Icon(
                        tr.arOk!
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        size: 18,
                        color: tr.arOk! ? ok : t.colorScheme.error,
                      ),
                    const SizedBox(width: 8),
                    Text(tr.accurateRip ?? '—'),
                  ],
                ),
              ),
              DataCell(Text(tr.copyCrc ?? '—', style: mono)),
              DataCell(
                Text(
                  tr.testCrc ?? '—',
                  style: mono?.copyWith(
                    color: tr.crcMatch == false ? t.colorScheme.error : null,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
