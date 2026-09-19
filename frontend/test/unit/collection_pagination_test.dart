import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sse_service.dart';
import 'package:frontend/features/collection/providers/collection_provider.dart';
import 'package:frontend/features/collection/providers/collection_filter_provider.dart';

class _NoSse extends SseService {
  @override
  Stream<SseEvent> build() => const Stream.empty();
}

void main() {
  test(
    'late pagination cannot merge into changed filters; refresh keeps loaded pages',
    () async {
      final pending = Completer<(RequestOptions, RequestInterceptorHandler)>();
      final dio = Dio();
      bool delay = true;
      final pages = <int>[];
      Response<dynamic> response(RequestOptions options, int id) => Response(
        requestOptions: options,
        data: {
          'query': options.queryParameters['q'],
          'kind': 'contents',
          'content_scope': 'library',
          'mode': 'keyword',
          'page': options.queryParameters['page'],
          'size': 20,
          'content_total': 60,
          'content_has_more': true,
          'contents': [
            {
              'content_id': id,
              'platform': 'universal',
              'url': 'https://example.test/$id',
              'status': 'parse_success',
              'media_assets': [],
              'score': 0,
              'match_source': 'browse',
            },
          ],
          'events': [],
          'people': [],
          'topics': [],
          'timepoints': [],
          'document_pages': [],
        },
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final page = options.queryParameters['page'] as int;
            pages.add(page);
            if (delay && page == 2) {
              pending.complete((options, handler));
            } else {
              handler.resolve(
                response(
                  options,
                  options.queryParameters['q'] == 'new' ? 90 + page : page,
                ),
              );
            }
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(dio),
          sseServiceProvider.overrideWith(_NoSse.new),
        ],
      );
      final sub = container.listen(collectionProvider, (_, _) {});
      addTearDown(() {
        sub.close();
        container.dispose();
        dio.close();
      });
      await container.read(collectionProvider.future);
      final oldLoad = container.read(collectionProvider.notifier).fetchMore();
      final (options, handler) = await pending.future;
      container
          .read(collectionFilterProvider.notifier)
          .updateSearchQuery('new');
      await container.read(collectionProvider.future);
      handler.resolve(response(options, 2));
      await oldLoad;
      expect(
        container.read(collectionProvider).requireValue.items.map((x) => x.id),
        [91],
      );
      delay = false;
      await container.read(collectionProvider.notifier).fetchMore();
      expect(
        container.read(collectionProvider).requireValue.items.map((x) => x.id),
        [91, 92],
      );
      pages.clear();
      container.invalidate(collectionProvider);
      await container.read(collectionProvider.future);
      expect(pages, [1, 2]);
      expect(
        container.read(collectionProvider).requireValue.items.map((x) => x.id),
        [91, 92],
      );
    },
  );
}
