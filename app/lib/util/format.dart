String formatDuration(double secs, {bool long = false}) {
  final s = secs.round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  if (long) {
    if (h > 0) return '$h 小时 $m 分';
    return '$m 分 $r 秒';
  }
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  return '$m:${r.toString().padLeft(2, '0')}';
}

String formatSize(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i >= 3 ? 2 : (i == 0 ? 0 : 1))} ${units[i]}';
}

String formatHours(double secs) {
  final h = secs / 3600;
  if (h >= 100) return '${h.round()} 小时';
  return '${h.toStringAsFixed(1)} 小时';
}

/// Last path segment (either separator).
String baseName(String path) => path.split(RegExp(r'[\\/]')).last;
