import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/svg_icon.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';
import 'package:album_manager/util/labels.dart';

/// Online databases used by the album page's "在线补全".
class OnlineSettingsPage extends StatelessWidget {
  const OnlineSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpage(
      title: '在线补全',
      onReset: settings.resetOnline,
      groups: (context) => [
        SettingsGroup(
          title: '数据源',
          children: [
            for (final s in OnlineSource.values)
              SwitchListTile(
                secondary: SvgIcon(s.iconAsset),
                title: Text(s.label),
                subtitle: Text(s.description),
                value: settings.usesOnlineSource(s),
                onChanged: (v) => settings.setOnlineSource(s, v),
              ),
            const SettingsNote(
              '在专辑页点 “在线补全” 时同时查询启用的数据源。选用的信息保存为专辑的手动修改，不会改动音频文件；封面下载到专辑文件夹，不会覆盖已有文件。',
            ),
          ],
        ),
      ],
    );
  }
}
