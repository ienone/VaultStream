import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/features/review/models/distribution_rule.dart';
import 'package:frontend/features/review/widgets/distribution_rule_dialog.dart';

void main() {
  group('DistributionRuleDialog Widget Tests', () {
    testWidgets('DistributionRuleDialog - Create mode', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Dialog(
              child: DistributionRuleDialog(
                onCreate: (rule, selectedChatIds) {
                  expect(rule.name, 'New Test Rule');
                  expect(rule.matchConditions['tags'], ['tag1']);
                },
                onUpdate: null,
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'New Test Rule');

      // Add include tag using enter key simulation
      await tester.enterText(
        find.widgetWithText(TextFormField, '包含标签'),
        'tag1',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('tag1'), findsOneWidget); // Verify tag added

      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
    });

    testWidgets('DistributionRuleDialog - Edit mode', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final existingRule = DistributionRule(
        id: 1,
        name: 'Existing Rule',
        matchConditions: {
          'tags': ['old_tag'],
          'tags_exclude': [],
          'tags_match_mode': 'any',
        },
        enabled: true,
        priority: 0,
        nsfwPolicy: 'block',
        approvalRequired: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Dialog(
              child: DistributionRuleDialog(
                rule: existingRule,
                onCreate: (_, selectedChatIds) {},
                onUpdate: (id, update) {
                  expect(update.matchConditions!['tags'], ['new_tag']);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clear old tag
      await tester.tap(find.byIcon(Icons.cancel).first);
      await tester.pumpAndSettle();

      // Add new tag
      await tester.enterText(
        find.widgetWithText(TextFormField, '包含标签'),
        'new_tag',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('new_tag'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
    });
  });
}
