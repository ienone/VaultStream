import 'package:frontend/features/collection/models/content.dart';

/// 平台常量定义
class PlatformConstants {
  PlatformConstants._();

  /// Telegram 平台标识
  static const String telegram = 'telegram';

  /// QQ 平台标识
  static const String qq = 'qq';

  /// 所有支持的平台列表
  static const List<String> supportedPlatforms = [telegram, qq];

  /// 平台显示名称映射
  static const Map<String, String> platformNames = {
    telegram: 'Telegram',
    qq: 'QQ',
  };

  /// 检查平台是否支持
  static bool isSupported(String platform) {
    return supportedPlatforms.contains(platform);
  }

  /// 获取平台显示名称
  static String getName(String platform) {
    return platformNames[platform] ?? platform;
  }
}

/// 平台类型检查扩展
extension PlatformCheck on String {
  bool get isTwitter =>
      toLowerCase() == 'twitter' || toLowerCase() == 'x';

  bool get isBilibili => toLowerCase() == 'bilibili';

  bool get isXiaohongshu => toLowerCase() == 'xiaohongshu';
  
  bool get isWeibo => toLowerCase() == 'weibo';
  
  bool get isZhihu => toLowerCase() == 'zhihu';
}

/// 内容类型扩展
extension ContentTypeCheck on ContentDetail {
  bool get isZhihuArticle => platform.isZhihu && contentType == 'article';
  bool get isZhihuAnswer => platform.isZhihu && contentType == 'answer';
  bool get isZhihuPin => platform.isZhihu && contentType == 'pin';
  bool get isZhihuQuestion => platform.isZhihu && contentType == 'question';
  bool get isZhihuColumn => platform.isZhihu && contentType == 'column';
  bool get isZhihuCollection => platform.isZhihu && contentType == 'collection';
}