import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/distribution_target.dart';

part 'distribution_targets_provider.g.dart';

class DistributionTargetCreateResult {
  final DistributionTarget target;
  final int backfilledCount;

  const DistributionTargetCreateResult({
    required this.target,
    required this.backfilledCount,
  });
}

@riverpod
class DistributionTargets extends _$DistributionTargets {
  @override
  FutureOr<List<DistributionTarget>> build(int ruleId) async {
    return _fetchTargets(ruleId);
  }

  Future<List<DistributionTarget>> _fetchTargets(int ruleId) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.get('/distribution-rules/$ruleId/targets');
    return (response.data as List)
        .map((e) => DistributionTarget.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DistributionTargetCreateResult> createTargetWithResult(
    int ruleId,
    DistributionTargetCreate target, {
    String backfillMode = 'new_only',
    int? backfillRecentDays,
  }) async {
    final dio = ref.watch(apiClientProvider);
    final data = target.toJson();
    data['backfill_mode'] = backfillMode;
    if (backfillRecentDays != null) {
      data['backfill_recent_days'] = backfillRecentDays;
    }
    final response = await dio.post(
      '/distribution-rules/$ruleId/targets',
      data: data,
    );
    final raw = Map<String, dynamic>.from(response.data as Map);
    final newTarget = DistributionTarget.fromJson(raw);
    ref.invalidateSelf();
    return DistributionTargetCreateResult(
      target: newTarget,
      backfilledCount: (raw['backfilled_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<int> previewBackfill(
    int ruleId,
    int botChatId, {
    String backfillMode = 'new_only',
    int? backfillRecentDays,
  }) async {
    if (backfillMode == 'new_only') return 0;
    final dio = ref.watch(apiClientProvider);
    final data = <String, dynamic>{
      'bot_chat_id': botChatId,
      'backfill_mode': backfillMode,
    };
    if (backfillRecentDays != null) {
      data['backfill_recent_days'] = backfillRecentDays;
    }
    final response = await dio.post(
      '/distribution-rules/$ruleId/targets/backfill-preview',
      data: data,
    );
    final raw = Map<String, dynamic>.from(response.data as Map);
    return (raw['candidate_count'] as num?)?.toInt() ?? 0;
  }

  Future<DistributionTarget> updateTarget(
    int ruleId,
    int targetId,
    DistributionTargetUpdate update,
  ) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.patch(
      '/distribution-rules/$ruleId/targets/$targetId',
      data: update.toJson(),
    );
    final updatedTarget = DistributionTarget.fromJson(response.data);
    ref.invalidateSelf();
    return updatedTarget;
  }

  Future<void> deleteTarget(int ruleId, int targetId) async {
    final dio = ref.watch(apiClientProvider);
    await dio.delete('/distribution-rules/$ruleId/targets/$targetId');
    ref.invalidateSelf();
  }
}
