import 'package:flutter/material.dart';

/// Design tokens for spacing, radius and motion.
/// Keep values centralized to avoid per-page drift.
final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  const AppSpacing._();
}

final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double xxxl = 32;
  static const double pill = 999;

  const AppRadius._();
}

/// 语义形状 token。
///
/// 组件按语义选择形状，而不是所有容器统一 28 圆角。
/// 卡片、pane、sheet 的圆角差异本身就是层级信号。
final class AppShape {
  /// 普通内容卡片：中等圆角。
  static const double card = AppRadius.md;

  /// 卡片内部的媒体、缩略图等次级容器。
  static const double cardMedia = AppRadius.sm;

  /// 分区容器 / supporting pane。
  static const double pane = AppRadius.lg;

  /// bottom sheet、side sheet、dialog。
  static const double sheet = AppRadius.xxl;

  /// 按钮、chip、选择指示器。
  static const double pill = AppRadius.pill;

  static const BorderRadius cardBorder = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius cardMediaBorder = BorderRadius.all(
    Radius.circular(cardMedia),
  );
  static const BorderRadius paneBorder = BorderRadius.all(
    Radius.circular(pane),
  );
  static const BorderRadius sheetTopBorder = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );

  const AppShape._();
}

final class AppMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration routeTransition = Duration(milliseconds: 260);
  static const Duration gallerySync = Duration(milliseconds: 140);

  /// 状态变化：选中、展开、按钮形变、进度完成。
  static const Duration stateChange = Duration(milliseconds: 200);

  /// 同层内容切换：section、筛选结果、list-detail 选择。
  static const Duration contentSwap = Duration(milliseconds: 240);

  /// 临时 surface 进入：menu、dialog、bottom/side sheet。
  static const Duration surfaceEnter = Duration(milliseconds: 320);

  /// 临时 surface 退出。退出比进入更短、更克制。
  static const Duration surfaceExit = Duration(milliseconds: 200);

  /// 容器转换：卡片到详情、搜索框到搜索页。
  static const Duration containerTransform = Duration(milliseconds: 450);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubic;

  const AppMotion._();
}

/// 布局尺寸 token。
final class AppPane {
  /// 阅读正文最大宽度。
  static const double readableMaxWidth = 720;

  /// 辅助 pane 宽度。
  static const double supportingWidth = 320;

  /// 表单和对话框最大宽度。
  static const double formMaxWidth = 560;

  const AppPane._();
}
