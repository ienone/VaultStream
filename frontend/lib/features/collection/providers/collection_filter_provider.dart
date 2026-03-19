import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'collection_filter_provider.g.dart';

@immutable
class CollectionFilterState {
  final List<String> platforms;
  final List<String> statuses;
  final String? author;
  final DateTimeRange? dateRange;
  final String searchQuery;
  final List<String> tags;
  final String searchMode; // keyword | semantic
  final int semanticTopK;

  const CollectionFilterState({
    this.platforms = const [],
    this.statuses = const [],
    this.author,
    this.dateRange,
    this.searchQuery = '',
    this.tags = const [],
    this.searchMode = 'keyword',
    this.semanticTopK = 20,
  });

  CollectionFilterState copyWith({
    List<String>? platforms,
    List<String>? statuses,
    String? author,
    DateTimeRange? dateRange,
    String? searchQuery,
    List<String>? tags,
    String? searchMode,
    int? semanticTopK,
    bool clearPlatforms = false,
    bool clearStatuses = false,
    bool clearAuthor = false,
    bool clearDateRange = false,
    bool clearTags = false,
  }) {
    return CollectionFilterState(
      platforms: clearPlatforms ? const [] : (platforms ?? this.platforms),
      statuses: clearStatuses ? const [] : (statuses ?? this.statuses),
      author: clearAuthor ? null : (author ?? this.author),
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      searchQuery: searchQuery ?? this.searchQuery,
      tags: clearTags ? const [] : (tags ?? this.tags),
      searchMode: searchMode ?? this.searchMode,
      semanticTopK: semanticTopK ?? this.semanticTopK,
    );
  }

  bool get hasActiveFilters =>
      platforms.isNotEmpty ||
      statuses.isNotEmpty ||
      author != null ||
      dateRange != null ||
      tags.isNotEmpty;

  bool get isSemantic => searchMode == 'semantic';
}

@riverpod
class CollectionFilter extends _$CollectionFilter {
  @override
  CollectionFilterState build() => const CollectionFilterState();

  void updateSearchQuery(String query) =>
      state = state.copyWith(searchQuery: query);

  void setFilters({
    List<String>? platforms,
    List<String>? statuses,
    String? author,
    DateTimeRange? dateRange,
    List<String>? tags,
    String? searchMode,
    int? semanticTopK,
  }) {
    state = state.copyWith(
      platforms: platforms,
      statuses: statuses,
      author: author,
      dateRange: dateRange,
      tags: tags,
      searchMode: searchMode,
      semanticTopK: semanticTopK,
      clearPlatforms: platforms == null || platforms.isEmpty,
      clearStatuses: statuses == null || statuses.isEmpty,
      clearAuthor: author == null,
      clearDateRange: dateRange == null,
      clearTags: tags == null || tags.isEmpty,
    );
  }

  void toggleTag(String tag) {
    final currentTags = List<String>.from(state.tags);
    if (currentTags.contains(tag)) {
      currentTags.remove(tag);
    } else {
      currentTags.add(tag);
    }
    state = state.copyWith(tags: currentTags);
  }

  void clearFilters() {
    state = const CollectionFilterState(searchQuery: '');
  }

  void setSearchMode(String mode) {
    if (mode != 'keyword' && mode != 'semantic') return;
    state = state.copyWith(searchMode: mode);
  }

  void setSemanticTopK(int topK) {
    final clamped = topK.clamp(1, 100);
    state = state.copyWith(semanticTopK: clamped);
  }
}
