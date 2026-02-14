import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/features/dashboard/dashboard_page.dart';
import 'package:frontend/features/dashboard/providers/dashboard_provider.dart';
import 'package:frontend/features/dashboard/models/stats.dart';

// Create a mock for the provider state if needed, or better, override the provider with a known state.

void main() {
  testWidgets('DashboardPage renders stats correctly (Portrait Mobile)', (WidgetTester tester) async {
    // Set screen size to portrait mobile
    tester.view.physicalSize = const Size(1080, 2400); // Pixel 4 ish
    tester.view.devicePixelRatio = 2.0;

    // Mock data
    final mockStats = DashboardStats(
      platformCounts: {'twitter': 10, 'bilibili': 5},
      dailyGrowth: [],
      storageUsageBytes: 1024 * 1024 * 100, // 100 MB
    );

    final mockQueue = QueueOverviewStats(
      parse: QueueStats(
        unprocessed: 2,
        processing: 1,
        parseSuccess: 15,
        parseFailed: 0,
        total: 18,
      ),
      distribution: DistributionStats(
        willPush: 3,
        filtered: 2,
        pendingReview: 1,
        pushed: 12,
        total: 18,
      ),
    );
    
    final mockHealth = SystemHealth(
        status: 'ok',
        queueSize: 0,
        components: {'db': 'ok', 'redis': 'ok'}
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardStatsProvider.overrideWith((ref) => Future.value(mockStats)),
          queueStatsProvider.overrideWith((ref) => Future.value(mockQueue)),
          systemHealthProvider.overrideWith((ref) => Future.value(mockHealth)),
        ],
        child: const MaterialApp(
          home: DashboardPage(),
        ),
      ),
    );

    // Pump to resolve futures
    await tester.pumpAndSettle();

    // Verify system overview
    expect(find.text('系统概览'), findsOneWidget);
    expect(find.text('总内容'), findsOneWidget);
    expect(find.text('15'), findsOneWidget); // Total content count
    
    // Verify responsive layout
    // In portrait, we expect 2 columns for grid
    final gridFinder = find.byType(GridView);
    final grid = tester.widget<GridView>(gridFinder);
    final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);

    // Reset view
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('DashboardPage renders stats correctly (Landscape Desktop)', (WidgetTester tester) async {
    // Set screen size to landscape desktop
    tester.view.physicalSize = const Size(3840, 2160);
    tester.view.devicePixelRatio = 2.0;

    // Mock data (same as above)
    final mockStats = DashboardStats(
      platformCounts: {'twitter': 10, 'bilibili': 5},
      dailyGrowth: [],
      storageUsageBytes: 1024 * 1024 * 100,
    );

    final mockQueue = QueueOverviewStats(
      parse: QueueStats(
        unprocessed: 2,
        processing: 1,
        parseSuccess: 15,
        parseFailed: 0,
        total: 18,
      ),
      distribution: DistributionStats(
        willPush: 3,
        filtered: 2,
        pendingReview: 1,
        pushed: 12,
        total: 18,
      ),
    );
    
    final mockHealth = SystemHealth(
        status: 'ok',
        queueSize: 0,
        components: {'db': 'ok', 'redis': 'ok'}
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardStatsProvider.overrideWith((ref) => Future.value(mockStats)),
          queueStatsProvider.overrideWith((ref) => Future.value(mockQueue)),
          systemHealthProvider.overrideWith((ref) => Future.value(mockHealth)),
        ],
        child: const MaterialApp(
          home: DashboardPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify 4 columns for grid in desktop
    final gridFinder = find.byType(GridView);
    final grid = tester.widget<GridView>(gridFinder);
    final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);

    addTearDown(tester.view.resetPhysicalSize);
  });
}
