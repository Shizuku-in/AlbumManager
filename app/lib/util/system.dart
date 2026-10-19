import 'dart:io';

/// Opens a file with its default application (or a folder in Explorer).
Future<void> openPath(String path) async {
  await Process.run('explorer.exe', [path]);
}

/// Shows a file selected in Explorer.
Future<void> revealInExplorer(String path) async {
  await Process.run('explorer.exe', ['/select,', path]);
}

/// Opens a web link in the default browser.
Future<void> openUrl(String url) async {
  await Process.run('explorer.exe', [url]);
}
