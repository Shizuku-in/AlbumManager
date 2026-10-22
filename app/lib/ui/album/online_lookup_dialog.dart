import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;
import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/svg_icon.dart';
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

/// Icon of a result's source; Discogs and FreeDB data comes through the
/// CueTools database.
String _sourceIcon(String source) => switch (source) {
  'MusicBrainz' => OnlineSource.musicBrainz.iconAsset,
  'Bangumi' => OnlineSource.bangumi.iconAsset,
  _ => OnlineSource.ctdb.iconAsset,
};

extension on MatchKind {
  String get label => switch (this) {
    MatchKind.discId => '同一张光盘',
    MatchKind.toc => '曲目结构相近',
    MatchKind.catalog => '品番',
    MatchKind.title => '标题',
  };
}

enum _Field { title, artist, date, catalog, event, cover }

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

  Future<OnlineResults> _lookup() =>
      api.lookupOnline(id: _s.id, sources: _sources);

  String? _current(_Field f) => switch (f) {
    _Field.title => _s.title,
    _Field.artist => _s.artist,
    _Field.date => _s.date,
    _Field.catalog => _s.catalog,
    _Field.event => _s.event,
    _Field.cover => _hasCover ? '已有封面' : null,
  };

  String? _online(OnlineMatch m, _Field f) => switch (f) {
    _Field.title => m.title,
    _Field.artist => m.artist,
    _Field.date => m.date,
    _Field.catalog => m.catalog,
    _Field.event => m.event,
    _Field.cover => m.coverUrl == null ? null : '下载到专辑文件夹',
  };

  void _pick(OnlineMatch m) => setState(() {
    _picked = m;
    _error = null;
    // Preselect what's new; the cover only when the album has none.
    _fields = {
      for (final f in _Field.values)
        if (_online(m, f) != null &&
            (f == _Field.cover ? !_hasCover : _online(m, f) != _current(f)))
          f,
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
          ? await api.saveOnlineCover(id: _s.id, url: m.coverUrl!)
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
          _error = '封面下载失败：$e';
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
        icon: Icon(Icons.cloud_off, size: 40),
        text: '没有启用任何数据源（设置 → 在线补全）',
      );
    }
    return FutureBuilder(
      future: _results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _Message(
            icon: const CircularProgressIndicator(),
            text: '正在查询 ${_sources.map((s) => s.label).join('、')}…',
          );
        }
        if (snap.hasError) {
          return _Message(
            icon: const Icon(Icons.cloud_off, size: 40),
            text: '查询失败：${snap.error}',
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
            icon: const Icon(Icons.search_off, size: 40),
            text: '没有找到匹配的专辑',
            action: failed,
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本地：$_trackCount 首 · 按匹配程度排序，选择一项查看可补全的信息',
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
    const names = {
      _Field.title: '标题',
      _Field.artist: '艺术家',
      _Field.date: '日期',
      _Field.catalog: '品番',
      _Field.event: '展会',
      _Field.cover: '封面',
    };
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
            title: Text(names[f]!),
            subtitle: Text(
              '${_current(f) ?? '（无）'}  →  ${_online(m, f) ?? '（无）'}',
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
    final placeholder = ColoredBox(
      color: t.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.album, color: t.colorScheme.onSurfaceVariant),
    );
    final sameTracks = m.trackCount == localTracks;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox.square(
          dimension: 56,
          child: m.thumbUrl == null
              ? placeholder
              : Image.network(
                  m.thumbUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
      ),
      title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          m.artist,
          m.date,
          m.catalog,
          m.event,
          m.label,
          [m.format, m.country].whereType<String>().join(' · '),
        ].whereType<String>().where((s) => s.isNotEmpty).join('  ·  '),
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
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  SvgIcon(
                    _sourceIcon(m.source),
                    size: 14,
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                  Text(
                    '${m.source} · ${m.matchedBy.label}',
                    style: t.textTheme.labelMedium,
                  ),
                ],
              ),
              if (m.trackCount > 0)
                Text(
                  '${m.trackCount} 首',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: sameTracks
                        ? t.colorScheme.primary
                        : t.colorScheme.onSurfaceVariant,
                  ),
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

class _Message extends StatelessWidget {
  final Widget icon;
  final String text;
  final Widget? action;
  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          icon,
          Text(text, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    );
  }
}
