import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';
import 'package:album_manager/util/labels.dart';

String _description(IssueKind k) => switch (k) {
  IssueKind.missingCover => '专辑文件夹中没有可用作封面的图片',
  IssueKind.cueEncoding => 'CUE 不是 UTF-8 编码，可在健康检查中一键转换',
  IssueKind.cueMissingFile => 'CUE 引用的音频文件不存在',
  IssueKind.ripErrors => '抓轨日志中记录了读取错误',
  IssueKind.ripUnverified => '按 OPS 日志规则有影响可信度的设置（如未用安全模式、偏移不对），或日志签名不符',
  IssueKind.missingLog => 'CD 抓轨没有附带抓轨日志',
  IssueKind.nonStandardName => '文件夹名不符合 “识别规则” 中的命名格式（专辑详情页不显示此项）',
};

/// Which issue kinds count as problems.
class HealthSettingsPage extends StatelessWidget {
  const HealthSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpage(
      title: '健康检查',
      groups: (context) => [
        SettingsGroup(
          title: '检查项',
          children: [
            for (final k in IssueKind.values)
              SwitchListTile(
                secondary: Icon(k.icon),
                title: Text(k.label),
                subtitle: Text(_description(k)),
                value: !settings.hiddenIssues.contains(k),
                onChanged: (v) => settings.setIssueEnabled(k, v),
              ),
            const SizedBox(height: 8),
            const SettingsNote('关闭的检查项不会出现在健康检查、专辑详情和 “有问题” 筛选中，也不计入导航栏的问题数。'),
          ],
        ),
      ],
    );
  }
}
