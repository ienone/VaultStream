import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/discovery/providers/discovery_feed_provider.dart';

Response<Map<String, dynamic>> _page(RequestOptions options, List<int> ids) =>
    Response(
      requestOptions: options,
      data: {
        'items': [
          for (final id in ids)
            {
              'id': id,
              'url': 'https://example.test/$id',
              'created_at': '2026-09-06T00:00:00',
            },
        ],
        'page': options.queryParameters['page'],
        'size': 20,
        'total': 40,
        'has_more': true,
      },
    );

ProviderContainer _container(Dio dio) {
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(dio)],
  );
  final subscription = container.listen(discoveryFeedProvider, (_, _) {});
  addTearDown(() {
    subscription.close();
    container.dispose();
    dio.close();
  });
  return container;
}

void main() {
  test('old pagination cannot overwrite a newly selected view', () async {
    final pending = Completer<(RequestOptions, RequestInterceptorHandler)>();
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.queryParameters['page'] == 2) {
            pending.complete((options, handler));
          } else {
            handler.resolve(
              _page(
                options,
                options.queryParameters['state'] == 'snoozed' ? [90] : [1],
              ),
            );
          }
        },
      ),
    );
    final container = _container(dio);
    await container.read(discoveryFeedProvider.future);
    final actions = container.read(discoveryFeedProvider.notifier);
    final load = actions.loadMore();
    final (options, handler) = await pending.future;
    await actions.showView(DiscoveryFeedView.later);
    handler.resolve(_page(options, [2]));
    await load;
    expect(actions.view, DiscoveryFeedView.later);
    expect(
      container
          .read(discoveryFeedProvider)
          .requireValue
          .items
          .map((item) => item.id),
      [90],
    );
  });

  for (final switchView in [false, true]) {
    test(
      'failed item rollback respects other actions and query (switch=$switchView)',
      () async {
        final pending =
            Completer<(RequestOptions, RequestInterceptorHandler)>();
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.method == 'GET') {
                handler.resolve(
                  _page(
                    options,
                    options.queryParameters['state'] == 'snoozed'
                        ? [90]
                        : [1, 2],
                  ),
                );
              } else if (options.path.endsWith('/1')) {
                pending.complete((options, handler));
              } else {
                handler.resolve(
                  Response(requestOptions: options, data: {'id': 2}),
                );
              }
            },
          ),
        );
        final container = _container(dio);
        await container.read(discoveryFeedProvider.future);
        final actions = container.read(discoveryFeedProvider.notifier);
        final action = actions.actOnItem(1, stateValue: 'snoozed');
        final failure = expectLater(action, throwsA(isA<DioException>()));
        final (options, handler) = await pending.future;
        await actions.actOnItem(2, stateValue: 'ignored');
        if (switchView) await actions.showView(DiscoveryFeedView.later);
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        );
        await failure;
        expect(
          container
              .read(discoveryFeedProvider)
              .requireValue
              .items
              .map((item) => item.id),
          switchView ? [90] : [1],
        );
      },
    );
  }
}
