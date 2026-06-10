import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/discovery/providers/discovery_actions_provider.dart';
import 'package:mockito/mockito.dart';

class _DelayedMockDio extends Mock implements Dio {
  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }
}

class _RecordingDio extends Mock implements Dio {
  String? lastPath;
  Object? lastData;

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    lastPath = path;
    lastData = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    lastPath = path;
    lastData = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }
}

void main() {
  test('promoteItem completes after provider container disposal', () async {
    final mockDio = _DelayedMockDio();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(mockDio)],
    );

    final future = container
        .read(discoveryActionsProvider.notifier)
        .promoteItem(1);
    container.dispose();

    await expectLater(future, completes);
  });

  test('snooze and bulk actions send closed-loop states', () async {
    final dio = _RecordingDio();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(dio)],
    );
    addTearDown(container.dispose);

    await container.read(discoveryActionsProvider.notifier).snoozeItem(7);

    expect(dio.lastPath, '/discovery/items/7');
    expect(dio.lastData, {'state': 'snoozed'});

    await container.read(discoveryActionsProvider.notifier).bulkAction({
      7,
    }, 'snooze');

    expect(dio.lastPath, '/discovery/items/bulk-action');
    expect(dio.lastData, {
      'ids': [7],
      'action': 'snooze',
    });
  });
}
