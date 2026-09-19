import 'package:freezed_annotation/freezed_annotation.dart';

import '../collection/models/content.dart';

part 'search_models.freezed.dart';

const searchPlatformLabels = {
  'universal': '网页 / 文件',
  'bilibili': 'Bilibili',
  'twitter': 'Twitter/X',
  'xiaohongshu': '小红书',
  'douyin': '抖音',
  'weibo': '微博',
  'zhihu': '知乎',
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

  factory UnifiedSearchRequest.fromUri(Uri uri) {
    final query = uri.queryParameters;
    return UnifiedSearchRequest(
      query: query['q'] ?? '',
      kind: query['kind'] ?? 'all',
      contentScope: query['content_scope'] ?? 'library',
      mode: query['mode'] ?? 'semantic',
      topK: int.tryParse(query['top_k'] ?? '') ?? 30,
      page: int.tryParse(query['page'] ?? '') ?? 1,
      size: int.tryParse(query['size'] ?? '') ?? 20,
      platforms: uri.queryParametersAll['platform'] ?? const [],
      statuses: uri.queryParametersAll['status'] ?? const [],
      tags: uri.queryParametersAll['tag'] ?? const [],
      author: query['author'],
      dateFrom: DateTime.tryParse(query['date_from'] ?? ''),
      dateTo: DateTime.tryParse(query['date_to'] ?? ''),
    );
  }
}

class UnifiedContentResult {
  const UnifiedContentResult({required this.card, this.summary});

  factory UnifiedContentResult.fromJson(Map<String, dynamic> json) =>
      UnifiedContentResult(
        card: ShareCard.fromJson({
          ...json,
          'id': json['content_id'] as int,
          'status': json['status'] as String,
          'media_assets': json['media_assets'] as List,
          'semantic_score': (json['score'] as num).toDouble(),
          'semantic_match_source': json['match_source'] as String,
          'semantic_chunk_title': json['chunk_title'],
          'semantic_source_text': json['source_text'],
        }),
        summary: json['summary'] as String?,
      );

  final ShareCard card;
  final String? summary;
}

class UnifiedEventResult {
  const UnifiedEventResult({
    required this.id,
    required this.title,
    required this.status,
    required this.memberCount,
    required this.matchSource,
    this.description,
    this.latestMemberTitle,
  });

  factory UnifiedEventResult.fromJson(Map<String, dynamic> json) =>
      UnifiedEventResult(
        id: json['id'] as int,
        title: json['title'] as String,
        description: json['description'] as String?,
        status: json['status'] as String? ?? 'active',
        memberCount: json['member_count'] as int? ?? 0,
        latestMemberTitle: json['latest_member_title'] as String?,
        matchSource: json['match_source'] as String? ?? 'title',
      );

  final int id;
  final String title;
  final String? description;
  final String status;
  final int memberCount;
  final String? latestMemberTitle;
  final String matchSource;
}

class UnifiedFacetResult {
  const UnifiedFacetResult({
    required this.name,
    required this.contentCount,
    required this.latestContentId,
    this.latestContentTitle,
  });

  factory UnifiedFacetResult.fromJson(Map<String, dynamic> json) =>
      UnifiedFacetResult(
        name: json['name'] as String,
        contentCount: json['content_count'] as int? ?? 0,
        latestContentId: json['latest_content_id'] as int,
        latestContentTitle: json['latest_content_title'] as String?,
      );

  final String name;
  final int contentCount;
  final int latestContentId;
  final String? latestContentTitle;
}

class UnifiedTimepointResult {
  const UnifiedTimepointResult({
    required this.contentId,
    required this.mediaAssetId,
    required this.mediaType,
    required this.segmentType,
    required this.title,
    required this.excerpt,
    required this.startSeconds,
    required this.matchSource,
    required this.score,
    this.contentTitle,
    this.endSeconds,
  });

  factory UnifiedTimepointResult.fromJson(Map<String, dynamic> json) =>
      UnifiedTimepointResult(
        contentId: json['content_id'] as int,
        contentTitle: json['content_title'] as String?,
        mediaAssetId: json['media_asset_id'] as int,
        mediaType: json['media_type'] as String,
        segmentType: json['segment_type'] as String,
        title: json['title'] as String,
        excerpt: json['excerpt'] as String? ?? '',
        startSeconds: (json['start_seconds'] as num).toDouble(),
        endSeconds: (json['end_seconds'] as num?)?.toDouble(),
        matchSource: json['match_source'] as String,
        score: (json['score'] as num).toDouble(),
      );

  final int contentId;
  final String? contentTitle;
  final int mediaAssetId;
  final String mediaType;
  final String segmentType;
  final String title;
  final String excerpt;
  final double startSeconds;
  final double? endSeconds;
  final String matchSource;
  final double score;
}

class DocumentPageResult {
  DocumentPageResult.fromJson(Map<String, dynamic> json)
    : filename = json['filename'] as String,
      pageNumber = json['page_number'] as int,
      excerpt = json['excerpt'] as String,
      route = json['route'] as String;
  final String filename;
  final int pageNumber;
  final String excerpt;
  final String route;
}

class UnifiedSearchResults {
  const UnifiedSearchResults({
    required this.query,
    required this.kind,
    required this.contentScope,
    required this.mode,
    required this.page,
    required this.size,
    required this.contentTotal,
    required this.contentHasMore,
    required this.contents,
    required this.events,
    required this.people,
    required this.topics,
    required this.timepoints,
    this.documentPages = const [],
  });

  factory UnifiedSearchResults.fromJson(
    Map<String, dynamic> json,
  ) => UnifiedSearchResults(
    query: json['query'] as String,
    kind: json['kind'] as String,
    contentScope: json['content_scope'] as String,
    mode: json['mode'] as String,
    page: json['page'] as int,
    size: json['size'] as int,
    contentTotal: json['content_total'] as int,
    contentHasMore: json['content_has_more'] as bool,
    contents: (json['contents'] as List<dynamic>)
        .map(
          (item) => UnifiedContentResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    events: (json['events'] as List<dynamic>)
        .map(
          (item) => UnifiedEventResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    people: (json['people'] as List<dynamic>)
        .map(
          (item) => UnifiedFacetResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    topics: (json['topics'] as List<dynamic>)
        .map(
          (item) => UnifiedFacetResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    timepoints: (json['timepoints'] as List<dynamic>)
        .map(
          (item) => UnifiedTimepointResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    documentPages: (json['document_pages'] as List)
        .map(
          (item) => DocumentPageResult.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false),
  );

  final String query;
  final String kind;
  final String contentScope;
  final String mode;
  final int page;
  final int size;
  final int contentTotal;
  final bool contentHasMore;
  final List<UnifiedContentResult> contents;
  final List<UnifiedEventResult> events;
  final List<UnifiedFacetResult> people;
  final List<UnifiedFacetResult> topics;
  final List<UnifiedTimepointResult> timepoints;
  final List<DocumentPageResult> documentPages;
}
