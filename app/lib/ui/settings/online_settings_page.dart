import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/svg_icon.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';
import 'package:album_manager/util/labels.dart';

/// Online databases and options of the album page's "在线补全".
class OnlineSettingsPage extends StatelessWidget {
  const OnlineSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bangumi = settings.usesOnlineSource(OnlineSource.bangumi);
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
          ],
        ),
        SettingsGroup(
          title: '查询',
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.album_outlined),
              title: const Text('找到同一张光盘时直接打开'),
              subtitle: const Text('最佳结果与抓轨日志或 CUE 的光盘目录一致时，跳过结果列表'),
              value: settings.openExactMatch,
              onChanged: settings.setOpenExactMatch,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.translate),
              title: const Text('Bangumi 标题优先用中文名'),
              subtitle: Text(bangumi ? '条目有中文名时用中文名作为标题' : '需要先启用 Bangumi'),
              value: settings.preferChineseTitle,
              onChanged: bangumi ? settings.setPreferChineseTitle : null,
            ),
          ],
        ),
        SettingsGroup(
          title: '应用',
          children: [
            SettingsMultiChoice(
              icon: Icons.checklist,
              title: '默认勾选',
              subtitle: '选中一条结果后，这些信息与当前不同时会预先勾选',
              values: OnlineField.values,
              isOn: settings.preselects,
              label: (f) => f.label,
              onChanged: settings.setPreselected,
            ),
            SettingsChoice(
              icon: Icons.image_outlined,
              title: '下载封面',
              subtitle: '何时预先勾选下载在线封面',
              values: CoverDownload.values,
              selected: settings.coverDownload,
              label: (c) => c.label,
              onSelected: settings.setCoverDownload,
            ),
            SettingsChoice(
              icon: Icons.drive_file_rename_outline,
              title: '封面文件名',
              subtitle: 'PNG 封面使用 .png；同名文件已存在时另存为 “cover (2).jpg” 等',
              values: CoverFileName.values,
              selected: settings.coverFileName,
              label: (n) => n.label,
              onSelected: settings.setCoverFileName,
            ),
            const SettingsNote('选用的信息保存为专辑的手动修改，不会改动音频文件，可在 “编辑专辑” 中清空恢复。'),
          ],
        ),
        SettingsGroup(
          title: '网络',
          children: [
            ListTile(
              leading: const Icon(Icons.lan_outlined),
              title: const Text('代理'),
              subtitle: Text(settings.onlineProxy ?? '不使用'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editProxy(context),
            ),
            SettingsChoice(
              icon: Icons.timer_outlined,
              title: '超时',
              subtitle: '单次请求的最长等待时间',
              values: OnlineTimeout.values,
              selected: settings.onlineTimeout,
              label: (t) => t.label,
              onSelected: settings.setOnlineTimeout,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editProxy(BuildContext context) async {
    final r = await showDialog<_ProxyResult>(
      context: context,
      builder: (_) => _ProxyDialog(settings.onlineProxy),
    );
    if (r != null) settings.setOnlineProxy(r.proxy);
  }
}

/// Null [proxy] = connect directly.
class _ProxyResult {
  final String? proxy;
  const _ProxyResult(this.proxy);
}

class _ProxyDialog extends StatefulWidget {
  final String? initial;
  const _ProxyDialog(this.initial);

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  late final _text = TextEditingController(text: widget.initial);

  /// `scheme://[user:pass@]host:port` with a scheme the client supports.
  static final _valid = RegExp(
    r'^(https?|socks5h?|socks4a?)://([^\s/@]+@)?[^\s/:@]+:\d{1,5}/?$',
  );

  bool get _ok => _valid.hasMatch(_text.text.trim());

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final empty = _text.text.trim().isEmpty;
    return AlertDialog(
      icon: const Icon(Icons.lan_outlined),
      title: const Text('代理'),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _text,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '代理地址',
            hintText: 'http://127.0.0.1:7890',
            helperText: '支持 http、https、socks5、socks4，留空表示不使用',
            errorText: empty || _ok ? null : '格式应为 协议://主机:端口',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: empty || _ok
              ? () => Navigator.pop(
                  context,
                  _ProxyResult(empty ? null : _text.text.trim()),
                )
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
