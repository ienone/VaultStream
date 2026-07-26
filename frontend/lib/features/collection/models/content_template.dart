import 'content.dart';

/// 内容模板。
///
/// 模板决定详情结构、列表预览重点和主要操作。
/// 判定只使用后端 contract 中已验证存在的两个字段：
///
/// - `effective_layout_type`：`article | video | gallery | audio | link`
///   （后端 `LayoutType` 枚举，`compute_effective_layout_type()` 计算，
///   优先级为 用户覆盖 > 系统检测 > 平台推断）
/// - `content_type`：平台原生类型字符串（`String(50)`，由各 adapter 写入）
///
/// 这里不推断后端没有产出的类型。当前代码中没有任何 adapter 产出
/// 文档（PDF/幻灯片）类内容，也没有产出帖子串（`TwitterContentType.THREAD`
/// 已定义但从未被赋值），因此不提供对应模板。
enum ContentTemplate {
  /// 文章、专栏、知乎回答、RSS 条目、普通网页。连续阅读为主。
  article,

  /// 图文笔记：文字与图片共同完成叙事（当前由小红书 `note` 明确识别）。
  imageNote,

  /// 短帖子：推文、微博、B 站动态、Telegram 消息。紧凑，作者与来源是重点。
  shortPost,

  /// 图集：图片本身是主体。
  gallery,

  /// 视频。当前多数平台只归档封面与元数据，模板需表达"无本地媒体"。
  video,

  /// 音频与播客。
  audio,

  /// 聚合页：知乎问题、收藏夹等，成员条目是主体。
  collectionIndex,

  /// 平台账号主页。
  profile,

  /// 书签：仅链接，或解析失败后只保留"为什么保存"。
  bookmark;

  String get label => switch (this) {
    ContentTemplate.article => '文章',
    ContentTemplate.imageNote => '图文笔记',
    ContentTemplate.shortPost => '短帖子',
    ContentTemplate.gallery => '图集',
    ContentTemplate.video => '视频',
    ContentTemplate.audio => '音频',
    ContentTemplate.collectionIndex => '聚合页',
    ContentTemplate.profile => '主页',
    ContentTemplate.bookmark => '书签',
  };

  /// 正文是否需要限制可读宽度。
  bool get constrainsBodyWidth =>
      this == ContentTemplate.article || this == ContentTemplate.imageNote;

  /// 媒体是否是该模板的主体。
  bool get mediaIsPrimary =>
      this == ContentTemplate.gallery ||
      this == ContentTemplate.video ||
      this == ContentTemplate.audio;
}

/// 产出短帖子语义的平台原生类型。
const _shortPostTypes = {
  'tweet', // twitter
  'status', // weibo
  'pin', // zhihu 想法
  'dynamic', // bilibili 动态
  'post', // telegram
};

/// 产出聚合页语义的平台原生类型。
const _collectionTypes = {
  'question', // zhihu 问题（rich_payload.blocks 承载回答列表）
  'collection', // zhihu 收藏夹
};

/// 以视频/直播为消费方式的平台原生类型。
///
/// 注意：bilibili 的 video/bangumi/live 解析器当前写入 `layout_type=gallery`
/// 且只归档封面，因此必须靠 `content_type` 才能识别为视频语义。
const _videoTypes = {'video', 'bangumi', 'live'};

/// 依据已验证的 contract 字段解析模板。
///
/// [layoutType] 传 `effective_layout_type`，[contentType] 传 `content_type`。
/// 两者都可能为 null（旧数据或后端未提供），此时回落到 [ContentTemplate.article]，
/// 这与后端 `compute_effective_layout_type()` 的默认值一致——不是字段猜测。
ContentTemplate resolveContentTemplate({
  String? layoutType,
  String? contentType,
}) {
  final layout = layoutType?.trim().toLowerCase();
  final type = contentType?.trim().toLowerCase();

  // 账号主页优先于布局：主页的消费方式与图集完全不同。
  if (type == 'user_profile') return ContentTemplate.profile;

  switch (layout) {
    case 'audio':
      return ContentTemplate.audio;
    case 'video':
      return ContentTemplate.video;
    case 'link':
      return ContentTemplate.bookmark;
    case 'gallery':
      if (type != null && _videoTypes.contains(type)) {
        return ContentTemplate.video;
      }
      if (type != null && _collectionTypes.contains(type)) {
        return ContentTemplate.collectionIndex;
      }
      if (type == 'note') return ContentTemplate.imageNote;
      if (type != null && _shortPostTypes.contains(type)) {
        return ContentTemplate.shortPost;
      }
      return ContentTemplate.gallery;
    case 'article':
    default:
      if (type != null && _collectionTypes.contains(type)) {
        return ContentTemplate.collectionIndex;
      }
      if (type != null && _shortPostTypes.contains(type)) {
        return ContentTemplate.shortPost;
      }
      return ContentTemplate.article;
  }
}

extension ContentDetailTemplate on ContentDetail {
  ContentTemplate get template =>
      resolveContentTemplate(layoutType: layoutType, contentType: contentType);

  /// 解析是否失败。`status` 取自后端 `ContentStatus` 枚举。
  bool get isParseFailed => status == 'parse_failed';

  /// 解析是否仍在进行或尚未开始。
  bool get isParsePending => status == 'unprocessed' || status == 'processing';

  /// 是否存在可读正文。
  bool get hasBody => (body ?? '').trim().isNotEmpty;

  /// 是否存在派生摘要。摘要是生成结果，不能当作原文展示。
  bool get hasSummary => (summary ?? '').trim().isNotEmpty;

  /// 用户是否手动指定过模板。手动修订不应被重新解析静默覆盖。
  bool get hasManualTemplate => (layoutTypeOverride ?? '').isNotEmpty;
}

extension ShareCardTemplate on ShareCard {
  ContentTemplate get template =>
      resolveContentTemplate(layoutType: layoutType, contentType: contentType);
}
