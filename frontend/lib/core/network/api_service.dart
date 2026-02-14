import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'api_client.dart';
import '../../features/collection/models/content.dart';
import '../../features/review/models/distribution_rule.dart';
import '../../features/review/models/distribution_target.dart';
import '../../features/review/models/pushed_record.dart';
import '../../features/dashboard/models/stats.dart';
import '../../features/review/models/bot_chat.dart';

part 'api_service.g.dart';

@riverpod
ApiService apiService(Ref ref) {
  final dio = ref.watch(apiClientProvider);
  return ApiService(dio);
}

class ApiService {
  final Dio _dio;

  ApiService(this._dio);

  // ============ Content APIs ============

  Future<ShareCardListResponse> getShareCards({
    int page = 1,
    int size = 20,
    List<String>? tags,
    List<String>? platforms,
    List<String>? statuses,
    String? author,
    DateTime? startDate,
    DateTime? endDate,
    String? query,
  }) async {
    final response = await _dio.get(
      '/cards',
      queryParameters: {
        'page': page,
        'size': size,
        if (tags case final tags? when tags.isNotEmpty) 'tags': tags.join(','),
        if (platforms case final platforms? when platforms.isNotEmpty)
          'platform': platforms.join(','),
        if (statuses case final statuses? when statuses.isNotEmpty)
          'status': statuses.join(','),
        'author': ?author,
        if (startDate != null) 'start_date': startDate.toIso8601String(),
        if (endDate != null) 'end_date': endDate.toIso8601String(),
        'q': ?query,
      },
    );
    return ShareCardListResponse.fromJson(response.data);
  }

  Future<ContentDetail> getContentDetail(int id) async {
    final response = await _dio.get('/contents/$id');
    return ContentDetail.fromJson(response.data);
  }

  Future<ContentDetail> updateContent(
    int id, {
    List<String>? tags,
    String? title,
    String? description,
    String? authorName,
    String? coverUrl,
    bool? isNsfw,
    String? status,
    String? reviewStatus,
    String? reviewNote,
    String? reviewedBy,
  }) async {
    final response = await _dio.patch(
      '/contents/$id',
      data: {
        'tags': ?tags,
        'title': ?title,
        'description': ?description,
        'author_name': ?authorName,
        'cover_url': ?coverUrl,
        'is_nsfw': ?isNsfw,
        'status': ?status,
        'review_status': ?reviewStatus,
        'review_note': ?reviewNote,
        'reviewed_by': ?reviewedBy,
      },
    );
    return ContentDetail.fromJson(response.data);
  }

  Future<void> deleteContent(int id) async {
    await _dio.delete('/contents/$id');
  }

  Future<void> retryContent(int id) async {
    await _dio.post('/contents/$id/retry');
  }

  Future<void> reParseContent(int id) async {
    await _dio.post('/contents/$id/re-parse');
  }

  Future<Map<String, dynamic>> createShare({
    required String url,
    List<String> tags = const [],
    String? source,
    String? note,
    bool isNsfw = false,
  }) async {
    final response = await _dio.post(
      '/shares',
      data: {
        'url': url,
        'tags': tags,
        'source': ?source,
        'note': ?note,
        'is_nsfw': isNsfw,
      },
    );
    return response.data;
  }

  // ============ Batch Operations ============

