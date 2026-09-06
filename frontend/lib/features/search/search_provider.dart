import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'search_models.dart';

final unifiedSearchProvider = FutureProvider.autoDispose
    .family<UnifiedSearchResults, UnifiedSearchRequest>((ref, request) async {
      final response = await ref
          .read(apiClientProvider)
          .get(
            '/search/unified',
            queryParameters: {
              'q': request.query,
              'kind': request.kind,
              'content_scope': request.contentScope,
              'top_k': 30,
            },
          );
      return UnifiedSearchResults.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });
