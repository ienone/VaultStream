import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'search_models.dart';

final unifiedSearchProvider = FutureProvider.autoDispose
    .family<UnifiedSearchResults, UnifiedSearchRequest>(
      (ref, request) =>
          fetchUnifiedSearch(ref.read(apiClientProvider), request),
    );

Future<UnifiedSearchResults> fetchUnifiedSearch(
  Dio client,
  UnifiedSearchRequest request,
) async {
  final response = await client.get(
    '/search/unified',
    queryParameters: request.toQueryParameters(),
    options: Options(listFormat: ListFormat.multi),
  );
  return UnifiedSearchResults.fromJson(
    Map<String, dynamic>.from(response.data as Map),
  );
}
