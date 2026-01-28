import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/rule_preview.dart';

part 'rule_preview_provider.g.dart';

@riverpod
class SelectedRuleId extends _$SelectedRuleId {
  @override
  int? build() => null;

  void select(int? id) {
    state = id;
  }
}

@riverpod
Future<RulePreviewResponse> rulePreview(
  Ref ref,
  int ruleId, {
  int hoursAhead = 24,
  int limit = 50,
}) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(
    '/distribution-rules/$ruleId/preview',
    queryParameters: {
      'hours_ahead': hoursAhead,
      'limit': limit,
    },
  );
  return RulePreviewResponse.fromJson(response.data);
}

@riverpod
Future<List<RulePreviewStats>> allRulesPreviewStats(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/distribution-rules/preview/stats');
  return (response.data as List)
      .map((e) => RulePreviewStats.fromJson(e as Map<String, dynamic>))
      .toList();
}
