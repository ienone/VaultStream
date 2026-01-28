import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:mockito/mockito.dart';

class MockDio extends Mock implements Dio {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    // Return empty success response for all gets
    return Future.value(Response(
      requestOptions: RequestOptions(path: path),
      data: null, // Return null or empty dict depending on expected T
      statusCode: 200,
    ));
  }
}

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Set a large enough screen size to avoid overflow in Dashboard grid
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Build our app and trigger a frame.
    // Override apiClientProvider to prevent real network calls
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => MockDio()),
        ],
        child: const VaultStreamApp(),
      ),
    );
    await tester.pumpAndSettle(); // Wait for animations and futures

    // Verify that we are on the dashboard
    expect(find.text('Dashboard'), findsAny);
  });
}
