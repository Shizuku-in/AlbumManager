import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/system.dart';

/// Shows a log / cue / txt file (encoding detected in Rust).
Future<void> showTextFile(BuildContext context, String path) async {
  final text = await api.readTextFile(path: path);
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx);
      return AlertDialog(
        title: Text(baseName(path)),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        content: SizedBox(
          width: 820,
          height: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: t.textTheme.bodySmall?.copyWith(fontFamily: 'Consolas', fontFamilyFallback: const ['MS Gothic', 'Microsoft YaHei'], height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => revealInExplorer(path), child: const Text('在资源管理器中显示')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      );
    },
  );
}
