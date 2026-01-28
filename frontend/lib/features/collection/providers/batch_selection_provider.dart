import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';

part 'batch_selection_provider.g.dart';

@riverpod
class BatchSelection extends _$BatchSelection {
  @override
  BatchSelectionState build() {
    return const BatchSelectionState();
  }

  void toggleSelection(int id) {
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
    state = state.copyWith(
      selectedIds: ids.toSet(),
      isSelectionMode: true,
    );
  }

  void clearSelection() {
    state = const BatchSelectionState();
  }

  void enterSelectionMode() {
    state = state.copyWith(isSelectionMode: true);
  }

  void exitSelectionMode() {
    state = const BatchSelectionState();
  }

  Future<void> batchUpdateTags(List<String> tags) async {
    if (state.selectedIds.isEmpty) return;

    final dio = ref.watch(apiClientProvider);
    state = state.copyWith(isProcessing: true);

    try {
      for (final id in state.selectedIds) {
        await dio.patch('/contents/$id', data: {'tags': tags});
      }
    } finally {
      state = state.copyWith(isProcessing: false);
    }
  }

  Future<void> batchSetNsfw(bool isNsfw) async {
    if (state.selectedIds.isEmpty) return;

    final dio = ref.watch(apiClientProvider);
    state = state.copyWith(isProcessing: true);

    try {
      for (final id in state.selectedIds) {
        await dio.patch('/contents/$id', data: {'is_nsfw': isNsfw});
      }
    } finally {
      state = state.copyWith(isProcessing: false);
    }
  }

  Future<void> batchDelete() async {
    if (state.selectedIds.isEmpty) return;

    final dio = ref.watch(apiClientProvider);
    state = state.copyWith(isProcessing: true);

    try {
      for (final id in state.selectedIds) {
        await dio.delete('/contents/$id');
      }
    } finally {
      state = state.copyWith(isProcessing: false);
    }
  }

  Future<void> batchReParse() async {
    if (state.selectedIds.isEmpty) return;

    final dio = ref.watch(apiClientProvider);
    state = state.copyWith(isProcessing: true);

    try {
      for (final id in state.selectedIds) {
        await dio.post('/contents/$id/re-parse');
      }
    } finally {
      state = state.copyWith(isProcessing: false);
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
