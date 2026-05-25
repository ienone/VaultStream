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
}
