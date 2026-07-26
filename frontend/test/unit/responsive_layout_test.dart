import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/layout/responsive_layout.dart';

void main() {
  group('统一窗口宽度类别', () {
    test('断点与前端 IA 方案第九章的表格一致', () {
      expect(ResponsiveLayout.widthClassFor(359), WindowWidthClass.compact);
      expect(ResponsiveLayout.widthClassFor(599), WindowWidthClass.compact);
      expect(ResponsiveLayout.widthClassFor(600), WindowWidthClass.medium);
      expect(ResponsiveLayout.widthClassFor(839), WindowWidthClass.medium);
      expect(ResponsiveLayout.widthClassFor(840), WindowWidthClass.expanded);
      expect(ResponsiveLayout.widthClassFor(1199), WindowWidthClass.expanded);
      expect(ResponsiveLayout.widthClassFor(1200), WindowWidthClass.large);
      expect(ResponsiveLayout.widthClassFor(1599), WindowWidthClass.large);
      expect(ResponsiveLayout.widthClassFor(1600), WindowWidthClass.extraLarge);
    });

    test('atLeast 按宽度顺序比较', () {
      expect(
        WindowWidthClass.expanded.atLeast(WindowWidthClass.medium),
        isTrue,
      );
      expect(
        WindowWidthClass.medium.atLeast(WindowWidthClass.expanded),
        isFalse,
      );
    });

    test('只有 expanded 及以上支持辅助 pane', () {
      expect(WindowWidthClass.compact.supportsSupportingPane, isFalse);
      expect(WindowWidthClass.medium.supportsSupportingPane, isFalse);
      expect(WindowWidthClass.expanded.supportsSupportingPane, isTrue);
      expect(WindowWidthClass.extraLarge.supportsSupportingPane, isTrue);
    });
  });

  group('窗口高度类别', () {
    test('手机横屏高度归为 compact', () {
      expect(ResponsiveLayout.heightClassFor(360), WindowHeightClass.compact);
      expect(ResponsiveLayout.heightClassFor(479), WindowHeightClass.compact);
      expect(ResponsiveLayout.heightClassFor(480), WindowHeightClass.medium);
      expect(ResponsiveLayout.heightClassFor(899), WindowHeightClass.medium);
      expect(ResponsiveLayout.heightClassFor(900), WindowHeightClass.expanded);
    });
  });

  group('WindowMetrics', () {
    test('手机竖屏 360x800', () {
      final m = WindowMetrics.fromSize(const Size(360, 800));
      expect(m.widthClass, WindowWidthClass.compact);
      expect(m.isCompact, isTrue);
      expect(m.isShortLandscape, isFalse);
      expect(m.supportsSupportingPane, isFalse);
    });

    test('手机横屏 800x360 宽度足够但高度不足，不使用双栏', () {
      final m = WindowMetrics.fromSize(const Size(800, 360));
      expect(m.widthClass, WindowWidthClass.medium);
      expect(m.heightClass, WindowHeightClass.compact);
      expect(m.isShortLandscape, isTrue);
      expect(m.supportsSupportingPane, isFalse);
    });

    test('平板横屏 1200x800 使用双栏', () {
      final m = WindowMetrics.fromSize(const Size(1200, 800));
      expect(m.widthClass, WindowWidthClass.large);
      expect(m.supportsSupportingPane, isTrue);
    });

    test('宽而极矮的窗口不启用辅助 pane', () {
      final m = WindowMetrics.fromSize(const Size(1600, 400));
      expect(m.widthClass, WindowWidthClass.extraLarge);
      expect(m.supportsSupportingPane, isFalse);
    });
  });

  group('内容网格列数', () {
    test('依据可用宽度而不是屏幕宽度', () {
      expect(ResponsiveLayout.contentGridColumns(320), 1);
      expect(ResponsiveLayout.contentGridColumns(360), 2);
      expect(ResponsiveLayout.contentGridColumns(599), 2);
      expect(ResponsiveLayout.contentGridColumns(600), 2);
      expect(ResponsiveLayout.contentGridColumns(840), 3);
      expect(ResponsiveLayout.contentGridColumns(1200), 4);
      expect(ResponsiveLayout.contentGridColumns(1600), 5);
      expect(ResponsiveLayout.contentGridColumns(2000), 6);
    });

    test('列数随宽度单调不减', () {
      var previous = 0;
      for (var width = 200.0; width <= 2400; width += 40) {
        final columns = ResponsiveLayout.contentGridColumns(width);
        expect(columns, greaterThanOrEqualTo(previous));
        previous = columns;
      }
    });
  });

  test('Root Shell 断点保持现状，等待自身切片迁移', () {
    // 收藏库切片不改变主导航在 600–839dp 的形态。
    expect(ResponsiveLayout.mobileBreakpoint, 800);
    expect(ResponsiveLayout.desktopBreakpoint, 1200);
  });
}
