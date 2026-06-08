import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/features/dashboard/models/stats.dart';
import 'package:frontend/features/dashboard/providers/dashboard_provider.dart';
import 'package:frontend/features/dashboard/task_result_page.dart';

void main() {
  testWidgets('TaskResultPage renders success run', (tester) async {
    await _pumpRun(
      tester,
      BackgroundTaskRun.fromJson({
        'run_id': 'success-run-1',
        'task': 'favorites_sync',
        'status': 'success',
        'trigger': 'manual',
        'platform': 'zhihu',
        'result': {'imported': 2},
      }),
    );

    expect(find.text('任务结果'), findsOneWidget);
    expect(find.text('favorites_sync'), findsOneWidget);
    expect(find.text('成功'), findsOneWidget);
    expect(find.textContaining('imported'), findsOneWidget);
  });

  testWidgets('TaskResultPage renders running run', (tester) async {
    await _pumpRun(
      tester,
      BackgroundTaskRun.fromJson({
        'run_id': 'running-run-1',
        'task': 'discovery_sync',
        'status': 'running',
        'trigger': 'manual',
        'source_id': 7,
      }),
    );

    expect(find.text('discovery_sync'), findsOneWidget);
    expect(find.text('运行中'), findsOneWidget);
    expect(find.textContaining('source_id'), findsWidgets);
  });

  testWidgets('TaskResultPage renders failed run', (tester) async {
    await _pumpRun(
      tester,
      BackgroundTaskRun.fromJson({
        'run_id': 'failed-run-1',
        'task': 'platform_parse_test',
        'status': 'error',
        'trigger': 'manual',
        'platform': 'zhihu',
        'error': 'parse failed',
        'result': {'url': 'https://example.com/post'},
      }),
    );

    expect(find.text('platform_parse_test'), findsOneWidget);
    expect(find.text('失败'), findsOneWidget);
    expect(find.text('parse failed'), findsOneWidget);
    expect(find.textContaining('example.com'), findsOneWidget);
  });
}

Future<void> _pumpRun(WidgetTester tester, BackgroundTaskRun run) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backgroundTaskRunProvider(run.runId).overrideWith((ref) async => run),
      ],
      child: MaterialApp(home: TaskResultPage(runId: run.runId)),
    ),
  );
  await tester.pumpAndSettle();
}
