import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/features/collection/providers/collection_provider.dart';
import 'package:frontend/features/collection/widgets/detail/components/post_processing_status_panel.dart';

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
          home: Scaffold(body: PostProcessingStatusPanel(contentId: contentId)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('处理状态'), findsOneWidget);
    expect(find.text('生成摘要'), findsOneWidget);
    expect(find.text('重建索引'), findsOneWidget);
    expect(find.text('重试分发'), findsOneWidget);
    expect(find.text('巡逻评分'), findsOneWidget);
    expect(find.text('未评分'), findsOneWidget);
    expect(find.text('失败详情'), findsNWidgets(2));
    expect(find.textContaining('embedding api unavailable'), findsOneWidget);
    expect(find.textContaining('telegram rate limited'), findsOneWidget);
  });
}
