import 'package:freezed_annotation/freezed_annotation.dart';

part 'target_usage_info.freezed.dart';
part 'target_usage_info.g.dart';

@freezed
abstract class TargetUsageInfo with _$TargetUsageInfo {
  const factory TargetUsageInfo({
    @JsonKey(name: 'target_platform') required String targetPlatform,
    @JsonKey(name: 'target_id') required String targetId,
    @Default(true) bool enabled,
    @JsonKey(name: 'rule_count') @Default(0) int ruleCount,
    @JsonKey(name: 'rule_ids') @Default([]) List<int> ruleIds,
    @JsonKey(name: 'rule_names') @Default([]) List<String> ruleNames,
    @JsonKey(name: 'total_pushed') @Default(0) int totalPushed,
    @JsonKey(name: 'last_pushed_at') DateTime? lastPushedAt,
    @JsonKey(name: 'merge_forward') @Default(false) bool mergeForward,
    @JsonKey(name: 'use_author_name') @Default(false) bool useAuthorName,
    @Default('') String summary,
    @JsonKey(name: 'render_config') Map<String, dynamic>? renderConfig,
    @JsonKey(name: 'connection_status') String? connectionStatus,
    @JsonKey(name: 'connection_message') String? connectionMessage,
  }) = _TargetUsageInfo;

  factory TargetUsageInfo.fromJson(Map<String, dynamic> json) =>
      _$TargetUsageInfoFromJson(json);
}
