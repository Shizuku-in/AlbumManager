import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/api/models.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';
import 'package:album_manager/ui/settings/welcome_page.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/system.dart';

/// Library location, scanning and the thumbnail cache.
class LibrarySettingsPage extends StatelessWidget {
  const LibrarySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpage(
      title: '位置与扫描',
      onReset: settings.resetScanning,
      resetNote: '专辑库位置不受影响。',
      groups: (context) => [
        SettingsGroup(
          title: '位置',
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('专辑库位置'),
              subtitle: Text(library.root ?? '未设置'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (library.root != null)
                    TextButton(
                      onPressed: () => openPath(library.root!),
                      child: const Text('打开'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => pickLibraryRoot(context),
                    child: const Text('更改'),
                  ),
                ],
              ),
            ),
            const SettingsNote(
              '按 “识别规则” 中的命名格式识别专辑文件夹，也能识别其它结构中包含音频、CUE 或光盘镜像的文件夹。以 “.” 开头的文件夹（如 .temp、.tools）会被忽略。',
            ),
          ],
        ),
        SettingsGroup(
          title: '扫描',
          children: [
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
              trailing: FilledButton(
                onPressed: library.scanning ? null : () => library.rescan(),
                child: const Text('扫描'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('完整重新扫描'),
              subtitle: const Text('重新解析所有 CUE、日志和音频信息'),
              trailing: OutlinedButton(
                onPressed: library.scanning
                    ? null
                    : () => library.rescan(force: true),
                child: const Text('扫描'),
              ),
            ),
          ],
        ),
        const SettingsGroup(title: '缓存', children: [_CacheTile()]),
      ],
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
    final ok = await confirmSetting(
      context,
      icon: Icons.image_outlined,
      title: '重建封面缓存？',
      body: '将删除全部缩略图并完整重新扫描专辑库，期间封面会暂时显示为占位图。',
      confirm: '重建',
    );
    if (!ok) return;
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
      subtitle: Text(
        info == null
            ? '正在统计…'
            : '${info.thumbCount} 张缩略图，${formatSize(info.thumbBytes)}\n${info.dataDir}',
      ),
      isThreeLine: info != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (info != null)
            TextButton(
              onPressed: () => openPath(info.dataDir),
              child: const Text('打开'),
            ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: library.scanning ? null : _rebuild,
            child: const Text('重建'),
          ),
        ],
      ),
    );
  }
}
