import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/providers/local_settings_provider.dart';

class _Settings extends LocalSettings {
  int clearCount = 0;
  @override
  LocalSettingsState build() => LocalSettingsState(
    baseUrl: 'http://example.test/api/v1',
    apiToken: 'old-test-token',
  );
  @override
  Future<void> clearAuth() async {
    clearCount++;
    state = state.copyWith(apiToken: '');
  }

  @override
  Future<void> setApiToken(String token) async =>
      state = state.copyWith(apiToken: token);
}

class _Adapter implements HttpClientAdapter {
  final started = Completer<void>();
  final response = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    started.complete();
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final replaceToken in [false, true]) {
    test(
      'invalid token recovery respects newer credentials ($replaceToken)',
      () async {
        final settings = _Settings();
        final container = ProviderContainer(
          overrides: [localSettingsProvider.overrideWith(() => settings)],
        );
        final subscription = container.listen(apiClientProvider, (_, _) {});
        addTearDown(() {
          subscription.close();
          container.dispose();
        });
        final dio = container.read(apiClientProvider);
        final adapter = _Adapter();
        dio.httpClientAdapter = adapter;
        final future = dio.get('/notifications');
        await adapter.started.future;
        if (replaceToken) {
          await settings.setApiToken('new-test-token');
          container.read(apiClientProvider);
        }
        adapter.response.complete(
          ResponseBody.fromString(
            '{"error_code":"invalid_api_token","error_message":"Invalid or missing API Token"}',
            401,
            headers: {
              'content-type': ['application/json'],
            },
          ),
        );
        await expectLater(future, throwsA(isA<DioException>()));
        expect(settings.clearCount, replaceToken ? 0 : 1);
        expect(
          container.read(localSettingsProvider).apiToken,
          replaceToken ? 'new-test-token' : '',
        );
      },
    );
  }
}
