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
