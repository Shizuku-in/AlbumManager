import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';

/// How rip logs are judged. The rules live in Rust and apply to the stored
/// logs at once (no rescan); showing the score is a display setting.
class RipLogSettingsPage extends StatefulWidget {
  const RipLogSettingsPage({super.key});

  @override
  State<RipLogSettingsPage> createState() => _RipLogSettingsPageState();
}

class _RipLogSettingsPageState extends State<RipLogSettingsPage> {
  RipRules? _rules;
  List<DeductionKind> _kinds = const [];

  @override
  void initState() {
    super.initState();
    Future.wait([api.getRipRules(), api.ripDeductionKinds()]).then((r) {
      if (!mounted) return;
      setState(() {
        _rules = r[0] as RipRules;
        _kinds = r[1] as List<DeductionKind>;
      });
    });
  }

  Future<void> _apply(RipRules r) async {
    setState(() => _rules = r);
    await library.setRipRules(r);
  }

  RipRules _with({
    List<String>? problemKinds,
    int? arMismatchMinSubmissions,
    bool? invalidSignatureIsProblem,
    int? perfectMinConfidence,
    bool? perfectNeedsBoth,
  }) {
    final r = _rules!;
    return RipRules(
      problemKinds: problemKinds ?? r.problemKinds,
      arMismatchMinSubmissions:
          arMismatchMinSubmissions ?? r.arMismatchMinSubmissions,
      invalidSignatureIsProblem:
          invalidSignatureIsProblem ?? r.invalidSignatureIsProblem,
      perfectMinConfidence: perfectMinConfidence ?? r.perfectMinConfidence,
      perfectNeedsBoth: perfectNeedsBoth ?? r.perfectNeedsBoth,
    );
  }

  Future<void> _resetDefaults() async {
    final ok = await confirmSetting(
      context,
      icon: Icons.settings_backup_restore,
      title: '恢复默认规则？',
      body: '抓轨日志的判定规则会恢复为默认值，显示评分的开关不受影响。',
      confirm: '恢复默认',
    );
    if (ok) await _apply(await api.defaultRipRules());
  }

  Widget _kindTile(DeductionKind k) {
    final on = _rules!.problemKinds.contains(k.id);
    return SwitchListTile(
      title: Text(k.label),
      subtitle: Text('OPS 扣 ${k.points} 分'),
      value: on,
      onChanged: (v) => _apply(
        _with(
          problemKinds: v
              ? [..._rules!.problemKinds, k.id]
              : _rules!.problemKinds.where((id) => id != k.id).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    return SettingsSubpage(
      title: '抓轨日志',
      groups: (context) => rules == null
          ? const [
              SettingsGroup(children: [ListTile(title: Text('正在读取…'))]),
            ]
          : [
              SettingsGroup(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('修改后立即重新判定所有专辑，无需重新扫描'),
                    trailing: TextButton(
                      onPressed: _resetDefaults,
                      child: const Text('恢复默认'),
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: '显示',
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.scoreboard_outlined),
                    title: const Text('显示日志评分'),
                    subtitle: const Text(
                      '在抓轨日志页显示 OPS 评分和全部扣分项。关闭时只列出算作问题的项，检查照常进行',
                    ),
                    value: settings.showLogScore,
                    onChanged: settings.setShowLogScore,
                  ),
                ],
              ),
              SettingsGroup(
                title: 'AccurateRip 与签名',
                children: [
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('AccurateRip 不一致时'),
                    subtitle: const Text('不一致可能只是压盘版本不同，数据库记录越多越能说明问题'),
                    trailing: _NumberMenu(
                      value: rules.arMismatchMinSubmissions,
                      options: const [0, 1, 2, 3, 5, 10],
                      label: (n) => switch (n) {
                        0 => '不算问题',
                        1 => '一律算问题',
                        _ => '至少 $n 条记录时算问题',
                      },
                      onSelected: (n) =>
                          _apply(_with(arMismatchMinSubmissions: n)),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.verified_user_outlined),
                    title: const Text('日志签名不符算作问题'),
                    subtitle: const Text('签名不符说明日志在抓轨后被修改过'),
                    value: rules.invalidSignatureIsProblem,
                    onChanged: (v) =>
                        _apply(_with(invalidSignatureIsProblem: v)),
                  ),
                ],
              ),
              SettingsGroup(
                title: '“完美” 的标准',
                children: [
                  ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: const Text('AccurateRip 最低可信度'),
                    subtitle: const Text('每条音轨在数据库中至少有这么多条一致的记录'),
                    trailing: _NumberMenu(
                      value: rules.perfectMinConfidence,
                      options: const [1, 2, 3, 5, 10],
                      label: (n) => '至少 $n',
                      onSelected: (n) => _apply(_with(perfectMinConfidence: n)),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.join_inner),
                    title: const Text('日志有 CTDB 结果时也要求 CTDB 通过'),
                    subtitle: const Text('关闭时 AccurateRip 或 CTDB 任一全部通过即为完美'),
                    value: rules.perfectNeedsBoth,
                    onChanged: (v) => _apply(_with(perfectNeedsBoth: v)),
                  ),
                ],
              ),
              SettingsGroup(
                title: '算作问题的设置',
                children: [
                  for (final k in _kinds.where((k) => k.problemByDefault))
                    _kindTile(k),
                ],
              ),
              SettingsGroup(
                title: '默认只计分的项',
                children: [
                  for (final k in _kinds.where((k) => !k.problemByDefault))
                    _kindTile(k),
                  const SettingsNote(
                    '整轨抓取和日志未记录的设置按 OPS 规则扣分，但默认不算作问题。读取错误、可疑位置、CRC 不一致等抓轨错误总是算作错误。',
                  ),
                ],
              ),
            ],
    );
  }
}

/// Outlined drop-down button choosing one of a few numbers.
class _NumberMenu extends StatelessWidget {
  final int value;
  final List<int> options;
  final String Function(int) label;
  final ValueChanged<int> onSelected;
  const _NumberMenu({
    required this.value,
    required this.options,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.arrow_drop_down),
        iconAlignment: IconAlignment.end,
        label: Text(label(value)),
      ),
      menuChildren: [
        for (final n in {...options, value}.toList()..sort())
          MenuItemButton(
            leadingIcon: Icon(n == value ? Icons.check : null),
            onPressed: () => onSelected(n),
            child: Text(label(n)),
          ),
      ],
    );
  }
}
