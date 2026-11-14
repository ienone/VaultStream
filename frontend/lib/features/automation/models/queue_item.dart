import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/media/media_asset.dart';

part 'queue_item.freezed.dart';
part 'queue_item.g.dart';

enum QueueStatus {
  willPush('will_push', '待发送'),
  filtered('filtered', '未发送'),
  history('history', '发送记录');

  const QueueStatus(this.value, this.label);
  final String value;
  final String label;
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
    @JsonKey(name: 'media_assets') @Default([]) List<MediaAsset> mediaAssets,
    required String status,
    @JsonKey(name: 'reason_code') String? reasonCode,
    @JsonKey(name: 'last_error') String? reason,
    @JsonKey(name: 'last_error_at') DateTime? lastErrorAt,
    @JsonKey(name: 'scheduled_at') DateTime? scheduledTime,
    @JsonKey(name: 'completed_at') DateTime? pushedAt,
    @Default(0) int priority,
  }) = _QueueItem;

  const QueueItem._();

  bool get deliveryUnconfirmed => reasonCode == 'delivery_unknown';
  bool get isProcessing => status == 'processing';

  bool get isDeliveryFailure =>
      status == 'failed' &&
      switch (reasonCode) {
        'manual_canceled' ||
        'manual_filtered' ||
        'tags_not_all_matched' ||
        'tags_not_any_matched' ||
        'tags_excluded' ||
        'platform_mismatch' ||
        'content_not_eligible' ||
        'already_pushed_dedupe' ||
        'approval_required' ||
        'manual_ready' ||
        'nsfw_condition_mismatch' ||
        'nsfw_blocked' ||
        'qq_agent_receipt' => false,
        _ => true,
      };

  String? get displayReason => switch (reasonCode) {
    'nsfw_blocked' || 'nsfw_condition_mismatch' => '内容限制，未发送',
    'nsfw_separate_unconfigured_blocked' => '未设置独立接收目标',
    'platform_mismatch' => '不符合平台条件',
    'tags_excluded' ||
    'tags_not_all_matched' ||
    'tags_not_any_matched' => '不符合标签条件',
    'approval_required' => '待确认',
    'already_pushed_dedupe' => '此前已发送',
    'content_not_eligible' => '内容不符合发送条件',
    'target_unavailable' => '接收目标不可用',
    'rule_or_target_disabled' => '规则或目标已停用',
    'manual_filtered' => '已手动跳过',
    'manual_canceled' => '已取消',
    'qq_agent_receipt' => '由助手回复',
    _ => null,
  };

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
