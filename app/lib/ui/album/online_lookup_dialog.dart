import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException;

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/ui/common/svg_icon.dart';
import 'package:album_manager/ui/common/tone_label.dart';
import 'package:album_manager/util/labels.dart';
import 'package:album_manager/util/system.dart';

/// Looks the album up online, lets the user pick a release and the values to
/// take from it. Returns the album's new overrides (the chosen cover already
/// saved to the album folder), or null when cancelled.
Future<AlbumOverride?> showOnlineLookupDialog(
  BuildContext context,
  Album album,
) {
  return showDialog<AlbumOverride>(
    context: context,
    builder: (_) => _OnlineLookupDialog(album),
  );
}

String _errorText(Object e) => e is AnyhowException ? e.message : '$e';

enum _Field {
  title(OnlineField.title),
  artist(OnlineField.artist),
  date(OnlineField.date),
  catalog(OnlineField.catalog),
  event(OnlineField.event),
  cover(null);

  const _Field(this.field);

  /// The setting deciding whether it's checked by default; null for the cover.
  final OnlineField? field;

  String get label => field?.label ?? '封面';
}

class _OnlineLookupDialog extends StatefulWidget {
  final Album album;
  const _OnlineLookupDialog(this.album);

  @override
  State<_OnlineLookupDialog> createState() => _OnlineLookupDialogState();
}

class _OnlineLookupDialogState extends State<_OnlineLookupDialog> {
  final _sources = settings.onlineSources;
  late Future<OnlineResults> _results = _lookup();
  OnlineMatch? _picked;
  Set<_Field> _fields = {};
  bool _saving = false;
  String? _error;

  AlbumSummary get _s => widget.album.summary;
  int get _trackCount =>
      widget.album.discs.fold(0, (n, d) => n + d.tracks.length);
  bool get _hasCover => _s.coverThumb != null;

  Future<OnlineResults> _lookup() async {
    final r = await api.lookupOnline(
      id: _s.id,
      sources: _sources,
      options: settings.onlineOptions,
    );
    final best = r.matches.firstOrNull;
    if (settings.openExactMatch &&
        best?.matchedBy == MatchKind.discId &&
        mounted &&
        _picked == null) {
      _pick(best!);
    }
    return r;
  }

  /// The value as stored; the cover by whether there is one.
  String? _current(_Field f) => switch (f) {
    _Field.title => _s.title,
    _Field.artist => _s.artist,
    _Field.date => _s.date,
    _Field.catalog => _s.catalog,
    _Field.event => _s.event,
    _Field.cover => _s.coverThumb,
  };

  String? _online(OnlineMatch m, _Field f) => switch (f) {
    _Field.title => m.title,
    _Field.artist => m.artist,
    _Field.date => m.date,
    _Field.catalog => m.catalog,
    _Field.event => m.event,
    _Field.cover => m.coverUrl,
  };

  /// For display: dates in the chosen style.
  String _shown(_Field f, String? v) =>
      (f == _Field.date ? settings.formatDate(v) : v) ?? '（无）';

  /// Checked by default: what's new (per the settings), and the cover as
  /// set in "下载封面".
  bool _preselected(OnlineMatch m, _Field f) {
    if (_online(m, f) == null) return false;
    final field = f.field;
    if (field == null) {
      return switch (settings.coverDownload) {
        CoverDownload.missing => !_hasCover,
        CoverDownload.always => true,
        CoverDownload.never => false,
      };
    }
    return settings.preselects(field) && _online(m, f) != _current(f);
  }

  void _pick(OnlineMatch m) => setState(() {
    _picked = m;
    _error = null;
    _fields = {
      for (final f in _Field.values)
        if (_preselected(m, f)) f,
    };
  });

