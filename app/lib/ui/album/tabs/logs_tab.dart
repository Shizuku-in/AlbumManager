import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';
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
        itemBuilder: (context, i) => ListenableBuilder(
          listenable: settings,
          builder: (context, _) => _LogCard(log: a.logs[i]),
        ),
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
    // Without the score, only what counts as a problem is listed.
    final shown = settings.showLogScore
        ? l.deductions
        : l.deductions.where((d) => !d.informational).toList();
    final rows = <(String, String?)>[
      ('程序', '${l.ripper}${l.version != null ? ' ${l.version}' : ''}'),
      ('光驱', l.drive),
      ('读取偏移', _offsetText(l)),
      ('读取模式', l.readMode),
      ('AccurateRip', l.accurateRipSummary),
      ('CTDB', l.ctdbSummary),
      ('日志签名', l.checksum.label),
      if (l.language != null) ('日志语言', '${l.language}（已译为英文后检查）'),
      ('编码', l.encoding),
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
            trailing: l.score == null || !settings.showLogScore
                ? null
                : _ScoreBadge(score: l.score!, tone: tone),
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
          if (shown.isNotEmpty) ...[
            const Divider(height: 1),
            _Deductions(deductions: shown, withPoints: settings.showLogScore),
          ],
          if (l.tracks.isNotEmpty) ...[
            const Divider(height: 1),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _VerifyTable(tracks: l.tracks),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                if (l.language != null)
                  TextButton.icon(
                    onPressed: () =>
                        showTextFile(context, l.path, translated: true),
                    icon: const Icon(Icons.translate),
                    label: const Text('查看英文译文'),
                  ),
                TextButton.icon(
                  onPressed: () => showTextFile(context, l.path),
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('查看原始日志'),
                ),
              ],
            ),
          ),
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

/// The log's read offset, checked against AccurateRip's drive list.
String? _offsetText(RipLog l) {
  final o = l.readOffset;
  if (o == null) return null;
  final known = l.driveOffsets;
  if (known.isEmpty) return '$o（驱动器不在 AccurateRip 数据库中）';
  if (known.contains(o)) return '$o（与 AccurateRip 驱动器数据库一致）';
  return '$o（数据库记录为 ${known.join(' / ')}）';
}

/// OPS log score on the status color.
class _ScoreBadge extends StatelessWidget {
  final int score;
  final CustomColor tone;
  const _ScoreBadge({required this.score, required this.tone});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Tooltip(
      message: '按 OPS 日志检查规则的评分（满分 100）',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: tone.container,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$score 分',
          style: t.textTheme.titleMedium?.copyWith(color: tone.onContainer),
        ),
      ),
    );
  }
}

/// Deductions, the same message on several tracks merged into one row.
/// Informational ones (range rip, settings the log doesn't record) are
/// muted: they count in the score but don't flag the log.
class _Deductions extends StatelessWidget {
  final List<LogDeduction> deductions;

  /// The full OPS view: points, and the informational deductions too.
  final bool withPoints;
  const _Deductions({required this.deductions, required this.withPoints});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final groups = <(String, bool), List<LogDeduction>>{};
    for (final d in deductions) {
      groups.putIfAbsent((d.message, d.informational), () => []).add(d);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.$2 == b.key.$2 ? 0 : (a.key.$2 ? 1 : -1));
    final total = deductions.fold(0, (n, d) => n + d.points);
    final muted = t.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            withPoints ? '扣分项（共 −$total）' : '检查发现的问题',
            style: t.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    e.key.$2 ? Icons.info_outline : Icons.remove_circle_outline,
                    size: 18,
                    color: e.key.$2 ? muted : t.colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  if (withPoints)
                    SizedBox(
                      width: 48,
                      child: Text(
                        '−${e.value.fold(0, (n, d) => n + d.points)}',
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: e.key.$2 ? muted : t.colorScheme.error,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _deductionText(e.key.$1, e.value),
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: e.key.$2 ? muted : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (entries.any((e) => e.key.$2)) ...[
            const SizedBox(height: 4),
            Text(
              'ⓘ 标记的项只计入评分，不算作问题（如整轨抓取、日志未记录的设置）',
              style: t.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

String _deductionText(String message, List<LogDeduction> ds) {
  final tracks = ds.map((d) => d.track).whereType<int>().toList()..sort();
  if (tracks.isEmpty) return message;
  if (tracks.length == 1) return '$message（音轨 ${tracks.first}）';
  return '$message（${tracks.length} 条音轨：${tracks.join('、')}）';
}
