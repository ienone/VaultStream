import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/collection/providers/batch_selection_provider.dart';
import 'package:frontend/features/collection/providers/content_actions_controller.dart';

class _Actions extends ContentActions {
  final calls = <int>[];
  final first = Completer<void>();
  bool fail = true;
  @override
  Set<String> build() => {};
  @override
  Future<ContentActionResult> reParse(int id) async {
    calls.add(id);
    if (calls.length == 1) await first.future;
    if (id == 2 && fail) return const ContentActionResult.failure('来源暂不可用');
    return ContentActionResult.success('已受理', runId: 'run-$id');
  }
}

void main() {
  test(
    'partial retry excludes accepted side effects and cannot change targets while running',
    () async {
      final actions = _Actions();
      final container = ProviderContainer(
        overrides: [contentActionsProvider.overrideWith(() => actions)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(batchSelectionProvider, (_, _) {});
      addTearDown(sub.close);
      final batch = container.read(batchSelectionProvider.notifier);
      batch.selectAll([1, 2, 3]);
      final first = batch.batchReParse();
      batch.selectAll([99]);
      batch.clearSelection();
      batch.toggleSelection(4);
      expect(container.read(batchSelectionProvider).selectedIds, {1, 2, 3});
      await expectLater(batch.batchDelete(), throwsStateError);
      actions.first.complete();
      final result = await first;
      expect(result.completed, 2);
      expect(result.failures.keys, [2]);
      expect(container.read(batchSelectionProvider).selectedIds, {2});
      actions.fail = false;
      await batch.batchReParse();
      expect(actions.calls, [1, 2, 3, 2]);
      expect(container.read(batchSelectionProvider).isSelectionMode, isFalse);
    },
  );
}
