import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/review/models/distribution_target.dart';
import 'package:frontend/features/review/providers/distribution_targets_provider.dart';

class MockDio extends Mock implements Dio {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (path.contains('/targets')) {
      return Response(
        requestOptions: RequestOptions(path: path),
        data: [
          {
            'id': 1,
            'rule_id': 1,
            'bot_chat_id': 10,
            'enabled': true,
            'merge_forward': false,
            'use_author_name': true,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }
        ] as T,
        statusCode: 200,
      );
    }
    throw UnimplementedError();
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
    return Response(
      requestOptions: RequestOptions(path: path),
      data: {
        'id': 2,
        'rule_id': 1,
        'bot_chat_id': 11,
        'enabled': true,
        'merge_forward': false,
        'use_author_name': true,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      } as T,
      statusCode: 201,
    );
  }
}

void main() {
  late ProviderContainer container;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockDio),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('DistributionTargetsProvider Tests', () {
    test('fetches distribution targets', () async {
      final targets = await container.read(distributionTargetsProvider(1).future);
      
      expect(targets, isA<List<DistributionTarget>>());
      expect(targets.length, 1);
      expect(targets.first.id, 1);
      expect(targets.first.botChatId, 10);
    });

    test('creates a distribution target', () async {
      const create = DistributionTargetCreate(
        botChatId: 11,
      );
      
      final target = await container
          .read(distributionTargetsProvider(1).notifier)
          .createTarget(1, create);
          
      expect(target.id, 2);
      expect(target.botChatId, 11);
    });
  });
}
