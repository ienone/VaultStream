import 'package:freezed_annotation/freezed_annotation.dart';

part 'distribution_rule.freezed.dart';
part 'distribution_rule.g.dart';

@freezed
abstract class DistributionRule with _$DistributionRule {
  const factory DistributionRule({
    required int id,
    required String name,
    String? description,
    @JsonKey(name: 'match_conditions')
    required Map<String, dynamic> matchConditions,
    @Default([]) List<Map<String, dynamic>> targets,
    @Default(true) bool enabled,
    @Default(0) int priority,
    @JsonKey(name: 'nsfw_policy') @Default('block') String nsfwPolicy,
    @JsonKey(name: 'approval_required') @Default(false) bool approvalRequired,
    @JsonKey(name: 'auto_approve_conditions')
    Map<String, dynamic>? autoApproveConditions,
    @JsonKey(name: 'rate_limit') int? rateLimit,
    @JsonKey(name: 'time_window') int? timeWindow,
    @JsonKey(name: 'template_id') String? templateId,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _DistributionRule;

  factory DistributionRule.fromJson(Map<String, dynamic> json) =>
      _$DistributionRuleFromJson(json);
}

@freezed
abstract class DistributionRuleCreate with _$DistributionRuleCreate {
  const factory DistributionRuleCreate({
    required String name,
    String? description,
    @JsonKey(name: 'match_conditions')
    required Map<String, dynamic> matchConditions,
    @Default([]) List<Map<String, dynamic>> targets,
    @Default(true) bool enabled,
    @Default(0) int priority,
    @JsonKey(name: 'nsfw_policy') @Default('block') String nsfwPolicy,
    @JsonKey(name: 'approval_required') @Default(false) bool approvalRequired,
    @JsonKey(name: 'auto_approve_conditions')
    Map<String, dynamic>? autoApproveConditions,
    @JsonKey(name: 'rate_limit') int? rateLimit,
    @JsonKey(name: 'time_window') int? timeWindow,
    @JsonKey(name: 'template_id') String? templateId,
  }) = _DistributionRuleCreate;

  factory DistributionRuleCreate.fromJson(Map<String, dynamic> json) =>
      _$DistributionRuleCreateFromJson(json);
}

@freezed
abstract class DistributionRuleUpdate with _$DistributionRuleUpdate {
  const factory DistributionRuleUpdate({
    String? name,
    String? description,
    @JsonKey(name: 'match_conditions') Map<String, dynamic>? matchConditions,
    List<Map<String, dynamic>>? targets,
    bool? enabled,
    int? priority,
    @JsonKey(name: 'nsfw_policy') String? nsfwPolicy,
    @JsonKey(name: 'approval_required') bool? approvalRequired,
    @JsonKey(name: 'auto_approve_conditions')
    Map<String, dynamic>? autoApproveConditions,
    @JsonKey(name: 'rate_limit') int? rateLimit,
    @JsonKey(name: 'time_window') int? timeWindow,
    @JsonKey(name: 'template_id') String? templateId,
  }) = _DistributionRuleUpdate;

  factory DistributionRuleUpdate.fromJson(Map<String, dynamic> json) =>
      _$DistributionRuleUpdateFromJson(json);
}
