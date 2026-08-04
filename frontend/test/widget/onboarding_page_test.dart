import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/presentation/onboarding_page.dart';

void main() {
  Future<void> pumpOnboarding(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OnboardingPage())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('功能开关与配置字段位于同一卡片', (tester) async {
    await pumpOnboarding(tester, size: const Size(600, 900));

    expect(find.byType(Stepper), findsNothing);
    expect(find.text('API Base URL'), findsNothing);
    await tester.tap(find.text('图像理解'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('API Base URL'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
  });

  testWidgets('通知字段横屏并排且可选项不收折', (tester) async {
    await pumpOnboarding(tester, size: const Size(800, 500));
    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();

    final telegramTop = tester.getTopLeft(find.text('Telegram')).dy;
    expect(tester.getTopLeft(find.text('QQ')).dy, telegramTop);

    await tester.tap(find.text('Telegram'));
    await tester.tap(find.text('QQ'));
    await tester.pumpAndSettle();
    expect(find.text('Bot Token'), findsOneWidget);
    expect(find.text('管理员 ID（可选）'), findsOneWidget);
    expect(find.text('Napcat API 地址'), findsOneWidget);
    expect(find.text('管理员 QQ 号（可选）'), findsOneWidget);
    expect(find.text('高级设置'), findsNothing);
  });

  testWidgets('账户 Cookie 默认收折并明确扫码连接', (tester) async {
    await pumpOnboarding(tester, size: const Size(600, 900));
    await tester.tap(find.text('账户'));
    await tester.pumpAndSettle();

    expect(find.text('扫码连接'), findsNWidgets(3));
    expect(find.text('手动 Cookie'), findsNWidgets(3));
    expect(find.text('Cookie'), findsNothing);

    await tester.tap(find.text('手动 Cookie').first);
    await tester.pumpAndSettle();
    expect(find.text('Cookie'), findsOneWidget);
  });

  testWidgets('功能卡按字段行数成对排列', (tester) async {
    await pumpOnboarding(tester, size: const Size(800, 1000));

    for (final label in ['内容理解', '图像理解', '自动摘要', '语义搜索']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    final textTop = tester.getTopLeft(find.text('内容理解')).dy;
    final visionTop = tester.getTopLeft(find.text('图像理解')).dy;
    final summaryTop = tester.getTopLeft(find.text('自动摘要')).dy;
    final embeddingTop = tester.getTopLeft(find.text('语义搜索')).dy;
    expect(visionTop, textTop);
    expect(embeddingTop, summaryTop);
    expect(summaryTop, greaterThan(textTop));
  });

  testWidgets('账户卡按三列两列单列渐进适配', (tester) async {
    await pumpOnboarding(tester, size: const Size(1200, 700));
    await tester.tap(find.text('账户'));
    await tester.pumpAndSettle();

    var weiboTop = tester.getTopLeft(find.text('微博')).dy;
    var xhsTop = tester.getTopLeft(find.text('小红书')).dy;
    var zhihuTop = tester.getTopLeft(find.text('知乎')).dy;
    expect(xhsTop, weiboTop);
    expect(zhihuTop, weiboTop);

    tester.view.physicalSize = const Size(800, 700);
    await tester.pumpAndSettle();
    weiboTop = tester.getTopLeft(find.text('微博')).dy;
    xhsTop = tester.getTopLeft(find.text('小红书')).dy;
    zhihuTop = tester.getTopLeft(find.text('知乎')).dy;
    expect(xhsTop, weiboTop);
    expect(zhihuTop, greaterThan(weiboTop));

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    weiboTop = tester.getTopLeft(find.text('微博')).dy;
    xhsTop = tester.getTopLeft(find.text('小红书')).dy;
    zhihuTop = tester.getTopLeft(find.text('知乎')).dy;
    expect(xhsTop, greaterThan(weiboTop));
    expect(zhihuTop, greaterThan(xhsTop));
  });

  testWidgets('进度条使用连续线和有界 InkWell 交互', (tester) async {
    await pumpOnboarding(tester, size: const Size(800, 500));

    expect(
      find.byKey(const ValueKey('onboarding-progress-line')),
      findsOneWidget,
    );
    final notificationInkWell = find.ancestor(
      of: find.text('通知'),
      matching: find.byType(InkWell),
    );
    expect(notificationInkWell, findsOneWidget);
    expect(tester.widget<InkWell>(notificationInkWell).hoverColor, isNotNull);
    expect(tester.getSize(notificationInkWell).width, lessThan(160));

    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();
    expect(find.text('Telegram'), findsOneWidget);
  });
  testWidgets('没有可选配置时完成页不显示账户卡', (tester) async {
    await pumpOnboarding(tester, size: const Size(800, 600));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('平台账户'), findsNothing);
    expect(find.text('没有需要确认的可选配置'), findsOneWidget);
  });
  testWidgets('完成页配置卡可跳回对应配置', (tester) async {
    await pumpOnboarding(tester, size: const Size(800, 600));
    await tester.tap(find.text('图像理解'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('确认配置'), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    expect(find.text('点击卡片可返回修改'), findsOneWidget);
    expect(find.text('平台账户'), findsNothing);

    await tester.tap(find.text('图像理解'));
    await tester.pumpAndSettle();
    expect(find.text('API Base URL'), findsOneWidget);
  });
}
