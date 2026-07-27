import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/network_thumbnail.dart';
import 'package:frontend/features/collection/models/content.dart';
import 'package:frontend/features/collection/models/media_asset.dart';
import 'package:frontend/features/collection/widgets/detail/components/unified_stats.dart';
import 'package:frontend/features/collection/widgets/list/collection_card_preview.dart';

const _templates = <({String layout, String? type, String label})>[
  (layout: 'article', type: 'article', label: '文章'),
  (layout: 'gallery', type: 'note', label: '图文笔记'),
  (layout: 'gallery', type: 'tweet', label: '短帖子'),
  (layout: 'gallery', type: 'gallery', label: '图集'),
  (layout: 'gallery', type: 'video', label: '视频'),
  (layout: 'audio', type: 'podcast', label: '音频'),
  (layout: 'article', type: 'question', label: '聚合页'),
  (layout: 'gallery', type: 'user_profile', label: '主页'),
  (layout: 'link', type: 'webpage', label: '书签'),
];

ShareCard _card(int index, ({String layout, String? type, String label}) item) {
  return ShareCard(
    id: index + 1,
    platform: 'test',
    url: 'https://example.test/${index + 1}',
    status: 'parse_success',
    layoutType: item.layout,
    contentType: item.type,
    title: '${item.label}示例',
    createdAt: DateTime(2026, 7, 26),
  );
}

Widget _host(List<ShareCard> cards) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWith(
        (ref) => Dio(BaseOptions(baseUrl: 'http://localhost')),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Wrap(
            children: [
              for (final card in cards)
                SizedBox(
                  width: 210,
                  height: 260,
                  child: CollectionCardPreview(content: card),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('九类模板保持相同外框尺寸，并显示各自模板内容', (tester) async {
    final cards = [
      for (var index = 0; index < _templates.length; index++)
        _card(index, _templates[index]),
    ];

    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(cards));
    await tester.pump();

    final previews = find.byType(CollectionCardPreview);
    expect(previews, findsNWidgets(9));
    for (var index = 0; index < 9; index++) {
      expect(tester.getSize(previews.at(index)), const Size(210, 260));
      expect(find.text(_templates[index].label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('身份缺失使用头像占位，缺失作者和零统计不造假显示', (tester) async {
    final profile = _card(0, _templates[7]);

    await tester.pumpWidget(_host([profile]));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('collection-card-avatar-placeholder')),
      findsOneWidget,
    );
    expect(find.text('未知作者'), findsNothing);
    expect(
      find.byKey(const ValueKey('collection-card-optional-stats')),
      findsNothing,
    );
  });

  testWidgets('有值的统计数据按需出现', (tester) async {
    final video = _card(
      0,
      _templates[4],
    ).copyWith(viewCount: 1200, likeCount: 35);

    await tester.pumpWidget(_host([video]));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('collection-card-optional-stats')),
      findsOneWidget,
    );
    expect(find.text('1.2k'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
  });

  testWidgets('本地缩略图在交给图片组件前映射为受保护媒体 URL', (tester) async {
    final article = _card(0, _templates[0]).copyWith(
      coverUrl: 'local://vaultstream/blobs/sha256/aa/bb/cover.webp',
      thumbnailUrl:
          'local://vaultstream/blobs/sha256/aa/bb/cover.webp?size=thumb',
    );

    await tester.pumpWidget(_host([article]));
    await tester.pump();

    final thumbnail = tester.widget<NetworkThumbnail>(
      find.byType(NetworkThumbnail),
    );
    expect(
      thumbnail.imageUrl,
      'http://localhost/api/v1/media/'
      'vaultstream/blobs/sha256/aa/bb/cover.webp?size=thumb',
    );
  });

  testWidgets('封面不可用时继续尝试正文首图的统一候选', (tester) async {
    const remoteCover = MediaAsset(
      id: 10,
      contentId: 1,
      mediaType: MediaType.image,
      role: MediaRole.cover,
      sources: [
        MediaSource(
          url: 'https://origin.test/cover.jpg',
          sourceKind: MediaSourceKind.remoteDirect,
        ),
      ],
    );
    const archivedBody = MediaAsset(
      id: 11,
      contentId: 1,
      mediaType: MediaType.image,
      role: MediaRole.body,
      sources: [
        MediaSource(
          url: 'http://localhost/api/v1/media/blobs/body.webp?signature=x',
          sourceKind: MediaSourceKind.localSigned,
        ),
      ],
    );
    final article = _card(
      0,
      _templates[0],
    ).copyWith(mediaAssets: const [archivedBody, remoteCover]);

    await tester.pumpWidget(_host([article]));
    await tester.pump();

    final thumbnail = tester.widget<NetworkThumbnail>(
      find.byType(NetworkThumbnail).first,
    );
    expect(
      thumbnail.imageUrl,
      'http://localhost/api/v1/media/blobs/body.webp?signature=x',
    );
    expect(thumbnail.fallbackUrls, ['https://origin.test/cover.jpg']);
  });

  testWidgets('详情统计不因平台类型补出无数据的零值', (tester) async {
    final detail = ContentDetail(
      id: 1,
      platform: 'bilibili',
      url: 'https://example.test/video',
      status: 'parse_success',
      tags: const [],
      isNsfw: false,
      createdAt: DateTime(2026, 7, 26),
      updatedAt: DateTime(2026, 7, 26),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UnifiedStats(detail: detail)),
      ),
    );

    expect(find.text('浏览'), findsNothing);
    expect(find.text('点赞'), findsNothing);
    expect(find.text('收藏'), findsNothing);
    expect(find.text('评论'), findsNothing);
    expect(find.text('分享'), findsNothing);
  });
}
