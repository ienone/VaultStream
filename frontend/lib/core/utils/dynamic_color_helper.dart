import 'package:flutter/material.dart';

/// 根据内容详情的封面颜色计算动态主题色
///
/// 规则：
/// 1. 如果有 coverColor 且不接近背景色，使用封面色
/// 2. 否则回退到系统主题色
class DynamicColorHelper {
  /// 计算内容的动态颜色
  ///
  /// [coverColor] 封面图的主色调（hex格式，如 "#FF5733"）
  /// [context] BuildContext 用于获取当前主题
  /// [fallbackColor] 可选的回退颜色，默认使用系统 primary
  static Color getContentColor(
    String? coverColor,
    BuildContext context, {
    Color? fallbackColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 没有封面颜色，使用回退
    if (coverColor == null || coverColor.isEmpty) {
      return fallbackColor ?? theme.colorScheme.primary;
    }

    // 解析封面颜色
    Color? parsedColor = _parseHexColor(coverColor);
    if (parsedColor == null) {
      return fallbackColor ?? theme.colorScheme.primary;
    }

    // 检查是否接近背景色
    final backgroundColor = isDark ? Colors.black : Colors.white;
    if (_isColorSimilar(parsedColor, backgroundColor, threshold: 0.15)) {
      // 太接近背景色，使用回退
      return fallbackColor ?? theme.colorScheme.primary;
    }

    // 检查亮度，确保在当前模式下有足够对比度
    final luminance = parsedColor.computeLuminance();

    if (isDark) {
      // 暗色模式：颜色太暗（luminance < 0.2）则提亮
      if (luminance < 0.2) {
        parsedColor = _lightenColor(parsedColor, 0.3);
      }
    } else {
      // 亮色模式：颜色太亮（luminance > 0.8）则加深
      if (luminance > 0.8) {
        parsedColor = _darkenColor(parsedColor, 0.3);
      }
    }

    return parsedColor;
  }

  /// 解析 hex 颜色字符串
  static Color? _parseHexColor(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) {
        buffer.write('ff');
      }
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  /// 判断两个颜色是否相似
  ///
  /// 使用欧几里得距离在 RGB 空间中计算
  /// [threshold] 相似度阈值（0-1），越小越严格
  static bool _isColorSimilar(
    Color color1,
    Color color2, {
    double threshold = 0.2,
  }) {
    final r1 = color1.r;
    final g1 = color1.g;
    final b1 = color1.b;

    final r2 = color2.r;
    final g2 = color2.g;
    final b2 = color2.b;

    final distance =
        ((r1 - r2) * (r1 - r2) + (g1 - g2) * (g1 - g2) + (b1 - b2) * (b1 - b2))
            .abs();

    final normalizedDistance = distance / 3.0; // 归一化到 [0, 1]

    return normalizedDistance < threshold;
  }

  /// 提亮颜色
  static Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  /// 加深颜色
  static Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  /// 为给定颜色生成 ColorScheme
  ///
  /// 基于封面色生成完整的 Material 3 色彩方案
  static ColorScheme getColorScheme(Color seedColor, Brightness brightness) {
    return ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  }
}
