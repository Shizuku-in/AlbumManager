import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/theme/app_colors.dart';
import 'package:album_manager/ui/album/album_page.dart';
import 'package:album_manager/ui/album/cue_fix_dialog.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/util/labels.dart';
import 'package:album_manager/util/memo.dart';
import 'package:album_manager/util/system.dart';

/// Albums affected per issue kind (each album counted once per kind).
final _byKind = Memo<(List<AlbumSummary>, Set<IssueKind>), Map<IssueKind, List<AlbumSummary>>>();

Map<IssueKind, List<AlbumSummary>> _group(List<AlbumSummary> albums) {
  final m = <IssueKind, List<AlbumSummary>>{};
  for (final a in albums) {
    for (final k in settings.issuesOf(a).map((i) => i.kind).toSet()) {
      m.putIfAbsent(k, () => []).add(a);
    }
  }
  return m;
}

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
      listenable: Listenable.merge([library, settings]),
      builder: (context, _) {
        final t = Theme.of(context);
        final albums = library.albums;
        final byKind = _byKind((albums, settings.hiddenIssues), () => _group(albums));
        final kinds = IssueKind.values.where(byKind.containsKey).toList();
        final kind = (_kind != null && kinds.contains(_kind)) ? _kind : (kinds.isEmpty ? null : kinds.first);
        final affected = byKind[kind] ?? const <AlbumSummary>[];
        final total = byKind.values.fold(0, (n, l) => n + l.length);
        if (kinds.isEmpty) {
          final enabled = IssueKind.values.length - settings.hiddenIssues.length;
          return AppPage(
            title: '健康检查',
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_outline, size: 48, color: AppColors.of(context).success.color),
                    const SizedBox(height: 16),
                    Text('没有发现问题', style: t.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${albums.length} 张专辑通过了已启用的 $enabled 项检查',
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
              ),
            ],
          );
        }
        return AppPage(
          title: '健康检查',
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '$total 项问题，涉及 ${library.albums.where((a) => settings.issuesOf(a).isNotEmpty).length} 张专辑',
                    style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final k in kinds)
                      ChoiceChip(
                        showCheckmark: false,
                        avatar: Icon(k.icon, color: k.tone(context).color),
                        label: Text('${k.label}  ${byKind[k]!.length}'),
                        selected: k == kind,
                        onSelected: (_) => setState(() => _kind = k),
                      ),
                  ]),
                  // Bulk fix for the selected kind, next to the list it acts on.
                  if (kind == IssueKind.cueEncoding && affected.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _fixing ? null : () => _fixAll(affected),
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text('全部转换为 UTF-8（${affected.length} 张专辑）'),
                    ),
                  ],
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
