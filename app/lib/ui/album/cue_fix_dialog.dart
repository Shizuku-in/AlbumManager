import 'package:flutter/material.dart';

/// Confirmation before rewriting cue sheets as UTF-8.
Future<bool> confirmCueFix(BuildContext context, int count) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.translate),
      title: const Text('转换 CUE 编码？'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(
          '将把 $count 个非 UTF-8 的 CUE 文件转换为 UTF-8（带 BOM）。原文件会保留为同目录下的 “*.cue.bak”。\n\n'
          '转换基于自动编码识别，建议之后抽查曲名是否正确。',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('转换')),
      ],
    ),
  );
  return r ?? false;
}
