import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/dashboard/dashboard_page.dart';
import 'package:frontend/features/discovery/models/discovery_models.dart';
import 'package:frontend/features/discovery/providers/discovery_stats_provider.dart';

void main() {
  testWidgets('DashboardPage renders content-focused feed transition', (
    tester,
  ) async {
    final mockDiscovery = DiscoveryStats(
      total: 12,
      byState: {'ingested': 2, 'scored': 3, 'visible': 4, 'ignored': 3},
      bySource: {'rss': 9, 'favorites_sync': 3},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discoveryStatsProvider.overrideWith(
            (ref) => Future.value(mockDiscovery),
          ),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('动态正在从系统仪表盘过渡为个人信息流'), findsOneWidget);
    expect(find.text('推荐候选'), findsWidgets);
    expect(find.text('查看候选'), findsOneWidget);
    expect(find.text('总计'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    expect(find.text('待处理动态'), findsNothing);
    expect(find.text('最近任务摘要'), findsNothing);
    expect(find.text('最近后台运行'), findsNothing);
    expect(find.text('系统概览'), findsNothing);
    expect(find.text('队列状态'), findsNothing);
    expect(find.text('平台分布'), findsNothing);
    expect(find.text('最近 7 天增长'), findsNothing);
    expect(find.byType(GridView), findsNothing);
  });
}
