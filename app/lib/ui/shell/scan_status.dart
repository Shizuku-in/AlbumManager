import 'package:flutter/material.dart';

import 'package:album_manager/state/library_controller.dart';

/// Scan progress at the bottom of the navigation drawer; empty when idle.
class ScanStatus extends StatelessWidget {
  const ScanStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: library.scanProgress,
      builder: (context, scan, _) {
        if (scan == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(),
              ),
              Text(
                scan.total == 0
                    ? '正在查找专辑…'
                    : '正在扫描 ${scan.done} / ${scan.total}',
                style: tt.labelLarge,
              ),
              if (scan.current.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  scan.current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
