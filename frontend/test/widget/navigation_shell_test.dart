import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/providers/local_settings_provider.dart';
import 'package:frontend/core/providers/system_status_provider.dart';
import 'package:frontend/features/dashboard/models/stats.dart';
import 'package:frontend/features/dashboard/providers/dashboard_provider.dart';
import 'package:frontend/features/discovery/models/discovery_models.dart';
import 'package:frontend/features/discovery/providers/discovery_stats_provider.dart';
import 'package:frontend/main.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return Future.value(
      Response<T>(requestOptions: RequestOptions(path: path), statusCode: 200),
    );
  }
}

class _TestSystemStatusNotifier extends SystemStatusNotifier {
  @override
  Future<SystemStatus> build() async => SystemStatus(isLoaded: true);
}

void main() {
  testWidgets('mobile shell keeps three primary destinations', (tester) async {
    configureRuntimeAssets();
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);

    SharedPreferences.setMockInitialValues({});
    if (!isSharedPrefsInitialized) {
      sharedPrefs = await SharedPreferences.getInstance();
    }

    tester.view.physicalSize = const Size(1520, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localSettingsProvider.overrideWithValue(
            LocalSettingsState(baseUrl: 'http://localhost', apiToken: 'token'),
          ),
          systemStatusProvider.overrideWith(_TestSystemStatusNotifier.new),
          apiClientProvider.overrideWith((ref) => _MockDio()),
          dashboardStatsProvider.overrideWith(
            (ref) async => const DashboardStats(
              platformCounts: {},
              dailyGrowth: [],
              storageUsageBytes: 0,
            ),
          ),
          queueStatsProvider.overrideWith(
            (ref) async => const QueueOverviewStats(
              parse: QueueStats(
                unprocessed: 0,
                processing: 0,
                parseSuccess: 0,
                parseFailed: 0,
                total: 0,
              ),
              distribution: DistributionStats(
                willPush: 0,
                filtered: 0,
                pushed: 0,
                total: 0,
              ),
            ),
          ),
          systemHealthProvider.overrideWith(
            (ref) async =>
                const SystemHealth(status: 'ok', queueSize: 0, components: {}),
          ),
          discoveryStatsProvider.overrideWith(
            (ref) async =>
                const DiscoveryStats(total: 0, byState: {}, bySource: {}),
          ),
          backgroundTaskDiagnosticsProvider.overrideWith(
            (ref) async => BackgroundTaskDiagnostics.fromJson({
              'summary': {},
              'task_states': [],
              'failed_parse_tasks': [],
              'failed_distribution_items': [],
              'failed_discovery_sources': [],
              'recent_task_runs': [],
            }),
          ),
        ],
        child: const VaultStreamApp(),
      ),
    );

    await tester.pumpAndSettle();

    final navigationBar = find.byType(NavigationBar);
    expect(
      find.descendant(
        of: navigationBar,
        matching: find.byType(NavigationDestination),
      ),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: navigationBar, matching: find.text('动态')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigationBar, matching: find.text('收藏库')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigationBar, matching: find.text('自动化')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigationBar, matching: find.text('收件箱')),
      findsNothing,
    );
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Agent'), findsNothing);
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通知中心'));
    await tester.pumpAndSettle();

    expect(find.text('通知中心'), findsWidgets);
    expect(find.text('Agent 工作台'), findsNothing);
    expect(find.text('账号中心'), findsNothing);
  });
}