  Future<Map<String, dynamic>> batchUpdateTags(
    List<int> ids,
    List<String> tags,
  ) async {
    final response = await _dio.post(
      '/contents/batch-update',
      data: {
        'content_ids': ids,
        'updates': {'tags': tags},
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> batchSetNsfw(List<int> ids, bool isNsfw) async {
    final response = await _dio.post(
      '/contents/batch-update',
      data: {
        'content_ids': ids,
        'updates': {'is_nsfw': isNsfw},
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> batchDelete(List<int> ids) async {
    final response = await _dio.post('/contents/batch-delete', data: ids);
    return response.data;
  }

  Future<Map<String, dynamic>> batchReParse(List<int> ids) async {
    final response = await _dio.post('/contents/batch-re-parse', data: ids);
    return response.data;
  }

  // ============ Distribution Rules ============

  Future<List<DistributionRule>> getDistributionRules({bool? enabled}) async {
    final response = await _dio.get(
      '/distribution-rules',
      queryParameters: {'enabled': ?enabled},
    );
    return (response.data as List)
        .map((e) => DistributionRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DistributionRule> getDistributionRule(int id) async {
    final response = await _dio.get('/distribution-rules/$id');
    return DistributionRule.fromJson(response.data);
  }

  Future<DistributionRule> createDistributionRule(
    DistributionRuleCreate rule,
  ) async {
    final response = await _dio.post(
      '/distribution-rules',
      data: rule.toJson(),
    );
    return DistributionRule.fromJson(response.data);
  }

  Future<DistributionRule> updateDistributionRule(
    int id,
    DistributionRuleUpdate update,
  ) async {
    final response = await _dio.patch(
      '/distribution-rules/$id',
      data: update.toJson(),
    );
    return DistributionRule.fromJson(response.data);
  }

  Future<void> deleteDistributionRule(int id) async {
    await _dio.delete('/distribution-rules/$id');
  }

  // ============ Pushed Records ============

  Future<List<PushedRecord>> getPushedRecords({
    int? contentId,
    String? targetId,
    int limit = 50,
  }) async {
    final response = await _dio.get(
      '/pushed-records',
      queryParameters: {
        'content_id': ?contentId,
        'target_id': ?targetId,
        'limit': limit,
      },
    );
    return (response.data as List)
        .map((e) => PushedRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============ Dashboard & Stats ============

  Future<Map<String, dynamic>> getHealth() async {
    final response = await _dio.get('/health');
    return response.data;
  }

  Future<DashboardStats> getDashboardStats() async {
    final response = await _dio.get('/dashboard/stats');
    return DashboardStats.fromJson(response.data);
  }

  Future<QueueOverviewStats> getQueueStats() async {
    final response = await _dio.get('/dashboard/queue');
    return QueueOverviewStats.fromJson(response.data);
  }

  Future<List<TagStats>> getTags() async {
    final response = await _dio.get('/tags');
    return (response.data as List)
        .map((e) => TagStats.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============ Settings ============

  Future<List<Map<String, dynamic>>> getSettings() async {
    final response = await _dio.get('/settings');
    return List<Map<String, dynamic>>.from(response.data);
  }

  Future<Map<String, dynamic>> getSetting(String key) async {
    final response = await _dio.get('/settings/$key');
    return response.data;
  }

  Future<Map<String, dynamic>> updateSetting(
    String key,
    dynamic value, {
    String? description,
  }) async {
    final response = await _dio.put(
      '/settings/$key',
      data: {'value': value, 'description': ?description},
    );
    return response.data;
  }

  Future<void> deleteSetting(String key) async {
    await _dio.delete('/settings/$key');
  }

  // ============ Bot Management ============

  Future<List<BotChat>> getBotChats({bool? enabled, String? chatType}) async {
    final response = await _dio.get(
      '/bot/chats',
      queryParameters: {'enabled': ?enabled, 'chat_type': ?chatType},
    );
    return (response.data as List)
        .map((e) => BotChat.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BotChat> getBotChat(String chatId) async {
    final response = await _dio.get('/bot/chats/$chatId');
    return BotChat.fromJson(response.data);
  }

  Future<BotChat> updateBotChat(
    String chatId, {
    required BotChatUpdate update,
  }) async {
    final response = await _dio.patch(
      '/bot/chats/$chatId',
      data: update.toJson(),
    );
    return BotChat.fromJson(response.data);
  }

  Future<Map<String, dynamic>> toggleBotChat(String chatId) async {
    final response = await _dio.post('/bot/chats/$chatId/toggle');
    return response.data;
  }

  Future<BotSyncResult> syncBotChats({String? chatId}) async {
    final response = await _dio.post(
      '/bot/chats/sync',
      data: chatId != null ? {'chat_id': chatId} : {},
    );
    return BotSyncResult.fromJson(response.data);
  }

  // ============ Distribution Targets ============

  Future<List<DistributionTarget>> getDistributionTargets(int ruleId) async {
    final response = await _dio.get('/distribution-rules/$ruleId/targets');
    return (response.data as List)
        .map((e) => DistributionTarget.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DistributionTarget> createDistributionTarget(
    int ruleId,
    DistributionTargetCreate create,
  ) async {
    final response = await _dio.post(
      '/distribution-rules/$ruleId/targets',
      data: create.toJson(),
    );
    return DistributionTarget.fromJson(response.data);
  }

  Future<DistributionTarget> updateDistributionTarget(
    int ruleId,
    int targetId,
    DistributionTargetUpdate update,
  ) async {
    final response = await _dio.patch(
      '/distribution-rules/$ruleId/targets/$targetId',
      data: update.toJson(),
    );
    return DistributionTarget.fromJson(response.data);
  }

  Future<void> deleteDistributionTarget(int ruleId, int targetId) async {
    await _dio.delete('/distribution-rules/$ruleId/targets/$targetId');
  }
}
