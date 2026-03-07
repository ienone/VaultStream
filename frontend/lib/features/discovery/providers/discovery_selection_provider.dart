import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'discovery_selection_provider.g.dart';

@riverpod
class DiscoverySelection extends _$DiscoverySelection {
  @override
  DiscoverySelectionState build() {
    return const DiscoverySelectionState();
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
    state = const DiscoverySelectionState();
  }

  void enterSelectionMode() {
    state = state.copyWith(isSelectionMode: true);
  }

  void exitSelectionMode() {
    state = const DiscoverySelectionState();
  }
}

class DiscoverySelectionState {
  final Set<int> selectedIds;
  final bool isSelectionMode;
  final bool isProcessing;

  const DiscoverySelectionState({
    this.selectedIds = const {},
    this.isSelectionMode = false,
    this.isProcessing = false,
  });

  DiscoverySelectionState copyWith({
    Set<int>? selectedIds,
    bool? isSelectionMode,
    bool? isProcessing,
  }) {
    return DiscoverySelectionState(
      selectedIds: selectedIds ?? this.selectedIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }

  int get count => selectedIds.length;
  bool isSelected(int id) => selectedIds.contains(id);
}
