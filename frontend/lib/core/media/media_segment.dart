enum MediaSegmentType { chapter, transcript }

class MediaSegment {
  const MediaSegment({
    required this.mediaAssetId,
    required this.mediaType,
    required this.segmentType,
    required this.title,
    required this.excerpt,
    required this.startSeconds,
    this.endSeconds,
  });

  factory MediaSegment.fromJson(Map<String, dynamic> json) => MediaSegment(
    mediaAssetId: json['media_asset_id'] as int,
    mediaType: json['media_type'] as String,
    segmentType: MediaSegmentType.values.byName(json['segment_type'] as String),
    title: json['title'] as String,
    excerpt: json['excerpt'] as String? ?? '',
    startSeconds: (json['start_seconds'] as num).toDouble(),
    endSeconds: (json['end_seconds'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'media_asset_id': mediaAssetId,
    'media_type': mediaType,
    'segment_type': segmentType.name,
    'title': title,
    'excerpt': excerpt,
    'start_seconds': startSeconds,
    'end_seconds': endSeconds,
  };

  final int mediaAssetId;
  final String mediaType;
  final MediaSegmentType segmentType;
  final String title;
  final String excerpt;
  final double startSeconds;
  final double? endSeconds;

  Duration get startPosition => Duration(
    milliseconds: (startSeconds * Duration.millisecondsPerSecond).round(),
  );
}
