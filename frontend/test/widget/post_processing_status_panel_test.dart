import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/collection/models/processing_status.dart';
import 'package:frontend/features/collection/providers/collection_provider.dart';
import 'package:frontend/features/collection/widgets/detail/components/post_processing_status_panel.dart';
import 'package:mockito/mockito.dart';

/// 记录所有写请求，用于断言面板确实经由控制层调用了正确的端点。
class _RecordingDio extends Mock implements Dio {
  final postPaths = <String>[];
  final postBodies = <Object?>[];

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
    postBodies.add(data);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'status': 'success', 'run_id': 'run-1'} as T,
    );
  }
}

ContentProcessingStatus _status({
  required int contentId,
  required ProcessingStageState overall,
  required List<ProcessingStage> stages,
}) {
  return ContentProcessingStatus(
    contentId: contentId,
    contentStatus: 'parse_success',
    state: overall,
    stages: stages,
  );
}

Widget _host(int contentId, ContentProcessingStatus status, {Dio? dio}) {
  return ProviderScope(
    overrides: [
      if (dio != null) apiClientProvider.overrideWithValue(dio),
      contentProcessingStatusProvider(
        contentId,
      ).overrideWith((ref) async => status),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PostProcessingStatusPanel(
            contentId: contentId,
            initiallyExpanded: true,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('规范化状态与失败详情按 typed contract 渲染', (tester) async {
    const contentId = 7;
    final status = _status(
      contentId: contentId,
      overall: ProcessingStageState.failed,
      stages: [
        const ProcessingStage(
          key: ProcessingStageKey.summary,
          label: '摘要',
          state: ProcessingStageState.blocked,
          detailState: 'unavailable',
          message: '摘要模型密钥未配置',
          issues: ['summary_api_key 未配置'],
          hints: ['在设置中配置摘要模型密钥'],
        ),
        const ProcessingStage(
          key: ProcessingStageKey.semanticIndex,
          label: '语义索引',
          state: ProcessingStageState.partial,
          detailState: 'partial',
          message: '1 个分块已索引，1 个失败',
          completedUnits: 1,
          totalUnits: 2,
          failuresTotal: 1,
          failures: [
            ProcessingStageFailure(
              id: 44,
              reference: '分块 1',
              reason: 'embedding api unavailable',
              retryCount: 2,
            ),
          ],
        ),
        const ProcessingStage(
          key: ProcessingStageKey.distribution,
          label: '分发',
          state: ProcessingStageState.notApplicable,
          detailState: 'not_matched',
          message: '暂未匹配分发规则',
        ),
      ],
    );

    await tester.pumpWidget(_host(contentId, status));
    await tester.pumpAndSettle();

    expect(find.text('处理状态'), findsOneWidget);
    // 阶段状态使用规范化标签，而不是后端的具体状态字符串
    expect(find.text('受阻'), findsOneWidget);
    expect(find.text('部分完成'), findsWidgets);
    expect(find.text('不适用'), findsOneWidget);
    // 具体条件仍以文案形式保留，供诊断使用
    expect(find.text('摘要模型密钥未配置'), findsOneWidget);
    expect(find.text('summary_api_key 未配置'), findsOneWidget);
    expect(find.text('在设置中配置摘要模型密钥'), findsOneWidget);
    expect(find.text('失败详情 (1)'), findsOneWidget);
    // 部分完成时显示进度
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('没有 typed action 的阶段不渲染任何可执行按钮', (tester) async {
    const contentId = 8;
    final status = _status(
      contentId: contentId,
      overall: ProcessingStageState.failed,
      stages: [
        const ProcessingStage(
          key: ProcessingStageKey.semanticIndex,
          label: '语义索引',
          state: ProcessingStageState.failed,
          detailState: 'failed',
          message: '语义索引生成失败',
          issues: ['embedding_api_key 未配置'],
          hints: ['配置 Embedding 密钥'],
          failuresTotal: 1,
          failures: [
            ProcessingStageFailure(id: 1, reason: 'embedding api unavailable'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_host(contentId, status));
    await tester.pumpAndSettle();

    // 后端未声明动作时前端不得自行推断出"重建索引"之类的按钮
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('失败详情 (1)'), findsOneWidget);
  });

  testWidgets('有外部副作用的动作必须先确认再调用控制层', (tester) async {
    const contentId = 11;
    final dio = _RecordingDio();
    final status = _status(
      contentId: contentId,
      overall: ProcessingStageState.pending,
      stages: [
        const ProcessingStage(
          key: ProcessingStageKey.patrol,
          label: '巡逻评分',
          state: ProcessingStageState.pending,
          detailState: 'pending',
          message: '等待巡逻评分',
          actions: [
            ProcessingStageAction(
              kind: ProcessingActionKind.patrolScore,
              label: '触发巡逻评分',
              externalEffect: true,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_host(contentId, status, dio: dio));
    await tester.pumpAndSettle();

    await tester.tap(find.text('触发巡逻评分'));
    await tester.pumpAndSettle();

    // 确认对话框出现前不得发出任何请求
    expect(dio.postPaths, isEmpty);
    expect(find.textContaining('会产生模型调用成本'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(dio.postPaths, contains('/contents/$contentId/patrol-score'));
    expect(find.text('查看日志'), findsOneWidget);
  });

  testWidgets('取消确认后不执行有外部副作用的动作', (tester) async {
    const contentId = 12;
    final dio = _RecordingDio();
    final status = _status(
      contentId: contentId,
      overall: ProcessingStageState.failed,
      stages: [
        const ProcessingStage(
          key: ProcessingStageKey.distribution,
          label: '分发',
          state: ProcessingStageState.failed,
          detailState: 'failed',
          message: '存在失败或被过滤的分发队列项',
          actions: [
            ProcessingStageAction(
              kind: ProcessingActionKind.retryDistributionItem,
              label: '重试失败分发',
              externalEffect: true,
              targetIds: [9, 10],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_host(contentId, status, dio: dio));
    await tester.pumpAndSettle();

    await tester.tap(find.text('重试失败分发'));
    await tester.pumpAndSettle();
    expect(find.textContaining('对外发送操作'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(dio.postPaths, isEmpty);
  });

  testWidgets('分发重试使用批量端点并携带后端给出的目标 id', (tester) async {
    const contentId = 13;
    final dio = _RecordingDio();
    final status = _status(
      contentId: contentId,
      overall: ProcessingStageState.failed,
      stages: [
        const ProcessingStage(
          key: ProcessingStageKey.distribution,
          label: '分发',
          state: ProcessingStageState.failed,
          detailState: 'failed',
          message: '存在失败或被过滤的分发队列项',
          actions: [
            ProcessingStageAction(
              kind: ProcessingActionKind.retryDistributionItem,
              label: '重试失败分发',
              externalEffect: true,
              targetIds: [9, 10],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_host(contentId, status, dio: dio));
    await tester.pumpAndSettle();

    await tester.tap(find.text('重试失败分发'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(dio.postPaths, ['/distribution-queue/batch-retry']);
    expect(dio.postBodies.single, {
      'item_ids': [9, 10],
    });
  });
}
