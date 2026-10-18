import 'package:flutter/material.dart';

import 'package:album_manager/state/library_controller.dart';

/// Scan progress / album count at the bottom of the navigation drawer.
class ScanStatus extends StatelessWidget {
  const ScanStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final scan = library.scan;
    if (scan == null) {
      return Text('${library.albums.length} 张专辑', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(scan.total == 0 ? '正在查找专辑…' : '正在扫描 ${scan.done} / ${scan.total}', style: tt.labelLarge),
      if (scan.current.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(scan.current, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    ]);
  }
}
