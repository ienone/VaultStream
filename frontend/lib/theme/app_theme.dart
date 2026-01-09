import 'package:flutter/material.dart';

// 定义一个名为AppTheme的类，用于管理应用的主题
class AppTheme {
  // 用一个不可变的局部静态变量定义默认的浅色主题颜色方案，
  // 使用ColorScheme.fromSeed方法从指定的种子颜色(seedColor)生成颜色方案
  // brightness参数指定颜色方案的亮度，这里设置为浅色(Brightness.light)
  static final _defaultLightColorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6750A4),
    brightness: Brightness.light,
  );

  static final _defaultDarkColorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6750A4),
    brightness: Brightness.dark,
  );

  // 定义一个静态方法light，接受一个可选的动态颜色方案参数(dynamicColorScheme)
  // ThemeData是Flutter框架中用于定义应用主题的类
  static ThemeData light(ColorScheme? dynamicColorScheme) {
    final scheme = dynamicColorScheme ?? _defaultLightColorScheme;
    return fromColorScheme(scheme, Brightness.light);
  }

  static ThemeData dark(ColorScheme? dynamicColorScheme) {
    final scheme = dynamicColorScheme ?? _defaultDarkColorScheme;
    return fromColorScheme(scheme, Brightness.dark);
  }

  static ThemeData fromColorScheme(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,

      // Scaffold 和 AppBar 的深度调整
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: 0.8),
        surfaceTintColor: scheme.surfaceContainerHighest,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      // 导航栏在深色模式下稍微突出一点
      navigationRailTheme: NavigationRailThemeData(
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.9,
        backgroundColor: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerHigh,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        selectedIconTheme: IconThemeData(
          color: scheme.onSecondaryContainer,
          size: 28,
        ),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),

      // 核心层次感：卡片设计
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: isDark ? 2 : 0, // 深色模式下给一点点投影来增强边缘识别
        color: isDark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
        shadowColor: Colors.black.withValues(alpha: 0.8),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          // 在深色模式下添加细微的边框，模仿高光边缘
          side: isDark
              ? BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.1),
                  width: 1,
                )
              : BorderSide.none,
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 4,
        hoverElevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        extendedSizeConstraints: const BoxConstraints.tightFor(height: 56),
      ),

      // 列表和分割线优化
      dividerTheme: DividerThemeData(
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.2 : 0.5),
      ),

      // 弹窗层次
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }
}
