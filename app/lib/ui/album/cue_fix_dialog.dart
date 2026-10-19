import 'package:flutter/material.dart';

import 'package:album_manager/state/settings_controller.dart';

/// Confirmation before rewriting cue sheets as UTF-8 with BOM.
Future<bool> confirmCueFix(BuildContext context, int count) async {
  final backup = settings.overwriteCue
      ? '将直接覆盖原文件，不保留备份。'
      : '原文件会保留为同目录下的 “*.cue.bak”。';
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.translate),
      title: const Text('转换 CUE 编码？'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(
          '将把 $count 个 CUE 文件转换为带 BOM 的 UTF-8。$backup\n\n'
          '转换基于自动编码识别，建议之后抽查曲名是否正确。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('转换'),
        ),
      ],
    ),
  );
  return r ?? false;
}
