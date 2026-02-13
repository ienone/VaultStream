import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/distribution_rule.dart';

part 'distribution_rules_provider.g.dart';

@riverpod
class DistributionRules extends _$DistributionRules {
  @override
  FutureOr<List<DistributionRule>> build() async {
    return _fetchRules();
  }

  Future<List<DistributionRule>> _fetchRules({bool? enabled}) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.get(
      '/distribution-rules',
      queryParameters: {if (enabled != null) 'enabled': enabled},
    );
    return (response.data as List)
        .map((e) => DistributionRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DistributionRule> createRule(DistributionRuleCreate rule) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.post(
      '/distribution-rules',
      data: rule.toJson(),
    );
    final newRule = DistributionRule.fromJson(response.data);
    ref.invalidateSelf();
    return newRule;
  }

  Future<DistributionRule> updateRule(int id, DistributionRuleUpdate update) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.patch(
      '/distribution-rules/$id',
      data: update.toJson(),
    );
    final updatedRule = DistributionRule.fromJson(response.data);
    ref.invalidateSelf();
    return updatedRule;
  }

  Future<void> toggleEnabled(int id, bool enabled) async {
    await updateRule(id, DistributionRuleUpdate(enabled: enabled));
  }

  Future<void> deleteRule(int id) async {
    final dio = ref.watch(apiClientProvider);
    await dio.delete('/distribution-rules/$id');
    ref.invalidateSelf();
  }
}

@riverpod
Future<DistributionRule> distributionRuleDetail(Ref ref, int id) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/distribution-rules/$id');
  return DistributionRule.fromJson(response.data);
}
