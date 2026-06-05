import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/discovery/models/discovery_models.dart';
import 'package:frontend/features/discovery/providers/discovery_sources_provider.dart';
import 'package:frontend/features/review/models/bot_chat.dart';
import 'package:frontend/features/review/models/distribution_rule.dart';
import 'package:frontend/features/review/models/queue_item.dart';
import 'package:frontend/features/review/providers/bot_chats_provider.dart';
import 'package:frontend/features/review/providers/distribution_rules_provider.dart';
import 'package:frontend/features/review/providers/queue_provider.dart';
import 'package:frontend/features/review/review_page.dart';
import 'package:frontend/features/settings/providers/favorites_sync_provider.dart';
import 'package:frontend/features/settings/providers/platform_health_provider.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:mockito/mockito.dart';

class MockDio extends Mock implements Dio {
  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return Future.value(
      Response(
        requestOptions: RequestOptions(path: path),
        data: {'status': 'success'} as T,
        statusCode: 200,
      ),
    );
  }

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
      Response(
        requestOptions: RequestOptions(path: path),
        data: null as T,
        statusCode: 200,
      ),
    );
  }
}

void main() {
  group('ReviewPage Widget Tests', () {
    testWidgets('ReviewPage renders correctly with initial state', (
      WidgetTester tester,
    ) async {
      final mockDistributionRules = <DistributionRule>[];
      final mockQueueItems = <QueueItem>[];
      final mockBotChats = <BotChat>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            distributionRulesProvider.overrideWith(
              () => MockDistributionRules(mockDistributionRules),
            ),
            contentQueueProvider.overrideWith(
              () => MockContentQueue(mockQueueItems),
            ),
            queueStatsProvider(
              null,
            ).overrideWith((ref) => Future.value({'will_push': 0})),
            favoritesSyncStatusProvider.overrideWith(
              (ref) async => _mockFavoritesStatus(),
            ),
            platformHealthProvider.overrideWith(
              (ref) async => _mockPlatformHealth(),
            ),
            discoverySourcesProvider.overrideWith(
              () => MockDiscoverySources(_mockDiscoverySources()),
            ),
            botChatsProvider.overrideWith(() => MockBotChats(mockBotChats)),
            apiClientProvider.overrideWith((ref) => MockDio()),
          ],
          child: const MaterialApp(home: ReviewPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('自动化'), findsOneWidget);
      expect(find.text('分发队列'), findsOneWidget);
      expect(find.text('收藏同步'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('ReviewPage fetches and displays data', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockDistributionRules = [
        DistributionRule(
          id: 1,
          name: 'Rule 1',
          matchConditions: {},
          enabled: true,
          priority: 1,
          nsfwPolicy: 'block',
          approvalRequired: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];
      final mockQueueItems = [
        QueueItem(
          id: 1,
          contentId: 101,
          title: 'Item 1',
          platform: 'twitter',
          status: 'will_push',
        ),
      ];
      final mockBotChats = [
        BotChat(
          id: 1,
          botConfigId: 1,
          chatId: '123',
          chatType: 'group',
          title: 'Chat 1',
          enabled: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            distributionRulesProvider.overrideWith(
              () => MockDistributionRules(mockDistributionRules),
            ),
            contentQueueProvider.overrideWith(
              () => MockContentQueue(mockQueueItems),
            ),
            queueStatsProvider(
              null,
            ).overrideWith((ref) => Future.value({'will_push': 1})),
            favoritesSyncStatusProvider.overrideWith(
              (ref) async => _mockFavoritesStatus(),
            ),
            platformHealthProvider.overrideWith(
              (ref) async => _mockPlatformHealth(),
            ),
            discoverySourcesProvider.overrideWith(
              () => MockDiscoverySources(_mockDiscoverySources()),
            ),
            botChatsProvider.overrideWith(() => MockBotChats(mockBotChats)),
            apiClientProvider.overrideWith((ref) => MockDio()),
          ],
          child: const MaterialApp(home: ReviewPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.textContaining('待推送(1)'), findsAny);

      // Open dropdown to see Rule 1
      await tester.tap(find.byType(DropdownMenu<int?>));
      await tester.pumpAndSettle();
      expect(find.text('Rule 1').last, findsOneWidget);
    });

    testWidgets('ReviewPage exposes favorites sync automation tab', (
      WidgetTester tester,
    ) async {
      final mockDistributionRules = <DistributionRule>[];
      final mockQueueItems = <QueueItem>[];
      final mockBotChats = <BotChat>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            distributionRulesProvider.overrideWith(
              () => MockDistributionRules(mockDistributionRules),
            ),
            contentQueueProvider.overrideWith(
              () => MockContentQueue(mockQueueItems),
            ),
            queueStatsProvider(
              null,
            ).overrideWith((ref) => Future.value({'will_push': 0})),
            favoritesSyncStatusProvider.overrideWith(
              (ref) async => _mockFavoritesStatus(),
            ),
            platformHealthProvider.overrideWith(
              (ref) async => _mockPlatformHealth(),
            ),
            discoverySourcesProvider.overrideWith(
              () => MockDiscoverySources(_mockDiscoverySources()),
            ),
            botChatsProvider.overrideWith(() => MockBotChats(mockBotChats)),
            apiClientProvider.overrideWith((ref) => MockDio()),
          ],
          child: const MaterialApp(home: ReviewPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('收藏同步'));
      await tester.pumpAndSettle();

      expect(find.text('收藏同步总览'), findsOneWidget);
      expect(find.text('同步全部'), findsOneWidget);
      expect(find.text('预览同步'), findsWidgets);
      expect(find.text('同步策略'), findsOneWidget);
      expect(find.text('同步范围'), findsOneWidget);
      expect(find.text('取消收藏'), findsOneWidget);
      expect(find.text('同步间隔'), findsOneWidget);
      expect(find.text('单轮上限'), findsOneWidget);
      expect(find.text('360 分钟'), findsOneWidget);
      expect(find.text('50 条'), findsOneWidget);
      expect(find.text('高级参数'), findsOneWidget);
      expect(find.text('知乎'), findsWidgets);

      await tester.scrollUntilVisible(
        find.textContaining('abcdef12'),
        320,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('abcdef12'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.textContaining('abcdef12'));
      await tester.pumpAndSettle();

      expect(find.text('同步任务 abcdef12'), findsOneWidget);
      expect(find.text('结果摘要'), findsOneWidget);
      expect(find.text('需要登录'), findsOneWidget);
      expect(find.text('登录状态不可用，请先完成该平台登录'), findsOneWidget);
    });

    testWidgets('ReviewPage opens highlighted favorites sync run detail', (
      WidgetTester tester,
    ) async {
      final mockDistributionRules = <DistributionRule>[];
      final mockQueueItems = <QueueItem>[];
      final mockBotChats = <BotChat>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            distributionRulesProvider.overrideWith(
              () => MockDistributionRules(mockDistributionRules),
            ),
            contentQueueProvider.overrideWith(
              () => MockContentQueue(mockQueueItems),
            ),
            queueStatsProvider(
              null,
            ).overrideWith((ref) => Future.value({'will_push': 0})),
            favoritesSyncStatusProvider.overrideWith(
              (ref) async => _mockFavoritesStatus(),
            ),
            platformHealthProvider.overrideWith(
              (ref) async => _mockPlatformHealth(),
            ),
            discoverySourcesProvider.overrideWith(
              () => MockDiscoverySources(_mockDiscoverySources()),
            ),
            botChatsProvider.overrideWith(() => MockBotChats(mockBotChats)),
            apiClientProvider.overrideWith((ref) => MockDio()),
          ],
          child: const MaterialApp(
            home: ReviewPage(
              initialTab: 'favorites',
              highlightRunId: 'abcdef123456',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('收藏同步总览'), findsOneWidget);
      expect(find.text('同步任务 abcdef12'), findsOneWidget);
      expect(find.text('结果摘要'), findsOneWidget);
      expect(find.text('登录状态不可用，请先完成该平台登录'), findsOneWidget);
    });

    testWidgets('ReviewPage exposes automation health matrix', (
      WidgetTester tester,
    ) async {
      final mockDistributionRules = <DistributionRule>[];
      final mockQueueItems = <QueueItem>[];
      final mockBotChats = [
        BotChat(
          id: 2,
          botConfigId: 1,
          chatId: 'target-1',
          chatType: 'channel',
          title: 'Push Channel',
          enabled: true,
          isPushTarget: true,
          isAccessible: false,
          syncError: 'bot lost access',
          createdAt: DateTime(2026, 6, 6),
          updatedAt: DateTime(2026, 6, 6),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            distributionRulesProvider.overrideWith(
              () => MockDistributionRules(mockDistributionRules),
            ),
            contentQueueProvider.overrideWith(
              () => MockContentQueue(mockQueueItems),
            ),
            queueStatsProvider(
              null,
            ).overrideWith((ref) => Future.value({'will_push': 0})),
            favoritesSyncStatusProvider.overrideWith(
              (ref) async => _mockFavoritesStatus(),
            ),
            platformHealthProvider.overrideWith(
              (ref) async => _mockPlatformHealth(),
            ),
            discoverySourcesProvider.overrideWith(
              () => MockDiscoverySources(_mockDiscoverySources()),
            ),
            botChatsProvider.overrideWith(() => MockBotChats(mockBotChats)),
            apiClientProvider.overrideWith((ref) => MockDio()),
          ],
          child: const MaterialApp(home: ReviewPage(initialTab: 'health')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('平台账号'), findsOneWidget);
      expect(find.text('发现源'), findsOneWidget);
      expect(find.text('推送目标'), findsOneWidget);
      expect(find.text('知乎'), findsOneWidget);
      expect(find.text('Tech RSS'), findsOneWidget);
      expect(find.text('Push Channel'), findsOneWidget);
      expect(find.textContaining('bot lost access'), findsOneWidget);
      expect(find.text('查看动态'), findsOneWidget);
      expect(find.text('配置'), findsOneWidget);
      expect(find.text('推送设置'), findsOneWidget);
      expect(find.text('检测'), findsOneWidget);
      expect(find.text('同步'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
    });
  });
}

FavoritesSyncStatus _mockFavoritesStatus() {
  return const FavoritesSyncStatus(
    running: true,
    intervalMinutes: 360,
    maxItems: 50,
    enabledPlatforms: ['zhihu'],
    lastSyncAt: '2026-06-05T12:00:00Z',
    recentRuns: [
      {
        'run_id': 'abcdef123456',
        'status': 'error',
        'scope': 'zhihu',
        'trigger': 'manual',
        'started_at': '2026-06-05T11:00:00Z',
        'error': 'cookie expired',
        'result': {
          'platform': 'zhihu',
          'result': {
            'platform': 'zhihu',
            'status': 'failed',
            'authenticated': false,
            'fetched': 0,
            'imported': 0,
            'failed': 0,
            'skipped': 0,
            'error': 'cookie expired',
            'error_hint': '登录状态不可用，请先完成该平台登录',
            'auth_required': true,
            'retryable': false,
          },
        },
      },
    ],
    platforms: [
      FavoritesPlatformStatus(
        platform: 'zhihu',
        enabled: true,
        available: true,
        authenticated: false,
        ratePerMinute: 5,
        lastResult: null,
        error: 'cookie expired',
        statusError: null,
      ),
    ],
  );
}

PlatformHealthResponse _mockPlatformHealth() {
  return const PlatformHealthResponse(
    platforms: [
      PlatformHealthStatus(
        platform: 'zhihu',
        label: '知乎',
        health: 'error',
        issues: ['登录状态不可用'],
        auth: {'cookie_configured': true, 'browser_auth_valid': false},
        favoritesSync: {'supported': true, 'enabled': true},
      ),
    ],
    recentFavoritesRuns: [],
  );
}

List<DiscoverySource> _mockDiscoverySources() {
  return [
    DiscoverySource(
      id: 1,
      kind: 'rss',
      name: 'Tech RSS',
      enabled: true,
      lastError: 'feed timeout',
      syncIntervalMinutes: 60,
      createdAt: DateTime(2026, 6, 6),
    ),
  ];
}

class MockDistributionRules extends DistributionRules {
  final List<DistributionRule> _rules;
  MockDistributionRules(this._rules);
  @override
  FutureOr<List<DistributionRule>> build() => _rules;
}

class MockContentQueue extends ContentQueue {
  final List<QueueItem> _items;
  MockContentQueue(this._items);
  @override
  FutureOr<QueueListResponse> build() {
    return QueueListResponse(items: _items, total: _items.length);
  }
}

class MockBotChats extends BotChats {
  final List<BotChat> _chats;
  MockBotChats(this._chats);
  @override
  FutureOr<List<BotChat>> build() => _chats;
}

class MockDiscoverySources extends DiscoverySources {
  final List<DiscoverySource> _sources;
  MockDiscoverySources(this._sources);
  @override
  FutureOr<List<DiscoverySource>> build() => _sources;
}
