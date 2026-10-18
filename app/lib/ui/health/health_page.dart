import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/ui/album/album_page.dart';
import 'package:album_manager/ui/album/cue_fix_dialog.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/util/labels.dart';
import 'package:album_manager/util/system.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  IssueKind? _kind;
  bool _fixing = false;

  Future<void> _fixAll(List<AlbumSummary> targets) async {
    final n = targets.fold(0, (n, a) => n + a.issues.where((i) => i.kind == IssueKind.cueEncoding).length);
    if (!await confirmCueFix(context, n)) return;
    setState(() => _fixing = true);
    var done = 0;
    for (final a in targets) {
      try {
        await library.fixCue(a.id);
        done++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _fixing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已修复 $done / ${targets.length} 张专辑的 CUE 编码')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final t = Theme.of(context);
        final counts = <IssueKind, int>{};
        for (final a in library.albums) {
          for (final k in a.issues.map((i) => i.kind).toSet()) {
            counts[k] = (counts[k] ?? 0) + 1;
          }
        }
        final kinds = IssueKind.values.where((k) => (counts[k] ?? 0) > 0).toList();
        final kind = (_kind != null && kinds.contains(_kind)) ? _kind : (kinds.isEmpty ? null : kinds.first);
        final affected = kind == null ? <AlbumSummary>[] : library.albums.where((a) => a.issues.any((i) => i.kind == kind)).toList();
        final total = counts.values.fold(0, (a, b) => a + b);
        return AppPage(
          title: '健康检查',
          actions: [
            if (kind == IssueKind.cueEncoding && affected.isNotEmpty)
              FilledButton.icon(
                onPressed: _fixing ? null : () => _fixAll(affected),
                icon: const Icon(Icons.auto_fix_high),
                label: Text('全部转换为 UTF-8（${affected.length}）'),
              ),
          ],
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    kinds.isEmpty ? '没有发现问题' : '$total 项问题，涉及 ${library.albums.where((a) => a.issues.isNotEmpty).length} 张专辑',
                    style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final k in kinds)
                      ChoiceChip(
                        avatar: Icon(k.icon, color: k.tone(context).color),
                        label: Text('${k.label}  ${counts[k]}'),
                        selected: k == kind,
                        onSelected: (_) => setState(() => _kind = k),
                      ),
                  ]),
                  if (_fixing) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
                ]),
              ),
            ),
            SliverList.builder(
              itemCount: affected.length,
              itemBuilder: (context, i) {
                final a = affected[i];
                final msgs = a.issues.where((x) => x.kind == kind).toList();
                return ListTile(
                  onTap: () => Navigator.of(context).push(AlbumPage.route(a)),
                  leading: SizedBox(width: 56, height: 56, child: CoverImage(path: a.coverThumb, radius: 8, cacheWidth: 120)),
                  title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(msgs.map((m) => m.message).join('；'), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(a.id.split('/').first, style: t.textTheme.labelMedium),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '在资源管理器中显示',
                      onPressed: () => msgs.first.path != null ? revealInExplorer(msgs.first.path!) : openPath(a.path),
                      icon: const Icon(Icons.folder_open_outlined),
                    ),
                  ]),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
