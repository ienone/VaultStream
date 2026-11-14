import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_models.freezed.dart';

const searchPlatformLabels = {
  'universal': '网页 / 文件',
  'bilibili': 'Bilibili',
  'twitter': 'Twitter/X',
  'xiaohongshu': '小红书',
  'douyin': '抖音',
  'weibo': '微博',
  'zhihu': '知乎',
  'telegram': 'Telegram',
};
const searchStatusLabels = {
  'unprocessed': '未处理',
  'processing': '处理中',
  'parse_success': '解析成功',
  'parse_failed': '解析失败',
};

@freezed
abstract class UnifiedSearchRequest with _$UnifiedSearchRequest {
  const UnifiedSearchRequest._();

  const factory UnifiedSearchRequest({
    @Default('') String query,
    @Default('all') String kind,
    @Default('library') String contentScope,
    @Default('semantic') String mode,
    @Default(30) int topK,
    @Default(1) int page,
    @Default(20) int size,
    @Default([]) List<String> platforms,
    @Default([]) List<String> statuses,
    @Default([]) List<String> tags,
    String? author,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) = _UnifiedSearchRequest;

  Map<String, dynamic> toQueryParameters() => {
    'q': query,
    'kind': kind,
    'content_scope': contentScope,
    'mode': mode,
    'top_k': topK,
    'page': page,
    'size': size,
    if (platforms.isNotEmpty) 'platform': platforms,
    if (statuses.isNotEmpty) 'status': statuses,
    if (tags.isNotEmpty) 'tag': tags,
    'author': ?author,
    if (dateFrom != null) 'date_from': dateFrom!.toUtc().toIso8601String(),
    if (dateTo != null) 'date_to': dateTo!.toUtc().toIso8601String(),
  };

  Uri toUri(String path) => Uri(
    path: path,
    queryParameters: {
      for (final entry in toQueryParameters().entries)
        entry.key: entry.value is List<String>
            ? entry.value
            : entry.value.toString(),
    },
  );
}
