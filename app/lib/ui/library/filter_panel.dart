import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_browser.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/ui/common/smooth_scroll.dart';
import 'package:album_manager/util/labels.dart';

/// M3 modal side sheet (detached, rounded) with all library filters.
/// Filters apply live.
Future<void> showFilterPanel(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭筛选',
    // M3 scrim: the scheme's scrim color at 32 %.
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, _, _) => const Align(
      alignment: Alignment.centerRight,
      child: Padding(padding: EdgeInsets.all(16), child: _FilterPanel()),
    ),
    transitionBuilder: (context, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    ),
  );
}

class _FilterPanel extends StatefulWidget {
  const _FilterPanel();

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 360,
        height: double.infinity,
        child: ListenableBuilder(
          listenable: Listenable.merge([browser, library]),
          builder: (context, _) {
            final f = browser.filters;
            final c = browser.counts(library.albums);
            final shown = browser.visible(library.albums).length;
            // Options nobody has are hidden unless selected (so they can be cleared).
            Iterable<T> present<T>(
              Iterable<T> options,
              Map<T, int> counts,
              TriFilter<T> selected,
            ) => options.where(
              (o) => (counts[o] ?? 0) > 0 || selected[o] != null,
            );
            Widget chip(
              String label,
              int? count,
              FilterMode? mode,
              VoidCallback onTap,
            ) {
              final exclude = mode == FilterMode.exclude;
              final fg = exclude
                  ? cs.onErrorContainer
                  : cs.onSecondaryContainer;
              return FilterChip(
                selected: mode != null,
                showCheckmark: false,
                avatar: mode == null
                    ? null
                    : Icon(
                        exclude ? Icons.block : Icons.check,
                        size: 18,
                        color: fg,
                      ),
                selectedColor: exclude ? cs.errorContainer : null,
                label: Text(
                  count == null ? label : '$label  $count',
                  style: exclude
                      ? TextStyle(
                          color: fg,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: fg,
                        )
                      : null,
                ),
                onSelected: (_) => onTap(),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('筛选', style: t.textTheme.titleLarge),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      if (browser.yearFilter != null)
                        _Section('年份', [
                          InputChip(
                            label: Text('${browser.yearFilter} 年'),
                            onDeleted: () => browser.setYear(null),
                          ),
                        ]),
                      _Section('来源', [
                        for (final s in present(
                          const [
                            AlbumSource.cdRip,
                            AlbumSource.digital,
                            AlbumSource.discImage,
                            AlbumSource.unknown,
                          ],
                          c.sources,
                          f.sources,
                        ))
                          chip(
                            s.label,
                            c.sources[s],
                            f.sources[s],
                            () => browser.setFilters(f.cycleSource(s)),
                          ),
                      ]),
                      _Section('音质', [
                        for (final q in present(
                          const [
                            AudioQuality.lossy,
                            AudioQuality.lossless,
                            AudioQuality.hiRes,
                            AudioQuality.dsd,
                            AudioQuality.unknown,
                          ],
                          c.qualities,
                          f.qualities,
                        ))
                          chip(
                            q.label,
                            c.qualities[q],
                            f.qualities[q],
                            () => browser.setFilters(f.cycleQuality(q)),
                          ),
                      ]),
                      _Section('格式', [
                        for (final fmt in present(
                          c.formats.keys,
                          c.formats,
                          f.formats,
                        ))
                          chip(
                            fmt,
                            c.formats[fmt],
                            f.formats[fmt],
                            () => browser.setFilters(f.cycleFormat(fmt)),
                          ),
                      ]),
                      _Section('抓轨状态', hint: '仅 CD 抓轨', [
                        for (final r in present(
                          ripStatusFilters,
                          c.ripStatuses,
                          f.ripStatuses,
                        ))
                          chip(
                            r.label,
                            c.ripStatuses[r],
                            f.ripStatuses[r],
                            () => browser.setFilters(f.cycleRipStatus(r)),
                          ),
                      ]),
                      _Section('内容', [
                        for (final flag in ContentFlag.values)
                          chip(
                            flag.label,
                            c.flags[flag],
                            f.flags[flag],
                            () => browser.setFilters(f.cycleFlag(flag)),
                          ),
                      ]),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 24, 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: browser.activeFilterCount == 0
                            ? null
                            : browser.clearFilters,
                        child: const Text('清除全部'),
                      ),
                      const Spacer(),
                      Text(
                        '$shown 张专辑',
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: t.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? hint;
  final List<Widget> chips;
  const _Section(this.title, this.chips, {this.hint});

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: t.textTheme.titleSmall),
              if (hint != null) ...[
                const SizedBox(width: 8),
                Text(
                  hint!,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }
}
