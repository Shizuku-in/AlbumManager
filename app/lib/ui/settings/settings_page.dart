import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/section_header.dart';
import 'package:album_manager/ui/settings/welcome_page.dart';
import 'package:album_manager/util/system.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, settings]),
      builder: (context, _) {
        final t = Theme.of(context);
        Widget group(String title, List<Widget> children) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Card.outlined(
                margin: EdgeInsets.zero,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SectionHeader(title), ...children, const SizedBox(height: 8)]),
              ),
            );
        return AppPage(
          title: '设置',
          slivers: [
            SliverList.list(children: [
              group('专辑库', [
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('专辑库位置'),
                  subtitle: Text(library.root ?? '未设置'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (library.root != null) TextButton(onPressed: () => openPath(library.root!), child: const Text('打开')),
                    const SizedBox(width: 8),
                    FilledButton.tonal(onPressed: () => pickLibraryRoot(context), child: const Text('更改')),
                  ]),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  subtitle: Text('支持 “年份/[YYMMDD] 标题” 结构，也能识别其它结构中包含音频、CUE 或光盘镜像的文件夹。以 “.” 开头的文件夹（如 .temp、.tools）会被忽略。'),
                ),
              ]),
              group('扫描', [
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('增量扫描'),
                  subtitle: Text(library.lastScanMessage ?? '只重新分析文件有变化的专辑'),
                  trailing: FilledButton(onPressed: library.scanning ? null : () => library.rescan(), child: const Text('扫描')),
                ),
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('完整重新扫描'),
                  subtitle: const Text('重新解析所有 CUE、日志和音频信息'),
                  trailing: OutlinedButton(onPressed: library.scanning ? null : () => library.rescan(force: true), child: const Text('扫描')),
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('重建封面缓存'),
                  subtitle: const Text('删除缩略图缓存并重新生成'),
                  trailing: OutlinedButton(
                    onPressed: library.scanning
                        ? null
                        : () async {
                            await api.clearThumbnailCache();
                            await library.rescan(force: true);
                          },
                    child: const Text('重建'),
                  ),
                ),
              ]),
              group('外观', [
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('主题'),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('跟随系统'), icon: Icon(Icons.brightness_auto_outlined)),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色'), icon: Icon(Icons.light_mode_outlined)),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色'), icon: Icon(Icons.dark_mode_outlined)),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => settings.setThemeMode(s.first),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('使用系统强调色'),
                  subtitle: const Text('关闭后使用默认配色'),
                  value: settings.useSystemColor,
                  onChanged: settings.setUseSystemColor,
                ),
              ]),
              group('关于', [
                ListTile(
                  leading: const Icon(Icons.album_outlined),
                  title: const Text('Album Manager'),
                  subtitle: Text(
                    'Flutter + Rust。解析 EAC / XLD 抓轨日志（AccurateRip、CTDB、CRC）、CUE（自动识别 Shift-JIS / GBK 等编码）、FLAC / WAV / APE / TAK / TTA / DSF 等格式。',
                    style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
              ]),
            ]),
          ],
        );
      },
    );
  }
}
