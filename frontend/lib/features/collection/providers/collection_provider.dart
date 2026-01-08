import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/content.dart';

part 'collection_provider.g.dart';

@riverpod
class Collection extends _$Collection {
  @override
  FutureOr<ShareCardListResponse> build({
    int page = 1,
    int size = 20,
    String? tag,
    String? platform,
    String? status,
    String? query,
  }) async {
    final dio = ref.watch(apiClientProvider);

    final response = await dio.get(
      '/cards',
      queryParameters: {
        'page': page,
        'size': size,
        if (tag != null) 'tag': tag,
        if (platform != null) 'platform': platform,
        if (status != null) 'status': status,
        if (query != null) 'q': query,
      },
    );

    return ShareCardListResponse.fromJson(response.data);
  }
}

@riverpod
Future<ContentDetail> contentDetail(Ref ref, int id) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/contents/$id');
  return ContentDetail.fromJson(response.data);
}
