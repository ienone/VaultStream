class MediaBookmark {
  const MediaBookmark({
    required this.id,
    required this.contentId,
    required this.mediaAssetId,
    required this.positionSeconds,
    required this.createdAt,
    required this.updatedAt,
    this.note,
  });

  factory MediaBookmark.fromJson(Map<String, dynamic> json) => MediaBookmark(
    id: json['id'] as int,
    contentId: json['content_id'] as int,
    mediaAssetId: json['media_asset_id'] as int,
    positionSeconds: (json['position_seconds'] as num).toDouble(),
    note: json['note'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final int id;
  final int contentId;
  final int mediaAssetId;
  final double positionSeconds;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  Duration get position => Duration(
    milliseconds: (positionSeconds * Duration.millisecondsPerSecond).round(),
  );
}
