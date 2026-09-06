enum MediaType { image, video, audio, document, other }

enum MediaRole { cover, avatar, body, gallery, poster, attachment }

enum MediaPurpose { card, detail, playback }

enum MediaSourceKind { localSigned, remoteProxy, remoteDirect }

class MediaSource {
  const MediaSource({
    required this.url,
    required this.sourceKind,
    this.variantId,
    this.variantKind,
    this.mimeType,
    this.codec,
    this.container,
    this.width,
    this.height,
    this.bitrate,
    this.sizeBytes,
    this.clientFetchAllowed = true,
    this.expiresAt,
  });

  factory MediaSource.fromJson(Map<String, dynamic> json) => MediaSource(
    url: json['url'] as String,
    sourceKind: switch (json['source_kind']) {
      'local_signed' => MediaSourceKind.localSigned,
      'remote_proxy' => MediaSourceKind.remoteProxy,
      'remote_direct' => MediaSourceKind.remoteDirect,
      _ => throw FormatException(
        'Unsupported media source kind: ${json['source_kind']}',
      ),
    },
    variantId: json['variant_id'] as int?,
    variantKind: json['variant_kind'] as String?,
    mimeType: json['mime_type'] as String?,
    codec: json['codec'] as String?,
    container: json['container'] as String?,
    width: json['width'] as int?,
    height: json['height'] as int?,
    bitrate: json['bitrate'] as int?,
    sizeBytes: json['size_bytes'] as int?,
    clientFetchAllowed: json['client_fetch_allowed'] as bool? ?? true,
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'source_kind': switch (sourceKind) {
      MediaSourceKind.localSigned => 'local_signed',
      MediaSourceKind.remoteProxy => 'remote_proxy',
      MediaSourceKind.remoteDirect => 'remote_direct',
    },
    'variant_id': variantId,
    'variant_kind': variantKind,
    'mime_type': mimeType,
    'codec': codec,
    'container': container,
    'width': width,
    'height': height,
    'bitrate': bitrate,
    'size_bytes': sizeBytes,
    'client_fetch_allowed': clientFetchAllowed,
    'expires_at': expiresAt?.toIso8601String(),
  };

  final String url;
  final MediaSourceKind sourceKind;
  final int? variantId;
  final String? variantKind;
  final String? mimeType;
  final String? codec;
  final String? container;
  final int? width;
  final int? height;
  final int? bitrate;
  final int? sizeBytes;
  final bool clientFetchAllowed;
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now.toUtc());
}

class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.contentId,
    required this.mediaType,
    required this.role,
    required this.sources,
    this.position = 0,
    this.altText,
    this.caption,
    this.width,
    this.height,
    this.durationMs,
    this.archiveStatus,
    this.lastError,
    this.metadata = const {},
    this.repairable = false,
    this.purpose = MediaPurpose.detail,
    this.generatedAt,
  });

  factory MediaAsset.fromJson(Map<String, dynamic> json) => MediaAsset(
    id: json['id'] as int,
    contentId: json['content_id'] as int,
    mediaType: MediaType.values.byName(json['media_type'] as String),
    role: MediaRole.values.byName(json['role'] as String),
    position: json['position'] as int? ?? 0,
    altText: json['alt_text'] as String?,
    caption: json['caption'] as String?,
    width: json['width'] as int?,
    height: json['height'] as int?,
    durationMs: json['duration_ms'] as int?,
    archiveStatus: json['archive_status'] as String?,
    lastError: json['last_error'] as String?,
    metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
    repairable: json['repairable'] as bool? ?? false,
    purpose: switch (json['purpose']) {
      'card' => MediaPurpose.card,
      'playback' => MediaPurpose.playback,
      _ => MediaPurpose.detail,
    },
    generatedAt: json['generated_at'] == null
        ? null
        : DateTime.parse(json['generated_at'] as String),
    sources: (json['sources'] as List<dynamic>? ?? const [])
        .map((item) => MediaSource.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content_id': contentId,
    'media_type': mediaType.name,
    'role': role.name,
    'position': position,
    'alt_text': altText,
    'caption': caption,
    'width': width,
    'height': height,
    'duration_ms': durationMs,
    'archive_status': archiveStatus,
    'last_error': lastError,
    'metadata': metadata,
    'repairable': repairable,
    'purpose': purpose.name,
    'generated_at': generatedAt?.toIso8601String(),
    'sources': sources.map((source) => source.toJson()).toList(growable: false),
  };

  final int id;
  final int contentId;
  final MediaType mediaType;
  final MediaRole role;
  final int position;
  final String? altText;
  final String? caption;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? archiveStatus;
  final String? lastError;
  final Map<String, dynamic> metadata;
  final bool repairable;
  final MediaPurpose purpose;
  final DateTime? generatedAt;
  final List<MediaSource> sources;
}

extension MediaAssetSelection on Iterable<MediaAsset> {
  MediaAsset? firstFor({required MediaRole role, MediaType? type}) {
    for (final asset in this) {
      if (asset.role == role && (type == null || asset.mediaType == type)) {
        return asset;
      }
    }
    return null;
  }
}
