import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'discovery_filter_provider.g.dart';

@immutable
class DiscoveryFilterState {
  final String? state;
  final bool showAll;
  final String? sourceName;
  final double? scoreMin;
  final double? scoreMax;
  final List<String> tags;
  final String searchQuery;
  final String sortBy;
  final String sortOrder;

  const DiscoveryFilterState({
    this.state,
    this.showAll = false,
    this.sourceName,
    this.scoreMin,
    this.scoreMax,
    this.tags = const [],
    this.searchQuery = '',
    this.sortBy = 'created_at',
    this.sortOrder = 'desc',
  });

  DiscoveryFilterState copyWith({
    String? state,
    bool? showAll,
    String? sourceName,
    double? scoreMin,
    double? scoreMax,
    List<String>? tags,
    String? searchQuery,
    String? sortBy,
    String? sortOrder,
    bool clearState = false,
    bool clearSourceName = false,
    bool clearScoreMin = false,
    bool clearScoreMax = false,
    bool clearTags = false,
  }) {
    return DiscoveryFilterState(
      state: clearState ? null : (state ?? this.state),
      showAll: showAll ?? this.showAll,
      sourceName: clearSourceName ? null : (sourceName ?? this.sourceName),
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
      showAll ||
      sourceName != null ||
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

  void setSourceName(String? name) {
    state = state.copyWith(
      sourceName: name,
      clearSourceName: name == null,
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
    bool showAll = false,
    String? sourceName,
    double? scoreMin,
    double? scoreMax,
    List<String>? tags,
    String? sortBy,
    String? sortOrder,
  }) {
    state = state.copyWith(
      state: discoveryState,
      showAll: showAll,
      sourceName: sourceName,
      scoreMin: scoreMin,
      scoreMax: scoreMax,
      tags: tags,
      sortBy: sortBy ?? state.sortBy,
      sortOrder: sortOrder ?? state.sortOrder,
      clearState: discoveryState == null,
      clearSourceName: sourceName == null,
      clearScoreMin: scoreMin == null,
      clearScoreMax: scoreMax == null,
      clearTags: tags == null || tags.isEmpty,
    );
  }

  void clearFilters() {
    state = const DiscoveryFilterState();
  }

  /// 原子化地将状态重置为指定初始筛选条件（避免 clearFilters+setFilters 两步触发双重重建）
  void resetToFilters({
    String? discoveryState,
    bool showAll = false,
  }) {
    state = DiscoveryFilterState(
      state: discoveryState,
      showAll: showAll,
    );
  }
}
