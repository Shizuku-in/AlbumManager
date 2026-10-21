import 'dart:io';

import 'package:album_manager/src/rust/api/shell.dart' as shell;

// Windows goes through the shell API: spawning explorer.exe leaves a
// "/factory,{...} -Embedding" host process running after every call.

/// Opens a file or folder with the desktop's default application.
Future<void> openPath(String path) async {
  await _open(File(path).absolute.path);
}

/// Reveals an item in the file manager. Linux opens its containing folder.
Future<void> revealInFileManager(String path) async {
  final absolute = File(path).absolute.path;
  if (Platform.isWindows) {
    await shell.shellReveal(path: absolute);
  } else if (Platform.isMacOS) {
    await _run('open', ['-R', absolute]);
  } else if (Platform.isLinux) {
    await _run('xdg-open', [File(absolute).parent.path]);
  } else {
    throw UnsupportedError('Unsupported desktop platform');
  }
}

/// Opens a web link in the default browser.
Future<void> openUrl(String url) async {
  final uri = Uri.parse(url);
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw ArgumentError.value(url, 'url', 'Expected an HTTP(S) URL');
  }
  await _open(uri.toString());
}

Future<void> _open(String target) async {
  if (Platform.isWindows) {
    await shell.shellOpen(target: target);
  } else if (Platform.isMacOS) {
    await _run('open', [target]);
  } else if (Platform.isLinux) {
    await _run('xdg-open', [target]);
  } else {
    throw UnsupportedError('Unsupported desktop platform');
  }
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }
}
