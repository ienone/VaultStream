import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/collection/models/content.dart';
import 'package:frontend/features/collection/models/content_template.dart';

ContentDetail _detail({
  String? layoutType,
  String? contentType,
  String? body,
  String status = 'parse_success',
  List<String> mediaUrls = const [],
  String? layoutTypeOverride,
  String? summary,
}) {
  return ContentDetail(
    id: 1,
    platform: 'zhihu',
    url: 'https://example.test/1',
    status: status,
    tags: const [],
    isNsfw: false,
    layoutType: layoutType,
    contentType: contentType,
    layoutTypeOverride: layoutTypeOverride,
    body: body,
    summary: summary,
    mediaUrls: mediaUrls,
    createdAt: DateTime(2026, 5, 25),
    updatedAt: DateTime(2026, 5, 25),
  );
}

void main() {
  group('模板解析只使用已验证的 contract 字段', () {
    test('user_profile 优先于布局类型', () {
      // 三个平台的 user_profile 解析器都写入 layout_type=gallery，
      // 但主页的消费方式与图集完全不同。
      expect(
        resolveContentTemplate(
          layoutType: 'gallery',
          contentType: 'user_profile',
        ),
        ContentTemplate.profile,
      );
    });

    test('bilibili 视频靠 content_type 识别，而不是 layout_type', () {
      // video_parser 写入 layout_type=gallery 且只归档封面，
      // 因此 layout_type=='video' 对 bilibili 永远不成立。
      expect(
        resolveContentTemplate(layoutType: 'gallery', contentType: 'video'),
        ContentTemplate.video,
      );
      expect(
        resolveContentTemplate(layoutType: 'gallery', contentType: 'bangumi'),
        ContentTemplate.video,
      );
      expect(
        resolveContentTemplate(layoutType: 'gallery', contentType: 'live'),
        ContentTemplate.video,
      );
    });

    test('小红书笔记是图文笔记，不是图集', () {
      expect(
        resolveContentTemplate(layoutType: 'gallery', contentType: 'note'),
        ContentTemplate.imageNote,
      );
    });

    test('短帖子类型不因详情正文或媒体加载状态改变模板', () {
      for (final type in ['tweet', 'status', 'pin', 'dynamic', 'post']) {
        expect(
          resolveContentTemplate(layoutType: 'gallery', contentType: type),
          ContentTemplate.shortPost,
          reason: type,
        );
      }
      expect(
        resolveContentTemplate(layoutType: 'gallery', contentType: 'tweet'),
        ContentTemplate.shortPost,
      );
    });

    test('知乎问题与收藏夹是聚合页', () {
      expect(
        resolveContentTemplate(layoutType: 'gallery', contentType: 'question'),
        ContentTemplate.collectionIndex,
      );
      expect(
        resolveContentTemplate(
          layoutType: 'article',
          contentType: 'collection',
        ),
        ContentTemplate.collectionIndex,
      );
    });

    test('未知 gallery 内容稳定映射到图集', () {
      expect(
        resolveContentTemplate(layoutType: 'gallery'),
        ContentTemplate.gallery,
      );
    });

    test('audio 与 link 布局映射到各自模板', () {
      expect(
        resolveContentTemplate(layoutType: 'audio'),
        ContentTemplate.audio,
      );
      expect(
        resolveContentTemplate(layoutType: 'link'),
        ContentTemplate.bookmark,
      );
    });

    test('字段缺失时回落到 article，与后端默认值一致', () {
      expect(resolveContentTemplate(), ContentTemplate.article);
      expect(
        resolveContentTemplate(layoutType: null, contentType: 'webpage'),
        ContentTemplate.article,
      );
    });
  });

  group('ContentDetail 模板扩展', () {
    test('解析状态判定基于后端 ContentStatus 枚举值', () {
      expect(_detail(status: 'parse_failed').isParseFailed, isTrue);
      expect(_detail(status: 'processing').isParsePending, isTrue);
      expect(_detail(status: 'unprocessed').isParsePending, isTrue);
      expect(_detail(status: 'parse_success').isParsePending, isFalse);
      expect(_detail(status: 'parse_success').isParseFailed, isFalse);
    });

    test('空白正文与摘要不算存在', () {
      expect(_detail(body: '   ').hasBody, isFalse);
      expect(_detail(body: '正文').hasBody, isTrue);
      expect(_detail(summary: '  ').hasSummary, isFalse);
      expect(_detail(summary: '摘要').hasSummary, isTrue);
    });

    test('人工指定的模板可被识别，且覆盖系统判定', () {
      final manual = _detail(
        layoutType: 'link',
        layoutTypeOverride: 'link',
        contentType: 'webpage',
      );
      expect(manual.hasManualTemplate, isTrue);
      expect(manual.template, ContentTemplate.bookmark);

      expect(_detail(layoutType: 'article').hasManualTemplate, isFalse);
    });

    test('模板携带布局意图', () {
      expect(ContentTemplate.article.constrainsBodyWidth, isTrue);
      expect(ContentTemplate.imageNote.constrainsBodyWidth, isTrue);
      expect(ContentTemplate.gallery.constrainsBodyWidth, isFalse);
      expect(ContentTemplate.video.mediaIsPrimary, isTrue);
      expect(ContentTemplate.audio.mediaIsPrimary, isTrue);
      expect(ContentTemplate.article.mediaIsPrimary, isFalse);
    });
  });

  group('ShareCard 模板扩展', () {
    test('卡片使用与详情相同的判定规则', () {
      const card = ShareCard(
        id: 1,
        platform: 'bilibili',
        url: 'https://example.test/v',
        contentType: 'video',
        layoutType: 'gallery',
      );
      expect(card.template, ContentTemplate.video);
    });
  });
}
