import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'discovery_filter_provider.g.dart';

@immutable
class DiscoveryFilterState {
  final String? state;
  final String? sourceKind;
  final double? scoreMin;
  final double? scoreMax;
  final List<String> tags;
  final String searchQuery;
  final String sortBy;
  final String sortOrder;

  const DiscoveryFilterState({
    this.state,
    this.sourceKind,
    this.scoreMin,
    this.scoreMax,
    this.tags = const [],
    this.searchQuery = '',
    this.sortBy = 'created_at',
    this.sortOrder = 'desc',
  });

  DiscoveryFilterState copyWith({
    String? state,
    String? sourceKind,
    double? scoreMin,
    double? scoreMax,
    List<String>? tags,
    String? searchQuery,
    String? sortBy,
    String? sortOrder,
    bool clearState = false,
    bool clearSourceKind = false,
    bool clearScoreMin = false,
    bool clearScoreMax = false,
    bool clearTags = false,
  }) {
    return DiscoveryFilterState(
      state: clearState ? null : (state ?? this.state),
      sourceKind: clearSourceKind ? null : (sourceKind ?? this.sourceKind),
      scoreMin: clearScoreMin ? null : (scoreMin ?? this.scoreMin),
      scoreMax: clearScoreMax ? null : (scoreMax ?? this.scoreMax),
      tags: clearTags ? const [] : (tags ?? this.tags),
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  bool get hasActiveFilters =>
      state != null ||
      sourceKind != null ||
      scoreMin != null ||
      scoreMax != null ||
      tags.isNotEmpty;
}

@riverpod
class DiscoveryFilter extends _$DiscoveryFilter {
  @override
  DiscoveryFilterState build() => const DiscoveryFilterState();

  void updateSearchQuery(String query) =>
      state = state.copyWith(searchQuery: query);

  void setDiscoveryState(String? discoveryState) {
    state = state.copyWith(
      state: discoveryState,
      clearState: discoveryState == null,
    );
  }

  void setSourceKind(String? kind) {
    state = state.copyWith(
      sourceKind: kind,
      clearSourceKind: kind == null,
    );
  }

  void setScoreRange(double? min, double? max) {
    state = state.copyWith(
      scoreMin: min,
      scoreMax: max,
      clearScoreMin: min == null,
      clearScoreMax: max == null,
    );
  }

  void setFilters({
    String? discoveryState,
    String? sourceKind,
    double? scoreMin,
    double? scoreMax,
    List<String>? tags,
  }) {
    state = state.copyWith(
      state: discoveryState,
      sourceKind: sourceKind,
      scoreMin: scoreMin,
      scoreMax: scoreMax,
      tags: tags,
      clearState: discoveryState == null,
      clearSourceKind: sourceKind == null,
      clearScoreMin: scoreMin == null,
      clearScoreMax: scoreMax == null,
      clearTags: tags == null || tags.isEmpty,
    );
  }

  void clearFilters() {
    state = const DiscoveryFilterState();
  }
}
