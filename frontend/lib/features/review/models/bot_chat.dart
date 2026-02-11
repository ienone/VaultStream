import 'package:freezed_annotation/freezed_annotation.dart';

part 'bot_chat.freezed.dart';
part 'bot_chat.g.dart';

@freezed
abstract class BotChat with _$BotChat {
  const BotChat._();

  const factory BotChat({
    required int id,
    @JsonKey(name: 'chat_id') required String chatId,
    @JsonKey(name: 'chat_type') required String chatType,
    String? title,
    String? username,
    String? description,
    @JsonKey(name: 'member_count') int? memberCount,
    @JsonKey(name: 'is_admin') @Default(false) bool isAdmin,
    @JsonKey(name: 'can_post') @Default(false) bool canPost,
    @Default(true) bool enabled,
    @Default(0) int priority,
    @JsonKey(name: 'nsfw_policy') @Default('inherit') String nsfwPolicy,
    @JsonKey(name: 'nsfw_chat_id') String? nsfwChatId,
    @JsonKey(name: 'tag_filter') @Default([]) List<String> tagFilter,
    @JsonKey(name: 'platform_filter') @Default([]) List<String> platformFilter,
    @JsonKey(name: 'linked_rule_ids') @Default([]) List<int> linkedRuleIds,
    @JsonKey(name: 'total_pushed') @Default(0) int totalPushed,
    @JsonKey(name: 'last_pushed_at') DateTime? lastPushedAt,
    @JsonKey(name: 'is_accessible') @Default(true) bool isAccessible,
    @JsonKey(name: 'last_sync_at') DateTime? lastSyncAt,
    @JsonKey(name: 'sync_error') String? syncError,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _BotChat;

  bool get isChannel => chatType == 'channel';
  bool get isGroup => chatType == 'group' || chatType == 'supergroup' || chatType == 'qq_group';
  bool get isQQ => chatType == 'qq_group' || chatType == 'qq_private';
  bool get isTelegram => !isQQ;

  String get displayName => title ?? username ?? chatId;

  String get chatTypeLabel {
    switch (chatType) {
      case 'channel':
        return 'TG 频道';
      case 'group':
        return 'TG 群组';
      case 'supergroup':
        return 'TG 超级群组';
      case 'private':
        return 'TG 私聊';
      case 'qq_group':
        return 'QQ 群';
      case 'qq_private':
        return 'QQ 私聊';
      default:
        return chatType;
    }
  }

  factory BotChat.fromJson(Map<String, dynamic> json) =>
      _$BotChatFromJson(json);
}

@freezed
abstract class BotChatCreate with _$BotChatCreate {
  const factory BotChatCreate({
    @JsonKey(name: 'chat_id') required String chatId,
    @JsonKey(name: 'chat_type') required String chatType,
    String? title,
    String? username,
    String? description,
    @Default(true) bool enabled,
    @Default(0) int priority,
    @JsonKey(name: 'nsfw_policy') @Default('inherit') String nsfwPolicy,
    @JsonKey(name: 'nsfw_chat_id') String? nsfwChatId,
    @JsonKey(name: 'tag_filter') @Default([]) List<String> tagFilter,
    @JsonKey(name: 'platform_filter') @Default([]) List<String> platformFilter,
    @JsonKey(name: 'linked_rule_ids') @Default([]) List<int> linkedRuleIds,
  }) = _BotChatCreate;

  factory BotChatCreate.fromJson(Map<String, dynamic> json) =>
      _$BotChatCreateFromJson(json);
}

@freezed
abstract class BotChatUpdate with _$BotChatUpdate {
  const factory BotChatUpdate({
    String? title,
    bool? enabled,
    int? priority,
    @JsonKey(name: 'nsfw_policy') String? nsfwPolicy,
    @JsonKey(name: 'nsfw_chat_id') String? nsfwChatId,
    @JsonKey(name: 'tag_filter') List<String>? tagFilter,
    @JsonKey(name: 'platform_filter') List<String>? platformFilter,
    @JsonKey(name: 'linked_rule_ids') List<int>? linkedRuleIds,
  }) = _BotChatUpdate;

  factory BotChatUpdate.fromJson(Map<String, dynamic> json) =>
      _$BotChatUpdateFromJson(json);
}

@freezed
abstract class BotStatus with _$BotStatus {
  const BotStatus._();

  const factory BotStatus({
    @JsonKey(name: 'is_running') required bool isRunning,
    @JsonKey(name: 'bot_username') String? botUsername,
    @JsonKey(name: 'bot_id') int? botId,
    @JsonKey(name: 'connected_chats') required int connectedChats,
    @JsonKey(name: 'total_pushed_today') required int totalPushedToday,
    @JsonKey(name: 'uptime_seconds') int? uptimeSeconds,
    @JsonKey(name: 'napcat_status') String? napcatStatus,
  }) = _BotStatus;

  bool get isNapcatOnline => napcatStatus == 'online';
  bool get isNapcatEnabled => napcatStatus != null;

  String get uptimeFormatted {
    if (uptimeSeconds == null) return '未知';
    final hours = uptimeSeconds! ~/ 3600;
    final minutes = (uptimeSeconds! % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  factory BotStatus.fromJson(Map<String, dynamic> json) =>
      _$BotStatusFromJson(json);
}

@freezed
abstract class BotRuntime with _$BotRuntime {
  const BotRuntime._();

  const factory BotRuntime({
    @JsonKey(name: 'bot_id') String? botId,
    @JsonKey(name: 'bot_username') String? botUsername,
    @JsonKey(name: 'bot_first_name') String? botFirstName,
    @JsonKey(name: 'started_at') DateTime? startedAt,
    @JsonKey(name: 'last_heartbeat_at') DateTime? lastHeartbeatAt,
    @JsonKey(name: 'is_running') required bool isRunning,
    @JsonKey(name: 'uptime_seconds') int? uptimeSeconds,
    String? version,
    @JsonKey(name: 'last_error') String? lastError,
    @JsonKey(name: 'last_error_at') DateTime? lastErrorAt,
  }) = _BotRuntime;

  String get uptimeFormatted {
    if (uptimeSeconds == null) return '未知';
    final hours = uptimeSeconds! ~/ 3600;
    final minutes = (uptimeSeconds! % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  factory BotRuntime.fromJson(Map<String, dynamic> json) =>
      _$BotRuntimeFromJson(json);
}

@freezed
abstract class BotSyncResult with _$BotSyncResult {
  const factory BotSyncResult({
    required int total,
    required int updated,
    required int failed,
    required int inaccessible,
    @Default([]) List<Map<String, dynamic>> details,
  }) = _BotSyncResult;

  factory BotSyncResult.fromJson(Map<String, dynamic> json) =>
      _$BotSyncResultFromJson(json);
}
