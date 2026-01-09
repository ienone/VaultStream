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
    final scheme =
        dynamicColorScheme ??
        _defaultLightColorScheme; // 如果传入的动态颜色方案为null，则使用兜底的默认浅色主题颜色方案
    // ThemeData方法返回一个ThemeData对象，指定颜色方案和其他主题配置
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme, //刚刚定义的颜色方案
      // 为了了在Web上获得更好的性能，使用系统默认字体；
      // fontFamily: 'NotoSans',

      // 导航栏主题配置由NavigationRailThemeData定义
      navigationRailTheme: NavigationRailThemeData(
        labelType: NavigationRailLabelType.all, // 显示所有标签
        groupAlignment: -0.9,
        backgroundColor: scheme.surfaceContainerHigh,
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

      // 卡片主题配置由CardThemeData定义
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias, // 抗锯齿裁剪行为
        elevation: 0, // 卡片阴影高度
        color: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
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
    );
  }

  static ThemeData dark(ColorScheme? dynamicColorScheme) {
    final scheme = dynamicColorScheme ?? _defaultDarkColorScheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      navigationRailTheme: NavigationRailThemeData(
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.9,
        backgroundColor: scheme.surfaceContainerHigh,
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
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
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
    );
  }
}
