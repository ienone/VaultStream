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

  const CollectionFilterState({
    this.platforms = const [],
    this.statuses = const [],
    this.author,
    this.dateRange,
    this.searchQuery = '',
    this.tags = const [],
  });

  CollectionFilterState copyWith({
    List<String>? platforms,
    List<String>? statuses,
    String? author,
    DateTimeRange? dateRange,
    String? searchQuery,
    List<String>? tags,
    bool clearPlatforms = false,
    bool clearStatuses = false,
    bool clearDateRange = false,
    bool clearTags = false,
  }) {
    return CollectionFilterState(
      platforms: clearPlatforms ? const [] : (platforms ?? this.platforms),
      statuses: clearStatuses ? const [] : (statuses ?? this.statuses),
      author: author ?? this.author,
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      searchQuery: searchQuery ?? this.searchQuery,
      tags: clearTags ? const [] : (tags ?? this.tags),
    );
  }

  bool get hasActiveFilters =>
      platforms.isNotEmpty ||
      statuses.isNotEmpty ||
      author != null ||
      dateRange != null ||
      tags.isNotEmpty;
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
  }) {
    state = state.copyWith(
      platforms: platforms,
      statuses: statuses,
      author: author,
      dateRange: dateRange,
      tags: tags,
      clearPlatforms: platforms == null || platforms.isEmpty,
      clearStatuses: statuses == null || statuses.isEmpty,
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
}
