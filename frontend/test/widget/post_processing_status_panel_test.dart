import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/collection/providers/collection_provider.dart';
import 'package:frontend/features/collection/widgets/detail/components/post_processing_status_panel.dart';
import 'package:mockito/mockito.dart';

class _RecordingDio extends Mock implements Dio {
  final postPaths = <String>[];

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
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'status': 'success', 'run_id': 'run-patrol-1'} as T,
    );
  }
}

void main() {
  testWidgets('PostProcessingStatusPanel exposes failures and retry actions', (
    tester,
  ) async {
    const contentId = 7;
    final status = {
      'content_id': contentId,
      'stages': [
        {
          'key': 'summary',
          'label': '摘要',
          'status': 'pending',
          'message': '尚未生成摘要',
          'details': {},
        },
        {
          'key': 'semantic_index',
          'label': '语义索引',
          'status': 'failed',
          'message': '语义索引生成失败',
          'issues': ['embedding_api_key 未配置'],
          'actions': ['配置 Embedding 密钥'],
          'details': {
            'failures': [
              {
                'id': 1,
                'failure_reason': 'embedding api unavailable',
                'retry_count': 2,
              },
            ],
          },
        },
        {
          'key': 'distribution',
          'label': '分发',
          'status': 'failed',
          'message': '存在失败或被过滤的分发队列项',
          'issues': ['存在失败或被过滤的分发队列项'],
          'actions': ['查看失败详情并重试失败分发项'],
          'details': {
            'failures': [
              {
                'id': 9,
                'last_error': 'telegram rate limited',
                'last_error_type': 'rate_limit',
              },
            ],
          },
        },
        {
          'key': 'patrol',
          'label': '巡逻评分',
          'status': 'not_scored',
          'message': '未记录巡逻评分',
          'issues': ['未配置可用于巡逻评分的 LLM 密钥'],
          'actions': ['配置 text_llm_api_key 或 vision_llm_api_key'],
          'details': {'discovery_state': 'visible'},
        },
      ],
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentProcessingStatusProvider(
            contentId,
          ).overrideWith((ref) async => status),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PostProcessingStatusPanel(contentId: contentId),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('处理状态'), findsOneWidget);
    expect(find.text('生成摘要'), findsOneWidget);
    expect(find.text('重建索引'), findsOneWidget);
    expect(find.text('重试分发'), findsOneWidget);
    expect(find.text('触发评分'), findsOneWidget);
    expect(find.text('巡逻评分'), findsOneWidget);
    expect(find.text('未评分'), findsOneWidget);
    expect(find.text('失败详情'), findsNWidgets(2));
    expect(find.textContaining('问题: embedding_api_key 未配置'), findsOneWidget);
    expect(find.textContaining('建议: 配置 Embedding 密钥'), findsOneWidget);
    expect(find.textContaining('配置 text_llm_api_key'), findsOneWidget);
    expect(find.textContaining('embedding api unavailable'), findsOneWidget);
    expect(find.textContaining('telegram rate limited'), findsOneWidget);
  });

  testWidgets('PostProcessingStatusPanel can trigger manual patrol scoring', (
    tester,
  ) async {
    const contentId = 11;
    final dio = _RecordingDio();
    final status = {
      'content_id': contentId,
      'stages': [
        {
          'key': 'patrol',
          'label': '巡逻评分',
          'status': 'pending',
          'message': '等待巡逻评分',
          'issues': [],
          'actions': ['等待 discovery_patrol 后台任务或手动触发巡逻评分'],
          'details': {
            'discovery_state': 'ingested',
            'text_llm_configured': true,
            'vision_llm_configured': false,
          },
        },
      ],
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(dio),
          contentProcessingStatusProvider(
            contentId,
          ).overrideWith((ref) async => status),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PostProcessingStatusPanel(contentId: contentId),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('触发评分'));
    await tester.pump();

    expect(dio.postPaths, contains('/contents/$contentId/patrol-score'));
    expect(find.text('查看日志'), findsOneWidget);
  });
}
