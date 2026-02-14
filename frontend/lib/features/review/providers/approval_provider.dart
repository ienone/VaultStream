// ignore_for_file: use_null_aware_elements

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../../collection/models/content.dart';

part 'approval_provider.g.dart';

typedef ApprovalListResponse = ShareCardListResponse;

@riverpod
class ApprovalFilter extends _$ApprovalFilter {
  @override
  ApprovalFilterState build() {
    return const ApprovalFilterState();
  }

  void setReviewStatus(String? status) {
    state = state.copyWith(reviewStatus: status);
  }

  void setPlatform(String? platform) {
    state = state.copyWith(platform: platform);
  }

  void clear() {
    state = const ApprovalFilterState();
  }
}

class ApprovalFilterState {
  final String? reviewStatus;
  final String? platform;
  final int page;
  final int size;

  const ApprovalFilterState({
    this.reviewStatus = 'PENDING',
    this.platform,
    this.page = 1,
    this.size = 20,
  });

  ApprovalFilterState copyWith({
    String? reviewStatus,
    String? platform,
    int? page,
    int? size,
  }) {
    return ApprovalFilterState(
      reviewStatus: reviewStatus ?? this.reviewStatus,
      platform: platform ?? this.platform,
      page: page ?? this.page,
      size: size ?? this.size,
    );
  }
}

@riverpod
class ApprovalQueue extends _$ApprovalQueue {
  @override
  FutureOr<ApprovalListResponse> build() async {
    final filter = ref.watch(approvalFilterProvider);
    return _fetchQueue(
      reviewStatus: filter.reviewStatus,
      platform: filter.platform,
      page: filter.page,
      size: filter.size,
    );
  }

  Future<ApprovalListResponse> _fetchQueue({
    String? reviewStatus,
    String? platform,
    int page = 1,
    int size = 20,
  }) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.get(
      '/cards',
      queryParameters: {
        'page': page,
        'size': size,
        if (reviewStatus case final reviewStatus?)
          'review_status': reviewStatus,
        if (platform case final platform?) 'platform': platform,
      },
    );
    return ApprovalListResponse.fromJson(response.data);
  }

  Future<void> approveContent(
    int id, {
    String? note,
    String? reviewedBy,
  }) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/cards/$id/review',
      data: {
        'action': 'approve',
        if (note case final note?) 'note': note,
        if (reviewedBy case final reviewedBy?) 'reviewed_by': reviewedBy,
      },
    );
    _safeInvalidate();
  }

  Future<void> rejectContent(int id, {String? note, String? reviewedBy}) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/cards/$id/review',
      data: {
        'action': 'reject',
        if (note case final note?) 'note': note,
        if (reviewedBy case final reviewedBy?) 'reviewed_by': reviewedBy,
      },
    );
    _safeInvalidate();
  }

  Future<void> batchApprove(
    List<int> ids, {
    String? note,
    String? reviewedBy,
  }) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/cards/batch-review',
      data: {
        'content_ids': ids,
        'action': 'approve',
        if (note case final note?) 'note': note,
        if (reviewedBy case final reviewedBy?) 'reviewed_by': reviewedBy,
      },
    );
    _safeInvalidate();
  }

  Future<void> batchReject(
    List<int> ids, {
    String? note,
    String? reviewedBy,
  }) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/cards/batch-review',
      data: {
        'content_ids': ids,
        'action': 'reject',
        if (note case final note?) 'note': note,
        if (reviewedBy case final reviewedBy?) 'reviewed_by': reviewedBy,
      },
    );
    _safeInvalidate();
  }

  void _safeInvalidate() {
    try {
      ref.invalidateSelf();
    } catch (_) {
      // Provider already disposed, ignore
    }
  }

  Future<void> fetchMore() async {
    if (state.isLoading || state.isRefreshing) return;

    final currentData = state.value;
    if (currentData == null || !currentData.hasMore) return;

    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<ApprovalListResponse>().copyWithPrevious(state);

    try {
      final filter = ref.read(approvalFilterProvider);
      final nextData = await _fetchQueue(
        reviewStatus: filter.reviewStatus,
        platform: filter.platform,
        page: currentData.page + 1,
        size: filter.size,
      );

      state = AsyncData(
        nextData.copyWith(items: [...currentData.items, ...nextData.items]),
      );
    } catch (e, st) {
      // ignore: invalid_use_of_internal_member
      state = AsyncError<ApprovalListResponse>(e, st).copyWithPrevious(state);
    }
  }
}
