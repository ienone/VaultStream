import 'package:freezed_annotation/freezed_annotation.dart';

part 'queue_item.freezed.dart';
part 'queue_item.g.dart';

enum QueueStatus {
  willPush('will_push', '待推送'),
  filtered('filtered', '不推送'),
  pendingReview('pending_review', '待审批'),
  pushed('pushed', '已推送');

  const QueueStatus(this.value, this.label);
  final String value;
  final String label;

  static QueueStatus fromValue(String value) {
    return QueueStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => QueueStatus.filtered,
    );
  }
}

@freezed
abstract class QueueItem with _$QueueItem {
  const factory QueueItem({
    required int id,
    @JsonKey(name: 'content_id') required int contentId,
    String? title,
    required String platform,
    @Default([]) List<String> tags,
    @JsonKey(name: 'is_nsfw') @Default(false) bool isNsfw,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'author_name') String? authorName,
    required String status,
    String? reason,
    @JsonKey(name: 'scheduled_time') DateTime? scheduledTime,
    @JsonKey(name: 'pushed_at') DateTime? pushedAt,
    @Default(0) int priority,
  }) = _QueueItem;

  factory QueueItem.fromJson(Map<String, dynamic> json) =>
      _$QueueItemFromJson(json);
}

@freezed
abstract class QueueListResponse with _$QueueListResponse {
  const factory QueueListResponse({
    required List<QueueItem> items,
    required int total,
    @JsonKey(name: 'will_push_count') @Default(0) int willPushCount,
    @JsonKey(name: 'filtered_count') @Default(0) int filteredCount,
    @JsonKey(name: 'pending_review_count') @Default(0) int pendingReviewCount,
    @JsonKey(name: 'pushed_count') @Default(0) int pushedCount,
  }) = _QueueListResponse;

  factory QueueListResponse.fromJson(Map<String, dynamic> json) =>
      _$QueueListResponseFromJson(json);
}
