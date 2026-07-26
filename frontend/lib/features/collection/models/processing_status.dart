import 'package:freezed_annotation/freezed_annotation.dart';

part 'processing_status.freezed.dart';
part 'processing_status.g.dart';

/// 后处理阶段标识。
///
/// 与后端 `app/schemas/content.py::ProcessingStageKey` 一一对应。
enum ProcessingStageKey {
  @JsonValue('summary')
  summary,
  @JsonValue('semantic_index')
  semanticIndex,
  @JsonValue('archive_media')
  archiveMedia,
  @JsonValue('patrol')
  patrol,
  @JsonValue('distribution')
  distribution,
}

/// 规范化阶段状态。
///
/// 与后端 `ProcessingStageState` 一一对应。UI 只依据本枚举决定
/// 层级、颜色和是否提示用户处理；具体后端条件见 `detailState`。
enum ProcessingStageState {
  @JsonValue('pending')
  pending,
  @JsonValue('running')
  running,
  @JsonValue('success')
  success,
  @JsonValue('partial')
  partial,
  @JsonValue('failed')
  failed,
  @JsonValue('blocked')
  blocked,
  @JsonValue('disabled')
  disabled,
  @JsonValue('not_applicable')
  notApplicable,
}

/// 后处理可执行动作类型。
///
/// 与后端 `ProcessingActionKind` 一一对应。前端按 kind 分发，不解析文案。
enum ProcessingActionKind {
  @JsonValue('generate_summary')
  generateSummary,
  @JsonValue('rebuild_semantic_index')
  rebuildSemanticIndex,
  @JsonValue('retry_semantic_chunk')
  retrySemanticChunk,
  @JsonValue('retry_distribution_item')
  retryDistributionItem,
  @JsonValue('rematch_distribution')
  rematchDistribution,
  @JsonValue('patrol_score')
  patrolScore,
}

@freezed
abstract class ProcessingStageAction with _$ProcessingStageAction {
  const ProcessingStageAction._();

  const factory ProcessingStageAction({
    required ProcessingActionKind kind,
    required String label,
    @JsonKey(name: 'external_effect') @Default(false) bool externalEffect,
    @JsonKey(name: 'target_ids') @Default([]) List<int> targetIds,
  }) = _ProcessingStageAction;

  factory ProcessingStageAction.fromJson(Map<String, dynamic> json) =>
      _$ProcessingStageActionFromJson(json);
}

@freezed
abstract class ProcessingStageFailure with _$ProcessingStageFailure {
  const ProcessingStageFailure._();

  const factory ProcessingStageFailure({
    int? id,
    String? reference,
    String? reason,
    @JsonKey(name: 'error_type') String? errorType,
    @JsonKey(name: 'retry_count') @Default(0) int retryCount,
    @JsonKey(name: 'max_retries') int? maxRetries,
    @Default(false) bool retryable,
    @JsonKey(name: 'occurred_at') DateTime? occurredAt,
  }) = _ProcessingStageFailure;

  factory ProcessingStageFailure.fromJson(Map<String, dynamic> json) =>
      _$ProcessingStageFailureFromJson(json);

  /// 是否还有剩余重试次数。`maxRetries` 缺失时不做推断。
  bool get hasRemainingAttempts => retryable;
}

@freezed
abstract class ProcessingStage with _$ProcessingStage {
  const ProcessingStage._();

  const factory ProcessingStage({
    required ProcessingStageKey key,
    required String label,
    required ProcessingStageState state,
    @JsonKey(name: 'detail_state') required String detailState,
    required String message,
    @Default([]) List<String> issues,
    @Default([]) List<String> hints,
    @Default([]) List<ProcessingStageAction> actions,
    @Default([]) List<ProcessingStageFailure> failures,
    @JsonKey(name: 'failures_total') @Default(0) int failuresTotal,
    @JsonKey(name: 'failures_truncated') @Default(false) bool failuresTruncated,
    @JsonKey(name: 'completed_units') int? completedUnits,
    @JsonKey(name: 'total_units') int? totalUnits,
    @Default({}) Map<String, dynamic> details,
  }) = _ProcessingStage;

  factory ProcessingStage.fromJson(Map<String, dynamic> json) =>
      _$ProcessingStageFromJson(json);

  /// 该阶段是否需要用户关注。
  bool get needsAttention =>
      state == ProcessingStageState.failed ||
      state == ProcessingStageState.partial ||
      state == ProcessingStageState.blocked;

  /// 该阶段是否与当前内容无关，可在紧凑布局中折叠。
  bool get isInactive =>
      state == ProcessingStageState.notApplicable ||
      state == ProcessingStageState.disabled;

  /// 进度分数。仅在后端提供了单元计数时可用。
  double? get progress {
    final total = totalUnits;
    final completed = completedUnits;
    if (total == null || completed == null || total <= 0) return null;
    return (completed / total).clamp(0.0, 1.0);
  }
}

@freezed
abstract class ContentProcessingStatus with _$ContentProcessingStatus {
  const ContentProcessingStatus._();

  const factory ContentProcessingStatus({
    @JsonKey(name: 'content_id') required int contentId,
    @JsonKey(name: 'content_status') required String contentStatus,
    required ProcessingStageState state,
    required List<ProcessingStage> stages,
  }) = _ContentProcessingStatus;

  factory ContentProcessingStatus.fromJson(Map<String, dynamic> json) =>
      _$ContentProcessingStatusFromJson(json);

  /// 需要用户关注的阶段。
  List<ProcessingStage> get attentionStages =>
      stages.where((stage) => stage.needsAttention).toList(growable: false);

  /// 与当前内容相关的阶段（排除不适用和已关闭）。
  List<ProcessingStage> get activeStages =>
      stages.where((stage) => !stage.isInactive).toList(growable: false);
}
