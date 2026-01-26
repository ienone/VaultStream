import 'package:flutter/material.dart';

class ResponsiveLayout {
  static const double mobileBreakpoint = 800;
  static const double desktopBreakpoint = 1200;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static int getColumnCount(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    if (width > 2200) return 7;
    if (width > 1800) return 6;
    if (width > 1400) return 5;
    if (width >= 1000) return 4;
    if (width >= 800) return 3;
    if (width >= 500) return 2;
    return 1; // 窄屏显示单列
  }

  static double getCardWidth(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double availableWidth = screenWidth;

    if (screenWidth >= mobileBreakpoint) {
      // 桌面布局有 NavigationRail
      if (screenWidth >= desktopBreakpoint) {
        availableWidth -= 200; // extended rail
      } else {
        availableWidth -= 80; // collapsed rail
      }
    }

    int columns = getColumnCount(context);
    // 左右内边距 16*2 = 32, 间距 12
    return (availableWidth - 32 - (columns - 1) * 12) / columns;
  }
}
