import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'content_actions_controller.dart';

part 'batch_selection_provider.g.dart';

@riverpod
class BatchSelection extends _$BatchSelection {
  @override
  BatchSelectionState build() {
    return const BatchSelectionState();
  }

  void toggleSelection(int id) {
    if (state.isProcessing) return;
    final newIds = Set<int>.from(state.selectedIds);
    if (newIds.contains(id)) {
      newIds.remove(id);
    } else {
      newIds.add(id);
    }
    state = state.copyWith(
      selectedIds: newIds,
      isSelectionMode: newIds.isNotEmpty,
    );
  }

  void selectAll(List<int> ids) {
    if (state.isProcessing) return;
    state = state.copyWith(selectedIds: ids.toSet(), isSelectionMode: true);
  }

  void clearSelection() {
    if (state.isProcessing) return;
    state = const BatchSelectionState();
  }

  void enterSelectionMode() {
    if (state.isProcessing) return;
    state = state.copyWith(isSelectionMode: true);
  }

  void exitSelectionMode() {
    if (state.isProcessing) return;
    state = const BatchSelectionState();
  }

  Future<BatchActionResult> batchUpdateTags(List<String> tags) => _execute(
    (id) => ref.read(contentActionsProvider.notifier).updateContent(id, {
      'tags': tags,
    }),
  );

  Future<BatchActionResult> batchSetNsfw(bool isNsfw) => _execute(
    (id) => ref.read(contentActionsProvider.notifier).updateContent(id, {
      'is_nsfw': isNsfw,
    }),
  );

  Future<BatchActionResult> batchDelete() => _execute(
    (id) => ref.read(contentActionsProvider.notifier).deleteContent(id),
  );

  Future<BatchActionResult> batchReParse() =>
      _execute((id) => ref.read(contentActionsProvider.notifier).reParse(id));

  Future<BatchActionResult> _execute(
    Future<ContentActionResult> Function(int id) action,
  ) async {
    if (state.isProcessing) throw StateError('已有批量操作正在执行');
    final ids = state.selectedIds.toList(growable: false);
    if (ids.isEmpty) return const BatchActionResult(0, {});
    final lease = ref.keepAlive();
    state = state.copyWith(isProcessing: true);
    final failures = <int, String>{};
    var completed = 0;
    try {
      for (final id in ids) {
        ContentActionResult result;
        try {
          result = await action(id);
        } catch (_) {
          result = const ContentActionResult.failure('操作未完成，请检查内容状态后重试');
        }
        if (result.ok) {
          completed++;
        } else {
          failures[id] = result.message;
        }
      }
      // A retry acts only on failures, never on already accepted side effects.
      state = BatchSelectionState(
        selectedIds: failures.keys.toSet(),
        isSelectionMode: failures.isNotEmpty,
      );
      return BatchActionResult(completed, failures);
    } finally {
      if (ref.mounted && state.isProcessing) {
        state = state.copyWith(isProcessing: false);
      }
      lease.close();
    }
  }
}

class BatchSelectionState {
  final Set<int> selectedIds;
  final bool isSelectionMode;
  final bool isProcessing;

  const BatchSelectionState({
    this.selectedIds = const {},
    this.isSelectionMode = false,
    this.isProcessing = false,
  });

  BatchSelectionState copyWith({
    Set<int>? selectedIds,
    bool? isSelectionMode,
    bool? isProcessing,
  }) {
    return BatchSelectionState(
      selectedIds: selectedIds ?? this.selectedIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }

  int get count => selectedIds.length;
  bool isSelected(int id) => selectedIds.contains(id);
}

class BatchActionResult {
  const BatchActionResult(this.completed, this.failures);
  final int completed;
  final Map<int, String> failures;
  bool get hasFailures => failures.isNotEmpty;
}
