// ignore_for_file: use_null_aware_elements

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/bot_chat.dart';

part 'bot_chats_provider.g.dart';

@riverpod
class BotChats extends _$BotChats {
  @override
  FutureOr<List<BotChat>> build() async {
    return _fetchChats();
  }

  Future<List<BotChat>> _fetchChats({bool? enabled, String? chatType}) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.get(
      '/bot/chats',
      queryParameters: {
        if (enabled case final enabled?) 'enabled': enabled,
        if (chatType case final chatType?) 'chat_type': chatType,
      },
    );
    return (response.data as List)
        .map((e) => BotChat.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BotChat> createChat(BotChatCreate chat) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.post('/bot/chats', data: chat.toJson());
    final newChat = BotChat.fromJson(response.data);
    ref.invalidateSelf();
    return newChat;
  }

  Future<BotChat> updateChat(
    int botChatId,
    BotChatUpdate update, {
    String? newChatId,
  }) async {
    final dio = ref.watch(apiClientProvider);
    final payload = <String, dynamic>{...update.toJson()};
    if (newChatId case final id?) {
      payload['chat_id'] = id;
    }
    final response = await dio.patch('/bot/chats/$botChatId', data: payload);
    final updatedChat = BotChat.fromJson(response.data);
    ref.invalidateSelf();
    return updatedChat;
  }

  Future<void> updateChatStatus(
    int botChatId, {
    bool? isMonitoring,
    bool? isPushTarget,
    bool? enabled,
  }) async {
    final dio = ref.read(apiClientProvider);
    await dio.patch(
      '/bot/chats/$botChatId',
      data: {
        if (isMonitoring != null) 'is_monitoring': isMonitoring,
        if (isPushTarget != null) 'is_push_target': isPushTarget,
        if (enabled != null) 'enabled': enabled,
      },
    );
    ref.invalidateSelf();
  }

  Future<void> toggleChat(int botChatId) async {
    final dio = ref.watch(apiClientProvider);
    await dio.post('/bot/chats/$botChatId/toggle');
    ref.invalidateSelf();
  }

  Future<void> deleteChat(int botChatId) async {
    final dio = ref.watch(apiClientProvider);
    await dio.delete('/bot/chats/$botChatId');
    ref.invalidateSelf();
  }

  Future<BotSyncResult> syncChats({String? chatId}) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.post(
      '/bot/chats/sync',
      data: chatId != null ? {'chat_id': chatId} : {},
    );
    ref.invalidateSelf();
    return BotSyncResult.fromJson(response.data);
  }
}

@riverpod
Future<BotStatus> botStatus(Ref ref) async {
  // 不使用 keepAlive，页面切换时自动重新获取最新状态
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/bot/status');
  return BotStatus.fromJson(response.data);
}

@riverpod
Future<BotRuntime> botRuntime(Ref ref) async {
  ref.keepAlive();
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(
    '/bot/runtime',
    queryParameters: {'platform': 'telegram'},
  );
  return BotRuntime.fromJson(response.data);
}

@riverpod
Future<BotChat> botChatDetail(Ref ref, int botChatId) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/bot/chats/$botChatId');
  return BotChat.fromJson(response.data);
}
