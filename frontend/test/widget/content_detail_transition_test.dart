import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/collection/content_detail_page.dart';
import 'package:frontend/features/collection/models/content.dart';
import 'package:frontend/features/collection/providers/collection_provider.dart';
import 'package:frontend/features/collection/widgets/list/collection_card_preview.dart';

void main() {
  testWidgets('card stays within constrained Hero flight dimensions', (
    tester,
  ) async {
    final preview = ShareCard(
      id: 41,
      platform: 'twitter',
      url: 'https://example.test/item/41',
      status: 'parse_success',
      layoutType: 'gallery',
      contentType: 'tweet',
      title:
          'A card title that remains visible while the shared container flies',
      authorName: 'Preview author',
      tags: const ['transition'],
      createdAt: DateTime(2026, 5, 25),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith(
            (ref) => Dio(BaseOptions(baseUrl: 'http://localhost')),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 603,
                height: 226,
                child: CollectionCardPreview(content: preview),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('ContentDetailPage loading state mounts one shared container', (
    tester,
  ) async {
    final preview = ShareCard(
      id: 42,
      platform: 'x',
      url: 'https://example.test/item/42',
      status: 'archived',
      layoutType: 'article',
      title: 'Preview title',
      authorName: 'Preview author',
      tags: const ['transition'],
      createdAt: DateTime(2026, 5, 25),
    );
    final pendingDetail = Completer<ContentDetail>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith(
            (ref) => Dio(BaseOptions(baseUrl: 'http://localhost')),
          ),
          contentDetailProvider(
            preview.id,
          ).overrideWith((ref) => pendingDetail.future),
        ],
        child: MaterialApp(
          home: ContentDetailPage(contentId: preview.id, preview: preview),
        ),
      ),
    );

    await tester.pump();

    // 只存在详情头这一套共享视觉，正文和媒体不参与。
    expect(find.byType(Hero), findsOneWidget);
    expect(
      find.byKey(const ValueKey('content-detail-shared-loading-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('content-detail-body-skeleton')),
      findsOneWidget,
    );
    expect(find.byType(CollectionCardPreview), findsNothing);
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.flightShuttleBuilder, isNotNull);
    expect(hero.placeholderBuilder, isNotNull);
    expect(
      hero.createRectTween!(
        const Rect.fromLTWH(0, 0, 240, 320),
        const Rect.fromLTWH(24, 24, 720, 116),
      ),
      isA<RectTween>(),
    );
    // 已知标题贯穿目标详情头与顶栏，而不是居中再画一张完整卡片。
    expect(find.text('Preview title'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Preview title'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ContentDetailPage data state keeps one opaque Hero target', (
    tester,
  ) async {
    final preview = ShareCard(
      id: 43,
      platform: 'x',
      url: 'https://example.test/item/43',
      status: 'archived',
      layoutType: 'article',
      title: 'Loaded preview title',
      authorName: 'Preview author',
      tags: const ['transition'],
      createdAt: DateTime(2026, 5, 25),
    );
    final detail = ContentDetail(
      id: preview.id,
      platform: preview.platform,
      url: preview.url,
      status: 'parse_success',
      tags: const ['transition'],
      isNsfw: false,
      title: 'Loaded detail title',
      body: 'Loaded body',
      authorName: 'Detail author',
      coverUrl: null,
      createdAt: DateTime(2026, 5, 25),
      updatedAt: DateTime(2026, 5, 25),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith(
            (ref) => Dio(BaseOptions(baseUrl: 'http://localhost')),
          ),
          contentDetailProvider(preview.id).overrideWith((ref) async => detail),
        ],
        child: MaterialApp(
          home: ContentDetailPage(contentId: preview.id, preview: preview),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Hero), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Hero), matching: find.byType(Material)),
      findsWidgets,
    );
    expect(find.text('Loaded detail title'), findsWidgets);
    expect(find.text('Detail author'), findsWidgets);
    expect(find.text('transition'), findsWidgets);
    expect(find.text('处理状态'), findsNothing);
  });
}
