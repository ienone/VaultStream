import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/distribution_target.dart';

part 'distribution_targets_provider.g.dart';

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

  Future<DistributionTarget> createTarget(
    int ruleId,
    DistributionTargetCreate target,
  ) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.post(
      '/distribution-rules/$ruleId/targets',
      data: target.toJson(),
    );
    final newTarget = DistributionTarget.fromJson(response.data);
    ref.invalidateSelf();
    return newTarget;
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
