import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/collection/content_detail_page.dart';
import 'package:frontend/features/collection/models/content.dart';
import 'package:frontend/features/collection/models/content_template.dart';
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

  testWidgets(
    'immersive loading target starts in the real right content pane',
    (tester) async {
      final preview = ShareCard(
        id: 49,
        platform: 'xiaohongshu',
        url: 'https://example.test/item/49',
        status: 'archived',
        layoutType: 'gallery',
        contentType: 'note',
        title: '媒体卡片标题',
        thumbnailUrl: 'https://example.test/preview.webp',
        authorName: '预览作者',
        tags: const [],
        createdAt: DateTime(2026, 7, 28),
      );
      final pendingDetail = Completer<ContentDetail>();

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
        find.byKey(const ValueKey('content-detail-immersive-loading-skeleton')),
        findsOneWidget,
      );
      expect(find.byType(Hero), findsOneWidget);
      expect(tester.getTopLeft(find.byType(Hero)).dx, greaterThan(700));
    },
  );

  testWidgets(
    'thumbnail-only short post keeps its loading title in the left reading pane',
    (tester) async {
      final preview = ShareCard(
        id: 50,
        platform: 'weibo',
        url: 'https://example.test/status/50',
        status: 'archived',
        layoutType: 'article',
        contentType: 'status',
        title: '纯文字短帖标题',
        thumbnailUrl: 'https://example.test/link-preview.webp',
        authorName: '短帖作者',
        tags: const [],
        createdAt: DateTime(2026, 7, 30),
      );
      final pendingDetail = Completer<ContentDetail>();

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
        find.byKey(const ValueKey('content-detail-immersive-loading-skeleton')),
        findsNothing,
      );
      expect(find.byType(Hero), findsOneWidget);
      expect(tester.getTopLeft(find.byType(Hero)).dx, lessThan(700));
    },
  );

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
      authorAvatarUrl: 'https://example.test/detail-avatar.webp',
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

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(Hero), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Hero), matching: find.byType(Material)),
      findsWidgets,
    );
    expect(find.text('Loaded detail title'), findsWidgets);
    expect(find.text('Detail author'), findsWidgets);
    expect(
      find.byKey(const ValueKey('content-detail-author-avatar')),
      findsOneWidget,
    );
    expect(find.text('transition'), findsWidgets);
    expect(find.text('处理状态'), findsNothing);
  });

  testWidgets(
    'Zhihu answer header removes duplicate question card and action',
    (tester) async {
      final detail = ContentDetail(
        id: 44,
        platform: 'zhihu',
        contentType: 'answer',
        layoutType: 'article',
        url: 'https://www.zhihu.com/question/123/answer/456',
        status: 'parse_success',
        tags: const [],
        isNsfw: false,
        title: '回答：为什么这样设计？',
        body: '# 第一节\n\n正文',
        authorName: '测试作者',
        createdAt: DateTime(2026, 7, 28),
        updatedAt: DateTime(2026, 7, 28),
        contextData: const {
          'type': 'question',
          'title': '为什么这样设计？',
          'url': 'https://www.zhihu.com/question/123',
          'stats': {
            'answer_count': 42,
            'follower_count': 7,
            'visit_count': 9000,
          },
        },
      );

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith(
              (ref) => Dio(BaseOptions(baseUrl: 'http://localhost')),
            ),
            contentDetailProvider(
              detail.id,
            ).overrideWith((ref) async => detail),
          ],
          child: MaterialApp(home: ContentDetailPage(contentId: detail.id)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('内容详情'), findsOneWidget);
      expect(find.text('为什么这样设计？'), findsOneWidget);
      expect(find.text('回答：为什么这样设计？'), findsNothing);
      expect(find.text('回答'), findsOneWidget);
      expect(find.text('42 回答'), findsOneWidget);
      expect(find.text('7 关注'), findsOneWidget);
      expect(find.text('原文'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('content-detail-outline-surface')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'wide image note uses immersive media stage with hover navigation',
    (tester) async {
      final detail = ContentDetail(
        id: 45,
        platform: 'xiaohongshu',
        contentType: 'note',
        layoutType: 'gallery',
        url: 'https://www.xiaohongshu.com/explore/example',
        status: 'parse_success',
        tags: const ['穿搭'],
        isNsfw: false,
        title: '周末穿搭记录',
        body: '左侧浏览图片，右侧阅读笔记文字。',
        authorName: '笔记作者',
        mediaUrls: const [
          'https://example.test/note-1.webp',
          'https://example.test/note-2.webp',
        ],
        createdAt: DateTime(2026, 7, 28),
        updatedAt: DateTime(2026, 7, 28),
      );

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith(
              (ref) => Dio(BaseOptions(baseUrl: 'http://localhost')),
            ),
            contentDetailProvider(
              detail.id,
            ).overrideWith((ref) async => detail),
          ],
          child: MaterialApp(home: ContentDetailPage(contentId: detail.id)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('immersive-media-detail')),
        findsOneWidget,
      );
      expect(find.text('作者与来源'), findsNothing);
      expect(find.byKey(const ValueKey('detail-tags-module')), findsOneWidget);
      expect(find.text('笔记作者'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('immersive-media-thumbnails')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('immersive-media-side-reveal')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('immersive-media-shared-header')),
            )
            .dx,
        greaterThan(700),
      );

      final nextButton = find.byKey(const ValueKey('immersive-media-next'));
      expect(nextButton, findsOneWidget);
      final nextOpacity = find.descendant(
        of: nextButton,
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(nextOpacity).opacity, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('immersive-media-viewer'))),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<AnimatedOpacity>(nextOpacity).opacity, 1);
      await mouse.removePointer();
    },
  );

  testWidgets('media profile shows its statistics only once', (tester) async {
    final detail = ContentDetail(
      id: 47,
      platform: 'zhihu',
      contentType: 'user_profile',
      layoutType: 'gallery',
      url: 'https://www.zhihu.com/people/example',
      status: 'parse_success',
      tags: const ['profile'],
      isNsfw: false,
      title: '测试用户的知乎主页',
      body: '个人简介',
      authorName: '测试用户',
      authorAvatarUrl: 'https://example.test/avatar.webp',
      mediaUrls: const ['https://example.test/profile-cover.webp'],
      viewCount: 598000,
      shareCount: 427,
      likeCount: 1578000,
      collectCount: 469000,
      extraStats: const {'answer_count': 13000},
      createdAt: DateTime(2026, 7, 28),
      updatedAt: DateTime(2026, 7, 28),
    );

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith(
            (ref) => Dio(BaseOptions(baseUrl: 'http://localhost')),
          ),
          contentDetailProvider(detail.id).overrideWith((ref) async => detail),
        ],
        child: MaterialApp(home: ContentDetailPage(contentId: detail.id)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('immersive-media-detail')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('detail-stats-module')), findsOneWidget);
    expect(find.text('粉丝'), findsOneWidget);
    expect(find.text('回答'), findsOneWidget);
  });

  testWidgets('plain short post does not repeat its body as a large title', (
    tester,
  ) async {
    const postText = '只有一句话的短帖，不需要再复制成一个大标题。';
    final detail = ContentDetail(
      id: 48,
      platform: 'twitter',
      contentType: 'tweet',
      layoutType: 'short_post',
      url: 'https://x.com/example/status/48',
      status: 'parse_success',
      tags: const [],
      isNsfw: false,
      title: postText,
      body: postText,
      authorName: '短帖作者',
      createdAt: DateTime(2026, 7, 28),
      updatedAt: DateTime(2026, 7, 28),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith(
            (ref) => Dio(BaseOptions(baseUrl: 'http://localhost')),
          ),
          contentDetailProvider(detail.id).overrideWith((ref) async => detail),
        ],
        child: MaterialApp(home: ContentDetailPage(contentId: detail.id)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('short-post-compact-body')),
      findsOneWidget,
    );
    expect(find.text(postText), findsOneWidget);
  });

  testWidgets('wide article docks its title after the header scrolls away', (
    tester,
  ) async {
    final detail = ContentDetail(
      id: 46,
      platform: 'zhihu',
      contentType: 'article',
      layoutType: 'article',
      url: 'https://zhuanlan.zhihu.com/p/example',
      status: 'parse_success',
      tags: const [],
      isNsfw: false,
      title: '一篇需要长时间阅读的文章',
      body: List.filled(40, '正文段落用于验证标题停靠行为。').join('\n\n'),
      authorName: '长文作者',
      createdAt: DateTime(2026, 7, 28),
      updatedAt: DateTime(2026, 7, 28),
    );
    expect(detail.template, ContentTemplate.article);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith(
            (ref) => Dio(BaseOptions(baseUrl: 'http://localhost')),
          ),
          contentDetailProvider(detail.id).overrideWith((ref) async => detail),
        ],
        child: MaterialApp(home: ContentDetailPage(contentId: detail.id)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('content-detail-identity-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('content-detail-docked-title-hidden')),
      findsOneWidget,
    );
    final primaryList = tester.widget<ListView>(
      find.byKey(const ValueKey('content-detail-primary-scroll')),
    );
    expect(primaryList.controller!.position.maxScrollExtent, greaterThan(136));
    primaryList.controller!.jumpTo(220);
    expect(primaryList.controller!.offset, greaterThanOrEqualTo(136));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('content-detail-docked-title-visible')),
      findsOneWidget,
    );
    expect(find.text('正在阅读'), findsOneWidget);
  });
}
