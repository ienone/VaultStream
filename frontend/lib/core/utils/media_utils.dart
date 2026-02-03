/// 检查 URL 是否为视频
bool isVideo(String url) {
  if (url.isEmpty) return false;
  final lower = url.toLowerCase().split('?').first;
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mkv');
}

/// 映射 URL 到正确的 API 路径（处理代理、本地存储等）
String mapUrl(String url, String apiBaseUrl) {
  if (url.isEmpty) return url;
  if (url.startsWith('//')) url = 'https:$url';

  // 0. 处理 local:// 协议 (后端本地存储的兜底)
  if (url.startsWith('local://')) {
    final key = url.substring('local://'.length);
    if (key.isEmpty) return '';
    final uri = Uri.parse(apiBaseUrl);
    final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    return '$origin/api/v1/media/$key';
  }

  // 1. 处理需要代理的外部域名
  if (url.contains('pbs.twimg.com') ||
      url.contains('hdslb.com') ||
      url.contains('bilibili.com') ||
      url.contains('xhscdn.com') ||
      url.contains('sinaimg.cn') ||
      url.contains('zhimg.com')) {
    if (url.contains('/proxy/image?url=')) return url;
    return '$apiBaseUrl/proxy/image?url=${Uri.encodeComponent(url)}';
  }

  // 2. 防止重复添加 /media/
  if (url.contains('/api/v1/media/')) return url;

  // 3. 处理本地存储路径
  if (url.contains('blobs/sha256/')) {
    if (url.startsWith('/media/') || url.contains('/media/')) {
      final path = url.contains('http')
          ? url.substring(url.indexOf('/media/'))
          : url;
      final cleanPath = path.startsWith('/') ? path : '/$path';
      if (cleanPath == '/media' || cleanPath == '/media/') return '';
      
      // Ensure we use the root of the API base URL (remove /api/v1 suffix)
      final uri = Uri.parse(apiBaseUrl);
      final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      return '$origin$cleanPath';
    }
    if (url.contains('/api/v1/')) {
      return url.replaceFirst('/api/v1/', '/api/v1/media/');
    }
    final cleanKey = url.startsWith('/') ? url.substring(1) : url;
    if (cleanKey.isEmpty) return '';
    
    final uri = Uri.parse(apiBaseUrl);
    final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    return '$origin/media/$cleanKey';
  }

  if (url.startsWith('/media') || url.contains('/media/')) {
    final path = url.contains('http')
        ? url.substring(url.indexOf('/media/'))
        : url;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    if (cleanPath == '/media' || cleanPath == '/media/') return '';
    
    final uri = Uri.parse(apiBaseUrl);
    final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    return '$origin$cleanPath';
  }

  // 4. 所有其他外部URL都走代理以避免CORS问题
  if (url.startsWith('http://') || url.startsWith('https://')) {
    if (url.contains('/proxy/image?url=')) return url;
    return '$apiBaseUrl/proxy/image?url=${Uri.encodeComponent(url)}';
  }

  return url;
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
