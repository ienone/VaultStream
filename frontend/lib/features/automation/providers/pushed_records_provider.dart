// ignore_for_file: use_null_aware_elements

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/pushed_record.dart';

part 'pushed_records_provider.g.dart';

@riverpod
class PushedRecordsFilter extends _$PushedRecordsFilter {
  @override
  PushedRecordsFilterState build() {
    return const PushedRecordsFilterState();
  }

  void setContentId(int? contentId) {
    state = state.copyWith(contentId: contentId);
  }

  void setTargetId(String? targetId) {
    state = state.copyWith(targetId: targetId);
  }

  void setStatus(String? status) {
    state = state.copyWith(status: status);
  }

  void setLimit(int limit) {
    state = state.copyWith(limit: limit);
  }

  void clear() {
    state = const PushedRecordsFilterState();
  }
}

class PushedRecordsFilterState {
  final int? contentId;
  final String? targetId;
  final String? status;
  final int limit;

  const PushedRecordsFilterState({
    this.contentId,
    this.targetId,
    this.status,
    this.limit = 50,
  });

  PushedRecordsFilterState copyWith({
    int? contentId,
    String? targetId,
    String? status,
    int? limit,
  }) {
    return PushedRecordsFilterState(
      contentId: contentId ?? this.contentId,
      targetId: targetId ?? this.targetId,
      status: status ?? this.status,
      limit: limit ?? this.limit,
    );
  }
}

@riverpod
class PushedRecords extends _$PushedRecords {
  @override
  FutureOr<List<PushedRecord>> build() async {
    final filter = ref.watch(pushedRecordsFilterProvider);
    return _fetchRecords(
      contentId: filter.contentId,
      targetId: filter.targetId,
      limit: filter.limit,
    );
  }

  Future<List<PushedRecord>> _fetchRecords({
    int? contentId,
    String? targetId,
    int limit = 50,
  }) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.get(
      '/pushed-records',
      queryParameters: {
        if (contentId case final contentId?) 'content_id': contentId,
        if (targetId case final targetId?) 'target_id': targetId,
        'limit': limit,
      },
    );
    return (response.data as List)
        .map((e) => PushedRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<void> deleteRecord(int id) async {
    final dio = ref.read(apiClientProvider);
    await dio.delete('/pushed-records/$id');
    ref.invalidateSelf();
  }
}
