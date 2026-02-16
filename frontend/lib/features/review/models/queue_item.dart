import 'package:freezed_annotation/freezed_annotation.dart';

part 'queue_item.freezed.dart';
part 'queue_item.g.dart';

enum QueueStatus {
  willPush('will_push', '待推送'),
  filtered('filtered', '不推送'),
  pendingReview('pending_review', '待审阅'),
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
    @JsonKey(name: 'rule_id') int? ruleId,
    @JsonKey(name: 'bot_chat_id') int? botChatId,
    @JsonKey(name: 'target_id') String? targetId,
    String? title,
    @JsonKey(name: 'source_platform') String? sourcePlatform,
    @JsonKey(name: 'target_platform') required String platform,
    @Default([]) List<String> tags,
    @JsonKey(name: 'is_nsfw') @Default(false) bool isNsfw,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'author_name') String? authorName,
    required String status,
    @JsonKey(name: 'reason_code') String? reasonCode,
    @JsonKey(name: 'last_error') String? reason,
    @JsonKey(name: 'scheduled_at') DateTime? scheduledTime,
    @JsonKey(name: 'completed_at') DateTime? pushedAt,
    @Default(0) int priority,
  }) = _QueueItem;

  const QueueItem._();

  String get displayPlatform => sourcePlatform ?? platform;

  String? get displayReason {
    final message = reason?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }

    return switch (reasonCode) {
      'nsfw_blocked' => 'NSFW 内容被阻止',
      'nsfw_separate_unconfigured_blocked' => 'NSFW 分离路由未配置，已阻止',
      'nsfw_condition_mismatch' => 'NSFW 条件不匹配',
      'platform_mismatch' => '平台条件不匹配',
      'tags_excluded' => '命中排除标签',
      'tags_not_all_matched' => '未命中全部必需标签',
      'tags_not_any_matched' => '未命中任一必需标签',
      'approval_required' => '等待人工审批',
      'already_pushed_dedupe' => '已推送（去重跳过）',
      'content_not_eligible' => '内容状态不满足推送条件',
      'target_unavailable' => '目标不可用，暂缓推送',
      'manual_filtered' => '已手动过滤',
      'manual_canceled' => '已手动取消',
      _ => null,
    };
  }

  factory QueueItem.fromJson(Map<String, dynamic> json) =>
      _$QueueItemFromJson(json);
}

@freezed
abstract class QueueListResponse with _$QueueListResponse {
  const factory QueueListResponse({
    required List<QueueItem> items,
    required int total,
    @Default(1) int page,
    @Default(50) int size,
    @JsonKey(name: 'has_more') @Default(false) bool hasMore,
  }) = _QueueListResponse;

  factory QueueListResponse.fromJson(Map<String, dynamic> json) =>
      _$QueueListResponseFromJson(json);
}
