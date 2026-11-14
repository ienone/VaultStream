import 'package:dio/dio.dart';

import '../collection/models/content.dart';
import 'search_models.dart';

Future<ShareCardListResponse> fetchCollectionPage(
  Dio client,
  UnifiedSearchRequest request,
) async {
  final response = await client.get<Map<String, dynamic>>(
    '/search/unified',
    queryParameters: request.toQueryParameters(),
    options: Options(listFormat: ListFormat.multi),
  );
  final data = response.data!;
  return ShareCardListResponse(
    items: [
      for (final hit in (data['contents'] as List).cast<Map<String, dynamic>>())
        ShareCard.fromJson({
          ...hit,
          'id': hit['content_id'],
          'semantic_score': hit['score'],
          'semantic_match_source': hit['match_source'],
          'semantic_chunk_title': hit['chunk_title'],
          'semantic_source_text': hit['source_text'],
        }),
    ],
    total: data['content_total'] as int,
    hasMore: data['content_has_more'] as bool,
    page: data['page'] as int,
    size: data['size'] as int,
  );
}
