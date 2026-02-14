import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/review/models/bot_chat.dart';
import 'package:frontend/features/review/models/distribution_rule.dart';
import 'package:frontend/features/review/models/queue_item.dart';
import 'package:frontend/features/review/providers/bot_chats_provider.dart';
import 'package:frontend/features/review/providers/distribution_rules_provider.dart';
import 'package:frontend/features/review/providers/queue_provider.dart';
import 'package:frontend/features/review/review_page.dart';
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
            botChatsProvider.overrideWith(() => MockBotChats(mockBotChats)),
            apiClientProvider.overrideWith((ref) => MockDio()),
          ],
          child: const MaterialApp(home: ReviewPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('审批与分发'), findsOneWidget);
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
            botChatsProvider.overrideWith(() => MockBotChats(mockBotChats)),
            apiClientProvider.overrideWith((ref) => MockDio()),
          ],
          child: const MaterialApp(home: ReviewPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.textContaining('待推送 (1)'), findsAny);

      // Open dropdown to see Rule 1
      await tester.tap(find.byType(DropdownMenu<int?>));
      await tester.pumpAndSettle();
      expect(find.text('Rule 1').last, findsOneWidget);
    });
  });
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
