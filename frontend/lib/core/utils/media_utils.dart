/// 检查 URL 是否为视频
bool isVideo(String url) {
  if (url.isEmpty) return false;
  final lower = url.toLowerCase().split('?').first;
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mkv');
}

/// 检查 URL 是否为浏览器和 video_player 可播放的常见音频格式。
bool isAudio(String url) {
  if (url.isEmpty) return false;
  final lower = url.toLowerCase().split('?').first;
  return lower.endsWith('.mp3') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.aac') ||
      lower.endsWith('.ogg') ||
      lower.endsWith('.oga') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.flac') ||
      lower.endsWith('.opus');
}

/// 格式化计数（支持万/千缩写）
String formatCount(dynamic count) {
  if (count == null) return '0';
  int val = 0;
  if (count is int) {
    val = count;
  } else if (count is String) {
    val = int.tryParse(count) ?? 0;
  } else {
    val = (count as num).toInt();
  }

  if (val >= 10000) {
    return '${(val / 10000).toStringAsFixed(1)}w';
  }
  if (val >= 1000) {
    return '${(val / 1000).toStringAsFixed(1)}k';
  }
  return val.toString();
}
