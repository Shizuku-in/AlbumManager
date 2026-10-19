import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/api/models.dart';
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/theme/app_theme.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/section_header.dart';
import 'package:album_manager/ui/settings/welcome_page.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/labels.dart';
import 'package:album_manager/util/system.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, settings]),
      builder: (context, _) {
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
            SliverList.list(
              children: [
                group('专辑库', [
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('专辑库位置'),
                    subtitle: Text(library.root ?? '未设置'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (library.root != null) TextButton(onPressed: () => openPath(library.root!), child: const Text('打开')),
                        const SizedBox(width: 8),
                        FilledButton.tonal(onPressed: () => pickLibraryRoot(context), child: const Text('更改')),
                      ],
                    ),
                  ),
                  // Footnote aligned with the tile text above (16 padding + 24 icon + 16 gap).
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 0, 24, 8),
                    child: Text(
                      '支持 “年份/[YYMMDD] 标题” 结构，也能识别其它结构中包含音频、CUE 或光盘镜像的文件夹。以 “.” 开头的文件夹（如 .temp、.tools）会被忽略。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ]),
                group('扫描', [
                  SwitchListTile(
                    secondary: const Icon(Icons.play_circle_outline),
                    title: const Text('启动时自动扫描'),
                    subtitle: const Text('打开应用后在后台进行一次增量扫描'),
                    value: settings.scanOnStartup,
                    onChanged: settings.setScanOnStartup,
                  ),
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
                ]),
                group('健康检查', [
                  ListTile(
                    leading: const Icon(Icons.health_and_safety_outlined),
                    title: const Text('检查项'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final k in IssueKind.values)
                            FilterChip(
                              avatar: Icon(k.icon),
                              label: Text(k.label),
                              selected: !settings.hiddenIssues.contains(k),
                              showCheckmark: false,
                              onSelected: (v) => settings.setIssueEnabled(k, v),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 0, 24, 8),
                    child: Text(
                      '关闭的检查项不会出现在健康检查、专辑详情和 “有问题” 筛选中，也不计入导航栏的问题数。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ]),
                group('存储', [const _CacheTile()]),
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
                    subtitle: const Text('关闭后可自选强调色'),
                    value: settings.useSystemColor,
                    onChanged: settings.setUseSystemColor,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    // Unfold downward from the switch while fading.
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SizeTransition(sizeFactor: anim, alignment: Alignment.topCenter, child: child),
                    ),
                    layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                    child: settings.useSystemColor
                        ? const SizedBox(key: ValueKey(false), width: double.infinity)
                        : ListTile(
                            key: const ValueKey(true),
                            leading: const Icon(Icons.color_lens_outlined),
                            title: const Text('强调色'),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final c in seedPresets) _Swatch(color: c, selected: c == settings.seedColor, onTap: () => settings.setSeedColor(c)),
                                ],
                              ),
                            ),
                          ),
                  ),
                ]),
                group('关于', [
                  const ListTile(
                    leading: Icon(Icons.album_outlined),
                    title: Text('Album Manager'),
                    subtitle: Text(
                      'Flutter + Rust。解析 EAC / XLD 抓轨日志（AccurateRip、CTDB、CRC）、CUE（自动识别 Shift-JIS / GBK 等编码）、FLAC / WAV / APE / TAK / TTA / DSF 等格式。',
                    ),
                  ),
                ]),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Thumbnail cache size, refreshed after each scan.
class _CacheTile extends StatefulWidget {
  const _CacheTile();

  @override
  State<_CacheTile> createState() => _CacheTileState();
}

class _CacheTileState extends State<_CacheTile> {
  CacheInfo? _info;
  bool _wasScanning = false;

  @override
  void initState() {
    super.initState();
    _wasScanning = library.scanning;
    library.addListener(_onLibrary);
    _refresh();
  }

  @override
  void dispose() {
    library.removeListener(_onLibrary);
    super.dispose();
  }

  void _onLibrary() {
    if (_wasScanning && !library.scanning) _refresh();
    _wasScanning = library.scanning;
  }

  Future<void> _refresh() async {
    final info = await api.cacheInfo();
    if (mounted) setState(() => _info = info);
  }

  Future<void> _rebuild() async {
    await api.clearThumbnailCache();
    await _refresh();
    await library.rescan(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return ListTile(
      leading: const Icon(Icons.image_outlined),
      title: const Text('封面缓存'),
      subtitle: Text(info == null ? '正在统计…' : '${info.thumbCount} 张缩略图，${formatSize(info.thumbBytes)}\n${info.dataDir}'),
      isThreeLine: info != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (info != null) TextButton(onPressed: () => openPath(info.dataDir), child: const Text('打开')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: library.scanning ? null : _rebuild, child: const Text('重建')),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: scheme.onSurface, width: 2) : null,
        ),
        child: selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
      ),
    );
  }
}
