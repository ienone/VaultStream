import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/discovery/models/discovery_models.dart';
import 'package:frontend/features/discovery/widgets/discovery_batch_action_sheet.dart';
import 'package:frontend/features/discovery/widgets/discovery_item_card.dart';

void main() {
  testWidgets('DiscoveryItemCard shows inbox candidate type labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(Dio(BaseOptions(baseUrl: ''))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DiscoveryItemCard(item: _item(sourceType: 'rss')),
                DiscoveryItemCard(
                  item: _item(
                    id: 2,
                    sourceType: 'favorites_sync',
                    title: '收藏候选内容',
                  ),
                ),
                DiscoveryItemCard(
                  item: _item(id: 3, status: 'parse_failed', title: '解析失败内容'),
                ),
                DiscoveryItemCard(
                  item: _item(id: 4, aiScore: 3.2, title: '低分内容'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('RSS'), findsOneWidget);
    expect(find.text('收藏候选'), findsOneWidget);
    expect(find.text('待修复'), findsOneWidget);
    expect(find.text('低置信度'), findsOneWidget);
    expect(find.text('待处理'), findsNWidgets(4));
  });

  testWidgets('DiscoveryBatchActionSheet exposes inbox batch actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  DiscoveryBatchActionSheet(parentContext: context),
            ),
          ),
        ),
      ),
    );

    expect(find.text('批量收藏'), findsOneWidget);
    expect(find.text('批量忽略'), findsOneWidget);
    expect(find.text('批量稍后处理'), findsOneWidget);
  });
}

DiscoveryItem _item({
  int id = 1,
  String? title,
  String? sourceType,
  String? status,
  double? aiScore,
}) {
  return DiscoveryItem(
    id: id,
    title: title ?? '候选内容 $id',
    url: 'https://example.com/$id',
    status: status,
    sourceType: sourceType,
    discoveryState: 'visible',
    aiScore: aiScore,
    createdAt: DateTime.utc(2026, 6, 6),
  );
}
