import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/collection/models/media_asset.dart';

void main() {
  test('解析统一图片资产及有序来源', () {
    final asset = MediaAsset.fromJson({
      'id': 7,
      'content_id': 3,
      'media_type': 'image',
      'role': 'cover',
      'archive_status': 'ready',
      'sources': [
        {
          'url': 'http://server/media.webp?signature=x',
          'source_kind': 'local_signed',
          'variant_kind': 'optimized',
          'mime_type': 'image/webp',
          'expires_at': '2026-07-26T12:00:00Z',
        },
        {
          'url': 'https://origin.test/image.jpg',
          'source_kind': 'remote_direct',
        },
      ],
    });

    expect(asset.mediaType, MediaType.image);
    expect(asset.role, MediaRole.cover);
    expect(asset.sources.first.sourceKind, MediaSourceKind.localSigned);
    expect(asset.sources.last.sourceKind, MediaSourceKind.remoteDirect);
  });
}
