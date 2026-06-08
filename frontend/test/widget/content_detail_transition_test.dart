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
  testWidgets('ContentDetailPage loading state keeps preview Hero mounted', (
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

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Hero && widget.tag == collectionCardHeroTag(preview.id),
      ),
      findsOneWidget,
    );
    expect(find.byType(CollectionCardPreview), findsOneWidget);
    expect(find.text('Preview title'), findsOneWidget);
  });

  testWidgets('ContentDetailPage data state uses a real detail Hero target', (
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

    final hero = tester.widget<Hero>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Hero && widget.tag == collectionCardHeroTag(preview.id),
      ),
    );
    expect(hero.flightShuttleBuilder, isNotNull);
    expect(hero.child, isA<DetailHeroHeader>());
    expect(find.byType(DetailHeroHeader), findsOneWidget);
    expect(find.text('Loaded detail title'), findsWidgets);
    expect(find.text('Detail author'), findsWidgets);
    expect(find.text('transition'), findsWidgets);
  });
}