  Future<void> _apply() async {
    final m = _picked!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ov = _s.overrides;
      final cover = _fields.contains(_Field.cover)
          ? await api.saveOnlineCover(
              id: _s.id,
              url: m.coverUrl!,
              name: settings.coverFileName.name,
              options: settings.onlineOptions,
            )
          : ov.coverPath;
      String? take(_Field f, String? old) =>
          _fields.contains(f) ? _online(m, f) : old;
      if (!mounted) return;
      Navigator.pop(
        context,
        AlbumOverride(
          source: ov.source,
          coverPath: cover,
          hasScans: ov.hasScans,
          title: take(_Field.title, ov.title),
          artist: take(_Field.artist, ov.artist),
          date: take(_Field.date, ov.date),
          genre: ov.genre,
          catalog: take(_Field.catalog, ov.catalog),
          event: take(_Field.event, ov.event),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return AlertDialog(
      icon: const Icon(Icons.travel_explore),
      title: const Text('在线补全信息'),
      content: SizedBox(
        width: 640,
        child: picked == null ? _resultList(context) : _fieldList(picked),
      ),
      actions: [
        if (picked != null)
          TextButton(
            onPressed: _saving ? null : () => setState(() => _picked = null),
            child: const Text('返回'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (picked != null)
          FilledButton(
            onPressed: _saving || _fields.isEmpty ? null : _apply,
            child: Text(_saving ? '正在应用…' : '应用'),
          ),
      ],
    );
  }

  Widget _resultList(BuildContext context) {
    final t = Theme.of(context);
    if (_sources.isEmpty) {
      return const _Message(
        icon: Icons.cloud_off,
        text: '没有启用任何数据源（设置 → 在线补全）',
      );
    }
    return FutureBuilder(
      future: _results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _Message(
            text: '正在查询 ${_sources.map((s) => s.label).join('、')}…',
          );
        }
        if (snap.hasError) {
          return _Message(
            icon: Icons.cloud_off,
            text: '查询失败：${_errorText(snap.error!)}',
            action: TextButton(
              onPressed: () => setState(() => _results = _lookup()),
              child: const Text('重试'),
            ),
          );
        }
        final results = snap.data!.matches;
        final errors = snap.data!.errors;
        final failed = errors.isEmpty
            ? null
            : Text(
                '部分数据源查询失败：${errors.join('；')}',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.error,
                ),
              );
        if (results.isEmpty) {
          return _Message(
            icon: Icons.search_off,
            text: '没有找到匹配的专辑',
            action: failed,
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本地 $_trackCount 首 · 按匹配程度排序，选择一项查看可补全的信息',
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
            if (failed != null) ...[const SizedBox(height: 4), failed],
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, i) => _ResultTile(
                  match: results[i],
                  localTracks: _trackCount,
                  onTap: () => _pick(results[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _fieldList(OnlineMatch m) {
    final t = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResultTile(match: m, localTracks: _trackCount),
        const Divider(),
        for (final f in _Field.values)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _fields.contains(f),
            onChanged: _online(m, f) == null || _saving
                ? null
                : (v) => setState(
                    () => _fields = v!
                        ? {..._fields, f}
                        : ({..._fields}..remove(f)),
                  ),
            title: Text(f.label),
            subtitle: f == _Field.cover
                ? _coverChange(m)
                : Text(
                    '${_shown(f, _current(f))} → ${_shown(f, _online(m, f))}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
          ),
      ],
    );
  }

  /// Current cover → online cover, as thumbnails.
  Widget _coverChange(OnlineMatch m) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        spacing: 12,
        children: [
          SizedBox.square(
            dimension: 72,
            child: CoverImage(path: _s.coverThumb, radius: 8, cacheWidth: 160),
          ),
          Icon(Icons.arrow_forward, color: t.colorScheme.onSurfaceVariant),
          SizedBox.square(dimension: 72, child: _NetworkCover(url: m.thumbUrl)),
          if (m.coverUrl != null)
            Expanded(
              child: Text(
                '保存为专辑文件夹中的 ${settings.coverFileName.label}，不覆盖已有文件',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A cover found online, with the same placeholder as local covers.
class _NetworkCover extends StatelessWidget {
  final String? url;
  const _NetworkCover({required this.url});

  @override
  Widget build(BuildContext context) {
    const placeholder = CoverPlaceholder(iconSize: 24);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final OnlineMatch match;
  final int localTracks;
  final VoidCallback? onTap;
  const _ResultTile({
    required this.match,
    required this.localTracks,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final m = match;
    final muted = t.textTheme.bodySmall?.copyWith(
      color: t.colorScheme.onSurfaceVariant,
    );
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox.square(
        dimension: 56,
        child: _NetworkCover(url: m.thumbUrl),
      ),
      title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          m.artist,
          settings.formatDate(m.date),
          m.catalog,
          m.event,
          m.label,
          m.format,
          m.country,
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 4,
            children: [
              ToneLabel(m.matchedBy.label, tone: m.matchedBy.tone(context)),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  SvgIcon(
                    m.via.iconAsset,
                    size: 12,
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                  Text(
                    [
                      m.source,
                      if (m.trackCount > 0) '${m.trackCount} 首',
                    ].join(' · '),
                    style: m.trackCount == localTracks
                        ? muted?.copyWith(color: t.colorScheme.primary)
                        : muted,
                  ),
                ],
              ),
            ],
          ),
          if (m.url.isNotEmpty)
            IconButton(
              tooltip: '在 ${m.source} 打开',
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: () => openUrl(m.url),
            ),
        ],
      ),
    );
  }
}

/// Centered state of the result list, styled like the app's empty states;
/// without [icon] it shows a progress indicator.
class _Message extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Widget? action;
  const _Message({this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          if (icon == null)
            const CircularProgressIndicator()
          else
            Icon(icon, size: 40, color: t.colorScheme.onSurfaceVariant),
          Text(
            text,
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
