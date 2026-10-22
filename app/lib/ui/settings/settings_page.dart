import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/svg_icon.dart';
import 'package:album_manager/ui/settings/appearance_settings_page.dart';
import 'package:album_manager/ui/settings/browsing_settings_page.dart';
import 'package:album_manager/ui/settings/health_settings_page.dart';
import 'package:album_manager/ui/settings/library_settings_page.dart';
import 'package:album_manager/ui/settings/online_settings_page.dart';
import 'package:album_manager/ui/settings/rip_log_settings_page.dart';
import 'package:album_manager/ui/settings/rules_page.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';
import 'package:album_manager/ui/settings/timeline_settings_page.dart';
import 'package:album_manager/util/labels.dart';
import 'package:album_manager/util/system.dart';

const _repoUrl = 'https://github.com/Shizuku-in/AlbumManager';

final _packageInfo = PackageInfo.fromPlatform();

/// Settings home: categories that open their own pages.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, settings]),
      builder: (context, _) {
        Widget category(
          IconData icon,
          String title,
          String summary,
          Widget page,
        ) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => page)),
        );
        final checks = IssueKind.values.length;
        return AppPage(
          title: '设置',
          slivers: [
            SliverList.list(
              children: [
                SettingsGroup(
                  title: '专辑库',
                  children: [
                    category(
                      Icons.folder_outlined,
                      '位置与扫描',
                      library.root ?? '尚未设置专辑库位置',
                      const LibrarySettingsPage(),
                    ),
                    category(
                      Icons.rule_folder_outlined,
                      '识别规则',
                      '封面、扫图、专辑文件夹命名格式、忽略的文件夹',
                      const RulesPage(),
                    ),
                    category(
                      Icons.travel_explore,
                      '在线补全',
                      [
                        settings.onlineSources.isEmpty
                            ? '未启用数据源'
                            : settings.onlineSources
                                  .map((s) => s.label)
                                  .join('、'),
                        if (settings.onlineProxy != null) '使用代理',
                      ].join(' · '),
                      const OnlineSettingsPage(),
                    ),
                  ],
                ),
                SettingsGroup(
                  title: '检查',
                  children: [
                    category(
                      Icons.fact_check_outlined,
                      '抓轨日志',
                      settings.showLogScore
                          ? '显示 OPS 评分 · 判定规则'
                          : '判定规则 · 评分未显示',
                      const RipLogSettingsPage(),
                    ),
                    category(
                      Icons.health_and_safety_outlined,
                      '健康检查',
                      '已启用 ${checks - settings.hiddenIssues.length} / $checks 项检查',
                      const HealthSettingsPage(),
                    ),
                  ],
                ),
                SettingsGroup(
                  title: '界面',
                  children: [
                    category(
                      Icons.palette_outlined,
                      '外观',
                      '${settings.themeMode.label} · ${settings.useSystemColor ? '系统强调色' : '自定义强调色'}',
                      const AppearanceSettingsPage(),
                    ),
                    category(
                      Icons.grid_view_outlined,
                      '专辑浏览',
                      '${settings.cardSize.label}卡片 · 日期 ${settings.dateStyle.label} · 搜索 ${SearchField.values.where(settings.searches).length} 个字段',
                      const BrowsingSettingsPage(),
                    ),
                    category(
                      Icons.view_timeline_outlined,
                      '时间线',
                      [
                        settings.timelineCard.label,
                        '${settings.wallStyle.label}封面墙',
                        settings.wallMotion.label,
                        if (settings.timelineDecades) '按年代分组',
                      ].join(' · '),
                      const TimelineSettingsPage(),
                    ),
                  ],
                ),
                SettingsGroup(
                  title: '关于',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.album_outlined),
                      title: const Text('Album Manager'),
                      subtitle: FutureBuilder(
                        future: _packageInfo,
                        builder: (context, snap) =>
                            Text('版本 ${snap.data?.version ?? ''}'),
                      ),
                    ),
                    ListTile(
                      leading: const SvgIcon('assets/icons/github.svg'),
                      title: const Text('GitHub'),
                      subtitle: const Text(_repoUrl),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => openUrl(_repoUrl),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
