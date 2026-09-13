import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/collection/models/content.dart';
import 'package:frontend/features/collection/providers/content_actions_controller.dart';
import 'package:frontend/features/collection/widgets/content_editor.dart';

class _Actions extends ContentActions {
  final patches = <Map<String, dynamic>>[];
  @override
  Set<String> build() => {};
  @override
  Future<ContentActionResult> updateContent(
    int id,
    Map<String, dynamic> patch,
  ) async {
    patches.add(patch);
    return const ContentActionResult.success('已更新');
  }
}

void main() {
  testWidgets('editing preserves atomic tags and only patches changed fields', (
    tester,
  ) async {
    final actions = _Actions();
    final content = ContentDetail(
      id: 1,
      platform: 'universal',
      url: 'local://sample',
      status: 'parse_success',
      tags: ['New York', 'one,two'],
      isNsfw: false,
      title: '原标题',
      body: '正文',
      layoutTypeOverride: 'audio',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [contentActionsProvider.overrideWith(() => actions)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => ContentEditor(content: content),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await open();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed,
      isNull,
    );
    await tester.enterText(field('标题'), '新标题');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(actions.patches.single, {'title': '新标题'});
    await open();
    await tester.ensureVisible(field('添加标签'));
    await tester.enterText(field('添加标签'), 'New York，读书\n读书');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(actions.patches.last, {
      'tags': ['New York', 'one,two', '读书'],
    });
  });
}
