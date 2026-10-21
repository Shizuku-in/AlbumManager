import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException;

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';

String _minImagesLabel(int n) => n == 0 ? '不按数量判断' : '至少 $n 张';

/// What each folder name placeholder matches and how templates are applied.
void _showTemplateHelp(BuildContext context) {
  final t = Theme.of(context);
  final mono = t.textTheme.bodyMedium?.copyWith(
    fontFamily: 'Consolas',
    color: t.colorScheme.primary,
  );
  final muted = t.textTheme.bodyMedium?.copyWith(
    color: t.colorScheme.onSurfaceVariant,
  );
  Widget heading(String s) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(s, style: t.textTheme.titleSmall),
  );
  // Two columns: code on the left, explanation on the right.
  Widget table(List<(String, String)> rows) => Table(
    columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
    children: [
      for (final (code, text) in rows)
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 6),
              child: Text(code, style: mono),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(text),
            ),
          ],
        ),
    ],
  );
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.help_outline),
      title: const Text('文件夹命名格式'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '用占位符描述专辑文件夹名。符合格式的文件夹会被识别为专辑并读取下列信息，'
                '不符合任何格式的会标为“命名不规范”。',
                style: muted,
              ),
              heading('占位符'),
              table(const [
                ('{title}', '标题，必须有且只有一个，取其余占位符之外剩下的文字'),
                (
                  '{date}',
                  '日期：240315、20240315、2024.03.15、2024-03-15、2024-03 等',
                ),
                ('{year}', '年份：2024，与 {date} 二选一'),
                ('{catalog}', '品番：LACA-15800、SVWC-70501~2 等，显示在专辑页并可搜索'),
                ('{artist}', '艺术家：音频标签和 CUE 中都没有艺术家时使用'),
                ('{event}', '展会：C103、M3-52、例大祭21 等，显示在专辑页并可搜索'),
                ('{*}', '跳过任意内容，如 [FLAC]、(24bit_96kHz)'),
              ]),
              heading('规则'),
              Text(
                '· 除 {title} 外至少要有 {date}、{year}、{catalog}、{artist}、{event} 之一，每个最多出现一次\n'
                '· 其他字符按原样匹配，空格可匹配任意多个空格\n'
                '· 多个格式按列表顺序尝试，使用第一个匹配的\n'
                '· 格式越宽松（如只有 {artist}），越容易把普通文件夹也当成专辑\n'
                '· 修改后需要完整重新扫描；编辑专辑时可手动修改品番和展会',
                style: muted,
              ),
              heading('示例'),
              table(const [
                ('[{date}] {title}', '[240315] 专辑名'),
                ('[{date}][{catalog}] {title}', '[240315][LACA-15800] 专辑名'),
                (
                  '({event}) [{artist}] {title} [{*}]',
                  '(C103) [社团名] 专辑名 [FLAC]',
                ),
                ('{year} - {title}', '2024 - 专辑名'),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

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

  Future<bool> _save({
    List<String>? coverKeywords,
    List<String>? nameTemplates,
    List<String>? scanFolderKeywords,
    int? scanMinImages,
  }) async {
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
    await _save(
      coverKeywords: d.coverKeywords,
      nameTemplates: d.nameTemplates,
      scanFolderKeywords: d.scanFolderKeywords,
      scanMinImages: d.scanMinImages,
    );
  }

  void _addKeyword() {
    final k = _keyword.text.trim();
    if (k.isEmpty) return;
    final list = _rules!.coverKeywords;
    if (!list.any((x) => x.toLowerCase() == k.toLowerCase())) {
      _save(coverKeywords: [...list, k]);
    }
    _keyword.clear();
  }

  void _addScanKeyword() {
    final k = _scanKeyword.text.trim();
    if (k.isEmpty) return;
    final list = _rules!.scanFolderKeywords;
    if (!list.any((x) => x.toLowerCase() == k.toLowerCase())) {
      _save(scanFolderKeywords: [...list, k]);
    }
    _scanKeyword.clear();
  }

  Future<void> _addTemplate(String t) async {
    t = t.trim();
    if (t.isEmpty || _rules!.nameTemplates.contains(t)) return;
    if (await _save(nameTemplates: [..._rules!.nameTemplates, t])) {
      _template.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    final t = Theme.of(context);
    Widget input(TextEditingController c, String hint, VoidCallback onAdd) =>
        SizedBox(
          width: 220,
          child: TextField(
            controller: c,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '添加',
                icon: const Icon(Icons.add),
                onPressed: onAdd,
              ),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        );
    return SettingsSubpage(
      title: '识别规则',
      onReset: _resetDefaults,
      resetNote: '自定义的封面关键词、扫图关键词和文件夹命名格式都会被替换，完整重新扫描后生效。',
      groups: (context) => rules == null
          ? const [
              SettingsGroup(children: [ListTile(title: Text('正在读取…'))]),
            ]
          : [
              SettingsGroup(
                children: [
                  ListTile(
                    leading: Icon(
                      _pending ? Icons.update : Icons.info_outline,
                      color: _pending ? t.colorScheme.primary : null,
                    ),
                    title: Text(
                      _pending ? '规则已保存，完整重新扫描后生效' : '修改后需要完整重新扫描才会生效',
                    ),
                    // Becomes the emphasized action while changes are waiting.
                    trailing: FilledButton(
                      style: _pending
                          ? null
                          : FilledButton.styleFrom(
                              backgroundColor: t.colorScheme.secondaryContainer,
                              foregroundColor:
                                  t.colorScheme.onSecondaryContainer,
                            ),
                      onPressed: library.scanning
                          ? null
                          : () {
                              setState(() => _pending = false);
                              library.rescan(force: true);
                            },
                      child: const Text('立即重新扫描'),
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: '封面',
                children: [
                  ListTile(
                    leading: const Icon(Icons.image_search_outlined),
                    title: const Text('封面文件名关键词'),
                    subtitle: settingsChips([
                      for (final (i, k) in rules.coverKeywords.indexed)
                        InputChip(
                          label: Text(k),
                          tooltip: i == 0 ? '优先级最高' : '移到最前',
                          onPressed: i == 0
                              ? null
                              : () => _save(
                                  coverKeywords: [
                                    k,
                                    ...rules.coverKeywords.where((x) => x != k),
                                  ],
                                ),
                          onDeleted: () => _save(
                            coverKeywords: rules.coverKeywords
                                .where((x) => x != k)
                                .toList(),
                          ),
                        ),
                      input(_keyword, '添加关键词', _addKeyword),
                    ]),
                  ),
                  const SettingsNote(
                    '专辑根目录中文件名以这些词开头的图片优先作为封面，越靠前优先级越高（点击关键词移到最前），不区分大小写。都不匹配时使用第一张图片。',
                  ),
                ],
              ),
              SettingsGroup(
                title: '扫图',
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('扫图文件夹关键词'),
                    subtitle: settingsChips([
                      for (final k in rules.scanFolderKeywords)
                        InputChip(
                          label: Text(k),
                          onDeleted: () => _save(
                            scanFolderKeywords: rules.scanFolderKeywords
                                .where((x) => x != k)
                                .toList(),
                          ),
                        ),
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
                        onPressed: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                        icon: const Icon(Icons.arrow_drop_down),
                        iconAlignment: IconAlignment.end,
                        label: Text(_minImagesLabel(rules.scanMinImages)),
                      ),
                      menuChildren: [
                        for (final n in {
                          0,
                          2,
                          3,
                          5,
                          10,
                          20,
                          rules.scanMinImages,
                        }.toList()..sort())
                          MenuItemButton(
                            leadingIcon: Icon(
                              n == rules.scanMinImages ? Icons.check : null,
                            ),
                            onPressed: () => _save(scanMinImages: n),
                            child: Text(_minImagesLabel(n)),
                          ),
                      ],
                    ),
                  ),
                  const SettingsNote(
                    '图片所在子文件夹的名字包含这些词（如 Scans、BK、Booklet）时，认为专辑含有扫图，不区分大小写。也可以在编辑专辑时手动指定有无扫图。',
                  ),
                ],
              ),
              SettingsGroup(
                title: '文件夹命名',
                trailing: IconButton(
                  tooltip: '格式说明',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showTemplateHelp(context),
                  icon: const Icon(Icons.help_outline),
                ),
                children: [
                  ListTile(
                    leading: const Icon(Icons.drive_file_rename_outline),
                    title: const Text('专辑文件夹命名格式'),
                    subtitle: settingsChips([
                      for (final f in rules.nameTemplates)
                        InputChip(
                          label: Text(f),
                          onDeleted: () => _save(
                            nameTemplates: rules.nameTemplates
                                .where((x) => x != f)
                                .toList(),
                          ),
                        ),
                      input(
                        _template,
                        '自定义格式',
                        () => _addTemplate(_template.text),
                      ),
                    ]),
                  ),
                  if (_error != null)
                    SettingsNote(_error!, color: t.colorScheme.error),
                  const SettingsNote('符合格式的文件夹会被识别为专辑，不符合的会标为“命名不规范”。'),
                ],
              ),
            ],
    );
  }
}
