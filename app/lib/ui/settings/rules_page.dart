import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show AnyhowException;

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';

const _templatePresets = ['[{date}] {title}', '{date} {title}', '{title} ({year})', '{title} [{year}]', '{year} - {title}'];

String _minImagesLabel(int n) => n == 0 ? '不按数量判断' : '至少 $n 张';

/// Editors for the cover keywords and folder name templates. Rules live in
/// the Rust config; changes apply on the next full scan.
class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  ScanRules? _rules;
  String? _error;

  /// Saved but not applied by a full scan yet.
  bool _pending = false;
  final _keyword = TextEditingController();
  final _scanKeyword = TextEditingController();
  final _template = TextEditingController();

  @override
  void initState() {
    super.initState();
    api.getScanRules().then((r) {
      if (mounted) setState(() => _rules = r);
    });
  }

  @override
  void dispose() {
    _keyword.dispose();
    _scanKeyword.dispose();
    _template.dispose();
    super.dispose();
  }

  Future<bool> _save({List<String>? coverKeywords, List<String>? nameTemplates, List<String>? scanFolderKeywords, int? scanMinImages}) async {
    final r = _rules!;
    final next = ScanRules(
      coverKeywords: coverKeywords ?? r.coverKeywords,
      nameTemplates: nameTemplates ?? r.nameTemplates,
      scanFolderKeywords: scanFolderKeywords ?? r.scanFolderKeywords,
      scanMinImages: scanMinImages ?? r.scanMinImages,
    );
    try {
      await api.setScanRules(rules: next);
      setState(() {
        _rules = next;
        _error = null;
        _pending = true;
      });
      return true;
    } catch (e) {
      setState(() => _error = e is AnyhowException ? e.message : '$e');
      return false;
    }
  }

  Future<void> _resetDefaults() async {
    final d = await api.defaultScanRules();
    await _save(coverKeywords: d.coverKeywords, nameTemplates: d.nameTemplates, scanFolderKeywords: d.scanFolderKeywords, scanMinImages: d.scanMinImages);
  }

  void _addKeyword() {
    final k = _keyword.text.trim();
    if (k.isEmpty) return;
    final list = _rules!.coverKeywords;
    if (!list.any((x) => x.toLowerCase() == k.toLowerCase())) _save(coverKeywords: [...list, k]);
    _keyword.clear();
  }

  void _addScanKeyword() {
    final k = _scanKeyword.text.trim();
    if (k.isEmpty) return;
    final list = _rules!.scanFolderKeywords;
    if (!list.any((x) => x.toLowerCase() == k.toLowerCase())) _save(scanFolderKeywords: [...list, k]);
    _scanKeyword.clear();
  }

  Future<void> _addTemplate(String t) async {
    t = t.trim();
    if (t.isEmpty || _rules!.nameTemplates.contains(t)) return;
    if (await _save(nameTemplates: [..._rules!.nameTemplates, t])) _template.clear();
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    final t = Theme.of(context);
    Widget input(TextEditingController c, String hint, VoidCallback onAdd) => SizedBox(
      width: 220,
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(tooltip: '添加', icon: const Icon(Icons.add), onPressed: onAdd),
        ),
        onSubmitted: (_) => onAdd(),
      ),
    );
    return SettingsSubpage(
      title: '识别规则',
      groups: (context) => rules == null
          ? const [SettingsGroup(children: [ListTile(title: Text('正在读取…'))])]
          : [
              SettingsGroup(children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(_pending ? '规则已保存，完整重新扫描后生效' : '修改后需要完整重新扫描才会生效'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: _resetDefaults, child: const Text('恢复默认')),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: library.scanning
                          ? null
                          : () {
                              setState(() => _pending = false);
                              library.rescan(force: true);
                            },
                      child: const Text('立即重新扫描'),
                    ),
                  ]),
                ),
              ]),
              SettingsGroup(title: '封面', children: [
                ListTile(
                  leading: const Icon(Icons.image_search_outlined),
                  title: const Text('封面文件名关键词'),
                  subtitle: settingsChips([
                    for (final (i, k) in rules.coverKeywords.indexed)
                      InputChip(
                        label: Text(k),
                        onPressed: i == 0 ? null : () => _save(coverKeywords: [k, ...rules.coverKeywords.where((x) => x != k)]),
                        onDeleted: () => _save(coverKeywords: rules.coverKeywords.where((x) => x != k).toList()),
                      ),
                    input(_keyword, '添加关键词', _addKeyword),
                  ]),
                ),
                const SettingsNote('专辑根目录中文件名以这些词开头的图片优先作为封面，越靠前优先级越高（点击关键词移到最前），不区分大小写。都不匹配时使用第一张图片。'),
              ]),
              SettingsGroup(title: '扫图', children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('扫图文件夹关键词'),
                  subtitle: settingsChips([
                    for (final k in rules.scanFolderKeywords)
                      InputChip(label: Text(k), onDeleted: () => _save(scanFolderKeywords: rules.scanFolderKeywords.where((x) => x != k).toList())),
                    input(_scanKeyword, '添加关键词', _addScanKeyword),
                  ]),
                ),
                ListTile(
                  leading: const Icon(Icons.collections_outlined),
                  title: const Text('按图片数量判断'),
                  subtitle: const Text('图片总数达到该数量时也视为含有扫图'),
                  trailing: MenuAnchor(
                    alignmentOffset: const Offset(0, 4),
                    builder: (context, controller, _) => OutlinedButton.icon(
                      onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                      icon: const Icon(Icons.arrow_drop_down),
                      iconAlignment: IconAlignment.end,
                      label: Text(_minImagesLabel(rules.scanMinImages)),
                    ),
                    menuChildren: [
                      for (final n in {0, 2, 3, 5, 10, 20, rules.scanMinImages}.toList()..sort())
                        MenuItemButton(
                          leadingIcon: Icon(n == rules.scanMinImages ? Icons.check : null),
                          onPressed: () => _save(scanMinImages: n),
                          child: Text(_minImagesLabel(n)),
                        ),
                    ],
                  ),
                ),
                const SettingsNote('图片所在子文件夹的名字包含这些词（如 Scans、BK、Booklet）时，认为专辑含有扫图，不区分大小写。也可以在编辑专辑时手动指定有无扫图。'),
              ]),
              SettingsGroup(title: '文件夹命名', children: [
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('专辑文件夹命名格式'),
                  subtitle: settingsChips([
                    for (final f in rules.nameTemplates)
                      InputChip(label: Text(f), onDeleted: () => _save(nameTemplates: rules.nameTemplates.where((x) => x != f).toList())),
                    input(_template, '自定义格式', () => _addTemplate(_template.text)),
                  ]),
                ),
                if (_templatePresets.any((p) => !rules.nameTemplates.contains(p)))
                  ListTile(
                    leading: const Icon(Icons.playlist_add),
                    title: const Text('常用格式'),
                    subtitle: settingsChips([
                      for (final p in _templatePresets.where((p) => !rules.nameTemplates.contains(p)))
                        ActionChip(avatar: const Icon(Icons.add), label: Text(p), onPressed: () => _addTemplate(p)),
                    ]),
                  ),
                if (_error != null) SettingsNote(_error!, color: t.colorScheme.error),
                const SettingsNote(
                  '用 {date}（240315、20240315、2024.03.15 等）或 {year}，加上 {title} 描述文件夹名，按顺序匹配。'
                  '符合格式的文件夹会被识别为专辑并读取日期和标题，不符合的会标为 “命名不规范”。',
                ),
              ]),
            ],
    );
  }
}
