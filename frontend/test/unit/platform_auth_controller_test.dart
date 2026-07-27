import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/settings/providers/platform_auth_controller.dart';
import 'package:mockito/mockito.dart';

class _MockDio extends Mock implements Dio {
  final requests = <String>[];

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
    requests.add('POST $path');
    final body = path.endsWith('/check')
        ? {'is_valid': true, 'platform': 'bilibili'}
        : {
            'session_id': 'session-1',
            'platform': 'bilibili',
            'status': 'waiting_scan',
            'message': '请扫码',
          };
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body as T,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    requests.add('DELETE $path');
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'status': 'success'} as T,
    );
  }
}

void main() {
  test('platform auth actions use browser-auth contract', () async {
    final dio = _MockDio();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(dio)],
    );
    addTearDown(container.dispose);
    final actions = container.read(platformAuthActionsProvider.notifier);

    final session = await actions.startSession('bilibili');
    final checked = await actions.check('bilibili');
    await actions.cancelSession(session.sessionId);
    await actions.logout('bilibili');

    expect(session.status, 'waiting_scan');
    expect(checked.isValid, isTrue);
    expect(dio.requests, [
      'POST /browser-auth/session/bilibili',
      'POST /browser-auth/bilibili/check',
      'DELETE /browser-auth/session/session-1',
      'DELETE /browser-auth/bilibili',
    ]);
    expect(container.read(platformAuthActionsProvider), isEmpty);
  });
}
