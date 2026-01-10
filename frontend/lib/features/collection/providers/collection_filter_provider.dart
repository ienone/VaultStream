import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'collection_filter_provider.g.dart';

@immutable
class CollectionFilterState {
  final String? platform;
  final String? status;
  final String? author;
  final DateTimeRange? dateRange;
  final String searchQuery;

  const CollectionFilterState({
    this.platform,
    this.status,
    this.author,
    this.dateRange,
    this.searchQuery = '',
  });

  CollectionFilterState copyWith({
    String? platform,
    String? status,
    String? author,
    DateTimeRange? dateRange,
    String? searchQuery,
    bool clearPlatform = false,
    bool clearStatus = false,
    bool clearDateRange = false,
  }) {
    return CollectionFilterState(
      platform: clearPlatform ? null : (platform ?? this.platform),
      status: clearStatus ? null : (status ?? this.status),
      author: author ?? this.author,
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  bool get hasActiveFilters =>
      platform != null || status != null || author != null || dateRange != null;
}

@riverpod
class CollectionFilter extends _$CollectionFilter {
  @override
  CollectionFilterState build() => const CollectionFilterState();

  void updateSearchQuery(String query) =>
      state = state.copyWith(searchQuery: query);

  void setFilters({
    String? platform,
    String? status,
    String? author,
    DateTimeRange? dateRange,
  }) {
    state = state.copyWith(
      platform: platform,
      status: status,
      author: author,
      dateRange: dateRange,
    );
  }

  void clearFilters() {
    state = const CollectionFilterState(searchQuery: '');
  }
}
