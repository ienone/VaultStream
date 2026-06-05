import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/settings/providers/settings_provider.dart';
import 'package:mockito/mockito.dart';

class _MockDio extends Mock implements Dio {
  final postPaths = <String>[];
  Object? lastData;

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
    postPaths.add(path);
    lastData = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'ok': true, 'run_id': 'ai-test-run', 'target': 'text_llm'} as T,
    );
  }
}

void main() {
  test('aiConnectivityTestProvider posts target to backend', () async {
    final dio = _MockDio();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(dio)],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(aiConnectivityTestProvider)
        .run('text_llm');

    expect(dio.postPaths, ['/ai/connectivity-test']);
    expect(dio.lastData, {'target': 'text_llm'});
    expect(result['ok'], isTrue);
    expect(result['run_id'], 'ai-test-run');
  });
}
