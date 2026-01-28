import 'package:freezed_annotation/freezed_annotation.dart';

part 'rule_preview.freezed.dart';
part 'rule_preview.g.dart';

@freezed
abstract class RulePreviewItem with _$RulePreviewItem {
  const factory RulePreviewItem({
    @JsonKey(name: 'content_id') required int contentId,
    String? title,
    required String platform,
    @Default([]) List<String> tags,
    @JsonKey(name: 'is_nsfw') @Default(false) bool isNsfw,
    required String status,
    String? reason,
    @JsonKey(name: 'scheduled_time') DateTime? scheduledTime,
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
  }) = _RulePreviewItem;

  factory RulePreviewItem.fromJson(Map<String, dynamic> json) =>
      _$RulePreviewItemFromJson(json);
}

@freezed
abstract class RulePreviewResponse with _$RulePreviewResponse {
  const factory RulePreviewResponse({
    @JsonKey(name: 'rule_id') required int ruleId,
    @JsonKey(name: 'rule_name') required String ruleName,
    @JsonKey(name: 'total_matched') required int totalMatched,
    @JsonKey(name: 'will_push_count') required int willPushCount,
    @JsonKey(name: 'filtered_count') required int filteredCount,
    @JsonKey(name: 'pending_review_count') required int pendingReviewCount,
    @JsonKey(name: 'rate_limited_count') required int rateLimitedCount,
    required List<RulePreviewItem> items,
  }) = _RulePreviewResponse;

  factory RulePreviewResponse.fromJson(Map<String, dynamic> json) =>
      _$RulePreviewResponseFromJson(json);
}

@freezed
abstract class RulePreviewStats with _$RulePreviewStats {
  const factory RulePreviewStats({
    @JsonKey(name: 'rule_id') required int ruleId,
    @JsonKey(name: 'rule_name') required String ruleName,
    @JsonKey(name: 'will_push') required int willPush,
    required int filtered,
    @JsonKey(name: 'pending_review') required int pendingReview,
    @JsonKey(name: 'rate_limited') required int rateLimited,
  }) = _RulePreviewStats;

  factory RulePreviewStats.fromJson(Map<String, dynamic> json) =>
      _$RulePreviewStatsFromJson(json);
}

enum PreviewItemStatus {
  willPush('will_push', '将推送', 0xFF4CAF50),
  filteredNsfw('filtered_nsfw', 'NSFW过滤', 0xFFE91E63),
  filteredTag('filtered_tag', '标签过滤', 0xFFFF9800),
  filteredPlatform('filtered_platform', '平台过滤', 0xFF9E9E9E),
  pendingReview('pending_review', '待审批', 0xFF2196F3),
  rateLimited('rate_limited', '限流', 0xFFFF5722),
  alreadyPushed('already_pushed', '已推送', 0xFF607D8B);

  const PreviewItemStatus(this.value, this.label, this.color);
  final String value;
  final String label;
  final int color;

  static PreviewItemStatus fromValue(String value) {
    return PreviewItemStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PreviewItemStatus.filteredPlatform,
    );
  }
}
