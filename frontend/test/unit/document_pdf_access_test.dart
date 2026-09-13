import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/collection/providers/document_pdf_provider.dart';

void main() {
  for (final status in [200, 403]) {
    test(
      'PDF resource isolates API credentials and stops at authorization denial ($status)',
      () async {
        final dio = Dio(
          BaseOptions(headers: {'X-API-Token': 'test-control-only'}),
        );
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(options.path, '/media/assets/7/manifest');
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'id': 7,
                    'content_id': 1,
                    'media_type': 'document',
                    'role': 'attachment',
                    'sources': [
                      for (final name in ['first', 'second'])
                        {
                          'url': 'https://example.com/$name',
                          'source_kind': 'remote_direct',
                          'mime_type': 'application/pdf',
                        },
                    ],
                  },
                ),
              );
            },
          ),
        );
        final requested = <String>[];
        await http.runWithClient(
          () async {
            final container = ProviderContainer(
              overrides: [apiClientProvider.overrideWithValue(dio)],
            );
            addTearDown(container.dispose);
            final subscription = container.listen(
              documentPdfProvider(7),
              (_, _) {},
            );
            addTearDown(subscription.close);
            final result = container.read(documentPdfProvider(7).future);
            if (status == 403) {
              await expectLater(
                result,
                throwsA(isA<DocumentPdfReadException>()),
              );
            } else {
              expect(String.fromCharCodes(await result), '%PDF-fixture');
            }
          },
          () => MockClient((request) async {
            expect(
              request.headers.keys.map((key) => key.toLowerCase()),
              isNot(contains('x-api-token')),
            );
            expect(
              request.headers.keys.map((key) => key.toLowerCase()),
              isNot(contains('authorization')),
            );
            requested.add(request.url.path);
            return http.Response('%PDF-fixture', status);
          }),
        );
        expect(requested, ['/first']);
      },
    );
  }
  for (final scenario in ['expired', 'still-expired', 'missing']) {
    test('PDF candidate recovery: $scenario', () async {
      final dio = Dio();
      var manifests = 0;
      var reports = 0;
      final paths = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST') {
              expect(options.path, '/media/assets/7/failures');
              expect(options.data, {
                'variant_id': 13,
                'error_code': 'media_blob_missing',
              });
              reports++;
              handler.resolve(
                Response(requestOptions: options, statusCode: 200),
              );
              return;
            }
            manifests++;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'id': 7,
                  'content_id': 1,
                  'media_type': 'document',
                  'role': 'attachment',
                  'sources': [
                    {
                      'url': 'https://example.com/local',
                      'source_kind': 'local_signed',
                      'variant_id': 13,
                      'mime_type': 'application/pdf',
                    },
                    if (scenario == 'missing')
                      {
                        'url': 'https://example.com/remote',
                        'source_kind': 'remote_direct',
                        'mime_type': 'application/pdf',
                      },
                  ],
                },
              ),
            );
          },
        ),
      );
      await http.runWithClient(
        () async {
          final container = ProviderContainer(
            overrides: [apiClientProvider.overrideWithValue(dio)],
          );
          final subscription = container.listen(
            documentPdfProvider(7),
            (_, _) {},
          );
          try {
            final result = container.read(documentPdfProvider(7).future);
            if (scenario == 'still-expired') {
              await expectLater(
                result,
                throwsA(isA<DocumentPdfReadException>()),
              );
            } else {
              expect(String.fromCharCodes(await result), '%PDF-fixture');
            }
          } finally {
            subscription.close();
            container.dispose();
          }
        },
        () => MockClient((request) async {
          paths.add(request.url.path);
          final status = scenario == 'missing'
              ? (request.url.path == '/local' ? 404 : 200)
              : (scenario == 'still-expired' || paths.length == 1 ? 410 : 200);
          return http.Response('%PDF-fixture', status);
        }),
      );
      expect(
        paths,
        scenario == 'missing' ? ['/local', '/remote'] : ['/local', '/local'],
      );
      expect(manifests, scenario == 'missing' ? 1 : 2);
      expect(reports, scenario == 'missing' ? 1 : 0);
    });
  }
}
