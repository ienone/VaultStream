import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'media_bookmark.dart';

typedef MediaBookmarkQuery = ({int contentId, int mediaAssetId});

final mediaBookmarksProvider = FutureProvider.autoDispose
    .family<List<MediaBookmark>, MediaBookmarkQuery>((ref, query) async {
      final response = await ref
          .read(apiClientProvider)
          .get(
            '/contents/${query.contentId}/media-bookmarks',
            queryParameters: {'media_asset_id': query.mediaAssetId},
          );
      final data = Map<String, dynamic>.from(response.data as Map);
      return (data['items'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                MediaBookmark.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
    });

final mediaBookmarkActionsProvider = Provider<MediaBookmarkActions>(
  MediaBookmarkActions.new,
);

class MediaBookmarkActions {
  MediaBookmarkActions(this.ref);

  final Ref ref;

  Future<MediaBookmark> create({
    required MediaBookmarkQuery query,
    required Duration position,
    String? note,
  }) async {
    final response = await ref
        .read(apiClientProvider)
        .post(
          '/contents/${query.contentId}/media-bookmarks',
          data: {
            'media_asset_id': query.mediaAssetId,
            'position_seconds': position.inMilliseconds / 1000,
            if (note != null) 'note': note,
          },
        );
    final bookmark = _bookmark(response.data);
    ref.invalidate(mediaBookmarksProvider(query));
    return bookmark;
  }

  Future<MediaBookmark> updateNote({
    required MediaBookmarkQuery query,
    required int bookmarkId,
    String? note,
  }) async {
    final response = await ref
        .read(apiClientProvider)
        .patch(
          '/contents/${query.contentId}/media-bookmarks/$bookmarkId',
          data: {'note': note},
        );
    final bookmark = _bookmark(response.data);
    ref.invalidate(mediaBookmarksProvider(query));
    return bookmark;
  }

  Future<void> delete({
    required MediaBookmarkQuery query,
    required int bookmarkId,
  }) async {
    await ref
        .read(apiClientProvider)
        .delete('/contents/${query.contentId}/media-bookmarks/$bookmarkId');
    ref.invalidate(mediaBookmarksProvider(query));
  }

  MediaBookmark _bookmark(Object? data) =>
      MediaBookmark.fromJson(Map<String, dynamic>.from(data as Map));
}
