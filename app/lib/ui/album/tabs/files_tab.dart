import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/album/text_file_dialog.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/system.dart';

IconData _fileIcon(String rel) {
  final ext = rel.contains('.') ? rel.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'flac' ||
    'wav' ||
    'ape' ||
    'tak' ||
    'tta' ||
    'dsf' ||
    'mp3' ||
    'm4a' ||
    'wv' => Icons.audio_file_outlined,
    'jpg' ||
    'jpeg' ||
    'png' ||
    'bmp' ||
    'tif' ||
    'tiff' ||
    'webp' => Icons.image_outlined,
    'cue' => Icons.queue_music,
    'log' || 'txt' => Icons.article_outlined,
    'iso' || 'mds' || 'm2ts' => Icons.album_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

final _textFile = RegExp(
  r'\.(log|cue|txt|m3u8?|lrc|accurip)$',
  caseSensitive: false,
);

/// One row of the list: a file, or (tree modes) a folder with the total size
/// of everything under it.
class _Row {
  final int depth;
  final String name;
  final String relPath;
  final int size;
  final bool isDir;
  const _Row(
    this.depth,
    this.name,
    this.relPath,
    this.size, {
    this.isDir = false,
  });
}

class _Dir {
  final dirs = <String, _Dir>{};
  final files = <FileEntry>[];
  int size = 0;
}

/// The files arrive in natural path order, which the folders keep.
_Dir _buildTree(List<FileEntry> files) {
  final root = _Dir();
  for (final f in files) {
    final parts = f.relPath.split('/');
    var d = root;
    for (final p in parts.take(parts.length - 1)) {
      d = d.dirs.putIfAbsent(p, _Dir.new)..size += f.size;
    }
    d.files.add(f);
  }
  return root;
}

/// [d]'s direct contents, folders before files.
Iterable<_Row> _children(_Dir d, String prefix, int depth) sync* {
  for (final MapEntry(key: name, value: sub) in d.dirs.entries) {
    yield _Row(depth, name, '$prefix$name', sub.size, isDir: true);
  }
  for (final f in d.files) {
    yield _Row(depth, f.relPath.split('/').last, f.relPath, f.size);
  }
}

/// Every file nested under its folders, all expanded.
List<_Row> _treeRows(_Dir root) {
  final rows = <_Row>[];
  void walk(_Dir d, String prefix, int depth) {
    for (final r in _children(d, prefix, depth)) {
      rows.add(r);
      if (r.isDir) walk(d.dirs[r.name]!, '${r.relPath}/', depth + 1);
    }
  }

  walk(root, '', 0);
  return rows;
}

/// The folder at [path] ('' = the album folder) or, once a rescan removed
/// it, its deepest remaining ancestor; with that folder's path.
(_Dir, String) _resolve(_Dir root, String path) {
  var d = root;
  final kept = <String>[];
  for (final p in path.isEmpty ? const <String>[] : path.split('/')) {
    final sub = d.dirs[p];
    if (sub == null) break;
    d = sub;
    kept.add(p);
  }
  return (d, kept.join('/'));
}

/// The parent of folder [path] ('' = the album folder).
String parentDir(String path) =>
    path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

/// Whether the 文件 tab is browsing a subfolder, so "back" should go up a
/// folder instead of leaving the album.
bool browsingSubfolder(String dir) =>
    settings.fileListMode == FileListMode.tree &&
    settings.folderView == FolderView.browse &&
    dir.isNotEmpty;

/// [dir] holds the folder shown while browsing folder by folder; the album
/// page owns it so it survives tab switches.
List<Widget> filesSlivers(
  BuildContext context,
  Album a,
  ValueNotifier<String> dir,
) {
  if (settings.fileListMode == FileListMode.flat) {
    return [
      _rowList(a, [
        for (final f in a.files) _Row(0, f.relPath, f.relPath, f.size),
      ]),
    ];
  }
  final root = _buildTree(a.files);
  if (settings.folderView == FolderView.expanded) {
    return [_rowList(a, _treeRows(root))];
  }
  return [
    ValueListenableBuilder(
      valueListenable: dir,
      builder: (context, path, _) {
        final (d, shown) = _resolve(root, path);
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: _Breadcrumb(a, shown, dir)),
            _rowList(
              a,
              _children(d, shown.isEmpty ? '' : '$shown/', 0).toList(),
              onOpenDir: (r) => dir.value = r.relPath,
            ),
          ],
        );
      },
    ),
  ];
}

String _fullPath(Album a, String relPath) => relPath.isEmpty
    ? a.summary.path
    : '${a.summary.path}\\${relPath.replaceAll('/', '\\')}';

/// Tapping a folder calls [onOpenDir] if given, else shows it in the file
/// manager.
Widget _rowList(Album a, List<_Row> rows, {void Function(_Row)? onOpenDir}) {
  return SliverList.builder(
    itemCount: rows.length,
    itemBuilder: (context, i) {
      final r = rows[i];
      final full = _fullPath(a, r.relPath);
      return ListTile(
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(
          start: 16 + 24.0 * r.depth,
          end: 24,
        ),
        leading: Icon(r.isDir ? Icons.folder_outlined : _fileIcon(r.name)),
        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          formatSize(r.size),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () {
          if (r.isDir && onOpenDir != null) {
            onOpenDir(r);
          } else if (!r.isDir && _textFile.hasMatch(r.name)) {
            showTextFile(context, full);
          } else {
            revealInFileManager(full);
          }
        },
      );
    },
  );
}

/// Up button and the path from the album folder to [path]; each ancestor
/// is a link back to it.
class _Breadcrumb extends StatelessWidget {
  final Album album;
  final String path;
  final ValueNotifier<String> dir;
  const _Breadcrumb(this.album, this.path, this.dir);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final parts = path.isEmpty ? const <String>[] : path.split('/');
    final names = [album.summary.path.split(RegExp(r'[\\/]')).last, ...parts];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一级',
            onPressed: parts.isEmpty ? null : () => dir.value = parentDir(path),
            icon: const Icon(Icons.arrow_upward),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Keeps the current folder in view when the path is long.
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < names.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: t.colorScheme.onSurfaceVariant,
                      ),
                    if (i == names.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(names[i], style: t.textTheme.labelLarge),
                      )
                    else
                      TextButton(
                        onPressed: () => dir.value = parts.take(i).join('/'),
                        child: Text(names[i]),
                      ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '在文件管理器中显示',
            onPressed: () => revealInFileManager(_fullPath(album, path)),
            icon: const Icon(Icons.folder_open_outlined),
          ),
        ],
      ),
    );
  }
}
