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
      navigationRailTheme: const NavigationRailThemeData(
        labelType: NavigationRailLabelType.all, // 显示所有标签
        groupAlignment:
            -0.9, // groupAlignment取值范围是-1.0到1.0，-1.0表示完全顶部对齐，0.0表示垂直居中对齐，1.0表示完全底部对齐，这里设置为-0.9，表示接近顶部对齐
      ),

      // 卡片主题配置由CardThemeData定义
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias, // 抗锯齿裁剪行为
        elevation: 0, // 卡片阴影高度
        shape: RoundedRectangleBorder(
          // 卡片形状为圆角矩形
          side: BorderSide(
            color: scheme.outlineVariant,
          ), // 卡片边框颜色为颜色方案中的outlineVariant
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          // Radius.circular(12)表示创建一个圆角半径为12像素的Radius对象
          // borderRadius.all表示应用于所有角
          // const用于在编译时创建不可变的常量对象,避免运行时反复创建对象带来的性能开销
        ),
      ),
    );
  }

  static ThemeData dark(ColorScheme? dynamicColorScheme) {
    final scheme = dynamicColorScheme ?? _defaultDarkColorScheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      navigationRailTheme: const NavigationRailThemeData(
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.9,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
