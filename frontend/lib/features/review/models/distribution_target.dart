import 'package:freezed_annotation/freezed_annotation.dart';

part 'distribution_target.freezed.dart';
part 'distribution_target.g.dart';

@freezed
abstract class DistributionTarget with _$DistributionTarget {
  const factory DistributionTarget({
    required int id,
    @JsonKey(name: 'rule_id') required int ruleId,
    @JsonKey(name: 'bot_chat_id') required int botChatId,
    @Default(true) bool enabled,
    @JsonKey(name: 'merge_forward') @Default(false) bool mergeForward,
    @JsonKey(name: 'use_author_name') @Default(true) bool useAuthorName,
    String? summary,
    @JsonKey(name: 'render_config_override')
    Map<String, dynamic>? renderConfigOverride,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _DistributionTarget;

  factory DistributionTarget.fromJson(Map<String, dynamic> json) =>
      _$DistributionTargetFromJson(json);
}

@freezed
abstract class DistributionTargetCreate with _$DistributionTargetCreate {
  const factory DistributionTargetCreate({
    @JsonKey(name: 'bot_chat_id') required int botChatId,
    @Default(true) bool enabled,
    @JsonKey(name: 'merge_forward') @Default(false) bool mergeForward,
    @JsonKey(name: 'use_author_name') @Default(true) bool useAuthorName,
    String? summary,
    @JsonKey(name: 'render_config_override')
    Map<String, dynamic>? renderConfigOverride,
  }) = _DistributionTargetCreate;

  factory DistributionTargetCreate.fromJson(Map<String, dynamic> json) =>
      _$DistributionTargetCreateFromJson(json);
}

@freezed
abstract class DistributionTargetUpdate with _$DistributionTargetUpdate {
  const factory DistributionTargetUpdate({
    bool? enabled,
    @JsonKey(name: 'merge_forward') bool? mergeForward,
    @JsonKey(name: 'use_author_name') bool? useAuthorName,
    String? summary,
    @JsonKey(name: 'render_config_override')
    Map<String, dynamic>? renderConfigOverride,
  }) = _DistributionTargetUpdate;

  factory DistributionTargetUpdate.fromJson(Map<String, dynamic> json) =>
      _$DistributionTargetUpdateFromJson(json);
}
