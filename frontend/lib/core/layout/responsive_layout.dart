import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/material.dart';

/// 窗口宽度类别。这是全应用唯一的宽度断点来源。
///
/// 断点取值与 `docs/plans/2026-06-10-frontend-information-architecture-redesign.plan.md`
/// 第九章的统一窗口类别表一致。页面不应再自行判断 800/900/1200。
enum WindowWidthClass {
  /// `< 600dp`：单 pane、全屏详情、bottom sheet。
  compact,

  /// `600–839dp`：单 pane 或窄 list-detail。
  medium,

  /// `840–1199dp`：标准 list-detail 或 supporting pane。
  expanded,

  /// `1200–1599dp`：两至三 pane，正文和表单限宽。
  large,

  /// `>= 1600dp`：受限主内容加稳定辅助 pane。
  extraLarge;

  bool get isCompact => this == WindowWidthClass.compact;

  /// 是否至少达到某个类别（枚举顺序即宽度顺序）。
  bool atLeast(WindowWidthClass other) => index >= other.index;

  /// 是否可以承载主内容 + 辅助 pane 的双栏结构。
  bool get supportsSupportingPane => atLeast(WindowWidthClass.expanded);
}

/// 窗口高度类别。手机横屏的可用高度远小于竖屏，必须单独判断，
/// 不能用 `width > height` 之类的方向判断代替。
enum WindowHeightClass {
  /// `< 480dp`：手机横屏。需要压缩 App Bar 并隐藏非关键辅助信息。
  compact,

  /// `480–899dp`：常规手机竖屏与平板横屏。
  medium,

  /// `>= 900dp`：平板竖屏与桌面。
  expanded;

  bool get isCompact => this == WindowHeightClass.compact;
}

/// 一次布局决策所需的全部窗口信息。
///
/// 通过 [WindowMetrics.of] 从 `MediaQuery` 读取，或用 [WindowMetrics.fromSize]
/// 从 `LayoutBuilder` 的约束构造（组件响应自身可用宽度时使用后者）。
@immutable
class WindowMetrics {
  const WindowMetrics({
    required this.width,
    required this.height,
    required this.widthClass,
    required this.heightClass,
    this.hasHinge = false,
  });

  final double width;
  final double height;
  final WindowWidthClass widthClass;
  final WindowHeightClass heightClass;

  /// 是否存在需要避开的显示铰链（折叠屏）。
  final bool hasHinge;

  factory WindowMetrics.fromSize(Size size, {bool hasHinge = false}) {
    return WindowMetrics(
      width: size.width,
      height: size.height,
      widthClass: ResponsiveLayout.widthClassFor(size.width),
      heightClass: ResponsiveLayout.heightClassFor(size.height),
      hasHinge: hasHinge,
    );
  }

  static WindowMetrics of(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return WindowMetrics.fromSize(
      mediaQuery.size,
      hasHinge: mediaQuery.displayFeatures.any(
        (feature) =>
            feature.type == DisplayFeatureType.hinge ||
            feature.type == DisplayFeatureType.fold,
      ),
    );
  }

  bool get isCompact => widthClass.isCompact;

  /// 手机横屏：宽度足够但高度不足，需要缩短顶栏、隐藏次要信息。
  bool get isShortLandscape => heightClass.isCompact && width > height;

  /// 是否可以并排显示主内容与辅助 pane。
  /// 高度过低时即使宽度足够也不强制双栏，避免三层结构挤压正文。
  bool get supportsSupportingPane =>
      widthClass.supportsSupportingPane && !heightClass.isCompact;

  @override
  bool operator ==(Object other) =>
      other is WindowMetrics &&
      other.width == width &&
      other.height == height &&
      other.hasHinge == hasHinge;

  @override
  int get hashCode => Object.hash(width, height, hasHinge);
}

class ResponsiveLayout {
  const ResponsiveLayout._();

  // 统一窗口类别断点
  static const double mediumBreakpoint = 600;
  static const double expandedBreakpoint = 840;
  static const double largeBreakpoint = 1200;
  static const double extraLargeBreakpoint = 1600;

  // 高度断点
  static const double compactHeightBreakpoint = 480;
  static const double expandedHeightBreakpoint = 900;

  static WindowWidthClass widthClassFor(double width) {
    if (width >= extraLargeBreakpoint) return WindowWidthClass.extraLarge;
    if (width >= largeBreakpoint) return WindowWidthClass.large;
    if (width >= expandedBreakpoint) return WindowWidthClass.expanded;
    if (width >= mediumBreakpoint) return WindowWidthClass.medium;
    return WindowWidthClass.compact;
  }

  static WindowHeightClass heightClassFor(double height) {
    if (height >= expandedHeightBreakpoint) return WindowHeightClass.expanded;
    if (height >= compactHeightBreakpoint) return WindowHeightClass.medium;
    return WindowHeightClass.compact;
  }

  static WindowWidthClass widthClassOf(BuildContext context) =>
      widthClassFor(MediaQuery.of(context).size.width);

  static bool isMobile(BuildContext context) =>
      !widthClassOf(context).atLeast(WindowWidthClass.expanded);

  /// 收藏库内容网格列数。
  ///
  /// 依据组件自身可用宽度而不是屏幕宽度，因此在 NavigationRail、
  /// 辅助 pane 或 side sheet 存在时也能得到正确列数。
  static int contentGridColumns(double availableWidth) {
    final widthClass = widthClassFor(availableWidth);
    switch (widthClass) {
      case WindowWidthClass.compact:
        // 手机按阅读顺序使用单列，避免长标题被挤成窄卡片。
        return 1;
      case WindowWidthClass.medium:
        return 2;
      case WindowWidthClass.expanded:
        return 3;
      case WindowWidthClass.large:
        return 4;
      case WindowWidthClass.extraLarge:
        // 超宽屏限制列数，避免卡片过窄导致标题不可读。
        return availableWidth >= 2000 ? 6 : 5;
    }
  }
}
