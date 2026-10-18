import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:album_manager/state/library_controller.dart';

Future<void> pickLibraryRoot(BuildContext context) async {
  final dir = await getDirectoryPath(confirmButtonText: '选择专辑库', initialDirectory: library.root);
  if (dir != null) await library.setRoot(dir);
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.album, size: 72, color: t.colorScheme.primary),
          const SizedBox(height: 24),
          Text('欢迎使用 Album Manager', style: t.textTheme.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            '选择你的专辑库文件夹（例如 F:\\Music），开始整理抓轨与数字资源。',
            style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(onPressed: () => pickLibraryRoot(context), icon: const Icon(Icons.folder_open), label: const Text('选择专辑库文件夹')),
        ]),
      ),
    );
  }
}
