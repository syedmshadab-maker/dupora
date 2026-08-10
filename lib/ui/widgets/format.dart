String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  double value = bytes.toDouble();
  var unitIndex = -1;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(value < 10 ? 2 : 1)} ${units[unitIndex]}';
}

String formatRate(double bytesPerSecond) => '${formatBytes(bytesPerSecond.round())}/s';

String formatDuration(Duration d) {
  if (d.inHours > 0) {
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
  return '${d.inSeconds}s';
}
