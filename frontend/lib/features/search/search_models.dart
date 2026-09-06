typedef UnifiedSearchRequest = ({
  String query,
  String kind,
  String contentScope,
});

class UnifiedContentResult {
  const UnifiedContentResult({
    required this.id,
    required this.platform,
    required this.status,
    required this.matchSource,
    required this.score,
    this.title,
    this.summary,
    this.authorName,
  });

  factory UnifiedContentResult.fromJson(Map<String, dynamic> json) =>
      UnifiedContentResult(
        id: json['content_id'] as int,
        platform: json['platform'] as String? ?? '',
        status: json['status'] as String? ?? '',
        matchSource: json['match_source'] as String? ?? 'fts',
        score: (json['score'] as num?)?.toDouble() ?? 0,
        title: json['title'] as String?,
        summary: json['summary'] as String?,
        authorName: json['author_name'] as String?,
      );

  final int id;
  final String platform;
  final String status;
  final String matchSource;
  final double score;
  final String? title;
  final String? summary;
  final String? authorName;
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

class UnifiedSearchResults {
  const UnifiedSearchResults({
    required this.query,
    required this.kind,
    required this.contentScope,
    required this.contents,
    required this.events,
    required this.people,
    required this.topics,
    required this.timepoints,
  });

  factory UnifiedSearchResults.fromJson(
    Map<String, dynamic> json,
  ) => UnifiedSearchResults(
    query: json['query'] as String,
    kind: json['kind'] as String,
    contentScope: json['content_scope'] as String,
    contents: (json['contents'] as List<dynamic>? ?? const [])
        .map(
          (item) => UnifiedContentResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    events: (json['events'] as List<dynamic>? ?? const [])
        .map(
          (item) => UnifiedEventResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    people: (json['people'] as List<dynamic>? ?? const [])
        .map(
          (item) => UnifiedFacetResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    topics: (json['topics'] as List<dynamic>? ?? const [])
        .map(
          (item) => UnifiedFacetResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    timepoints: (json['timepoints'] as List<dynamic>? ?? const [])
        .map(
          (item) => UnifiedTimepointResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
  );

  final String query;
  final String kind;
  final String contentScope;
  final List<UnifiedContentResult> contents;
  final List<UnifiedEventResult> events;
  final List<UnifiedFacetResult> people;
  final List<UnifiedFacetResult> topics;
  final List<UnifiedTimepointResult> timepoints;
}
