/// 执行后端给出的候选顺序；不猜域名、不重排来源。
class MediaCandidateResolver {
  MediaCandidateResolver(Iterable<String> urls)
    : _urls = List.unmodifiable(_deduplicate(urls));

  final List<String> _urls;
  int _index = 0;

  List<String> get urls => _urls;
  String? get current => _urls.isEmpty ? null : _urls[_index];
  int get index => _index;
  bool get hasNext => _index + 1 < _urls.length;

  bool moveNext() {
    if (!hasNext) return false;
    _index += 1;
    return true;
  }

  static Iterable<String> _deduplicate(Iterable<String> urls) sync* {
    final seen = <String>{};
    for (final rawUrl in urls) {
      final url = rawUrl.trim();
      if (url.isNotEmpty && seen.add(url)) yield url;
    }
  }
}
