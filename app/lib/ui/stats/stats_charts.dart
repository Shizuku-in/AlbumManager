import 'package:flutter/material.dart';

import 'package:album_manager/state/library_browser.dart';

class KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const KpiCard(this.label, this.value, this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: t.colorScheme.primaryContainer,
              foregroundColor: t.colorScheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: t.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label,
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
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

class YearBarChart extends StatelessWidget {
  final Map<int, int> data;
  const YearBarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final entries = data.entries.where((e) => e.key != 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return const SizedBox(height: 40);
    final max = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final label = t.textTheme.labelSmall?.copyWith(
      color: t.colorScheme.onSurfaceVariant,
    );
    return SizedBox(
      height: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in entries)
            Expanded(
              child: Tooltip(
                message: '${e.key} 年：${e.value} 张',
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => browser.showYear(e.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${e.value}', style: label),
                        const SizedBox(height: 4),
                        Container(
                          height: 160 * e.value / max + 2,
                          decoration: BoxDecoration(
                            color: t.colorScheme.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "'${(e.key % 100).toString().padLeft(2, '0')}",
                          style: label,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Segmented bar + legend.
class BreakdownBar extends StatelessWidget {
  final List<(String, int, Color)> entries;
  const BreakdownBar({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final list = [...entries]..sort((a, b) => b.$2.compareTo(a.$2));
    final total = list.fold<int>(0, (n, e) => n + e.$2);
    if (total == 0) return const Text('—');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (final (i, e) in list.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: e.$2,
                    child: Container(color: e.$3),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final e in list)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: e.$3,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(e.$1, style: t.textTheme.bodyMedium),
                  const SizedBox(width: 6),
                  Text(
                    '${e.$2} · ${(e.$2 * 100 / total).toStringAsFixed(1)}%',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
