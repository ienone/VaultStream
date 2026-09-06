import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../automation/providers/bot_chats_provider.dart';

final botConfigActionsProvider = Provider<BotConfigActions>((ref) {
  return BotConfigActions(ref);
});

enum TelegramServiceAction { start, stop, restart }

class BotConfigRecord {
  const BotConfigRecord({
    required this.id,
    required this.platform,
    required this.enabled,
    required this.botTokenConfigured,
    this.napcatHttpUrl,
  });

  factory BotConfigRecord.fromJson(Map<String, dynamic> json) {
    return BotConfigRecord(
      id: (json['id'] as num).toInt(),
      platform: json['platform']?.toString() ?? '',
      enabled: json['enabled'] == true,
      botTokenConfigured:
          (json['bot_token_masked']?.toString().trim().isNotEmpty ?? false),
      napcatHttpUrl: json['napcat_http_url']?.toString(),
    );
  }

  final int id;
  final String platform;
  final bool enabled;
  final bool botTokenConfigured;
  final String? napcatHttpUrl;

  bool get hasUsableCredentials => switch (platform) {
    'telegram' => botTokenConfigured,
    'qq' => napcatHttpUrl?.trim().isNotEmpty ?? false,
    _ => false,
  };
}

class BotChatSyncResult {
  const BotChatSyncResult({
    required this.configured,
    this.total = 0,
    this.updated = 0,
    this.created = 0,
    this.failed = 0,
  });

  final bool configured;
  final int total;
  final int updated;
  final int created;
  final int failed;
}

class BotConfigSaveResult {
  const BotConfigSaveResult({
    required this.saved,
    this.configId,
    this.followUpKind,
    this.followUpRunId,
    this.followUpStatus,
    this.followUpError,
  });

  factory BotConfigSaveResult.fromJson(Map<String, dynamic> json) {
    return BotConfigSaveResult(
      saved: true,
      configId: (json['id'] as num?)?.toInt(),
      followUpKind: json['follow_up_kind']?.toString(),
      followUpRunId: json['follow_up_run_id']?.toString(),
      followUpStatus: json['follow_up_status']?.toString(),
      followUpError: json['follow_up_error']?.toString(),
    );
  }

  final bool saved;
  final int? configId;
  final String? followUpKind;
  final String? followUpRunId;
  final String? followUpStatus;
  final String? followUpError;

  bool get followUpFailed => followUpStatus == 'error';
}

/// Bot 配置、进程控制和 chat 同步的前端请求边界。
///
/// 页面负责表单与用户确认；本类拥有 endpoint、payload、动态响应解析和
/// 相关 provider 刷新。
class BotConfigActions {
  const BotConfigActions(this.ref);

  final Ref ref;

  Future<List<BotConfigRecord>> listConfigs() async {
    final response = await ref.read(apiClientProvider).get('/bot-config');
    final data = response.data as List? ?? const [];
    return data
        .map(
          (item) =>
              BotConfigRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<BotConfigSaveResult> saveCredentials({
    required String platform,
    required String telegramToken,
    required String napcatHttpUrl,
  }) async {
    final configs = await listConfigs();
    final existing = configs
        .where((item) => item.platform == platform)
        .firstOrNull;
    final dio = ref.read(apiClientProvider);

    if (platform == 'telegram' && telegramToken.trim().isNotEmpty) {
      final payload = {'bot_token': telegramToken.trim(), 'enabled': true};
      if (existing == null) {
        final response = await dio.post(
          '/bot-config',
          data: {
            'platform': 'telegram',
            'name': 'Main Telegram Bot',
            ...payload,
          },
        );
        ref.invalidate(botStatusProvider);
        return BotConfigSaveResult.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      } else {
        final response = await dio.patch(
          '/bot-config/${existing.id}',
          data: payload,
        );
        ref.invalidate(botStatusProvider);
        return BotConfigSaveResult.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }
    }

    if (platform == 'qq' && napcatHttpUrl.trim().isNotEmpty) {
      final payload = {
        'napcat_http_url': napcatHttpUrl.trim(),
        'enabled': true,
      };
      if (existing == null) {
        final response = await dio.post(
          '/bot-config',
          data: {'platform': 'qq', 'name': 'Main QQ Bot', ...payload},
        );
        ref.invalidate(botStatusProvider);
        return BotConfigSaveResult.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      } else {
        final response = await dio.patch(
          '/bot-config/${existing.id}',
          data: payload,
        );
        ref.invalidate(botStatusProvider);
        return BotConfigSaveResult.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }
    }

    return const BotConfigSaveResult(saved: false);
  }

  Future<void> controlTelegram(TelegramServiceAction action) async {
    await ref
        .read(apiClientProvider)
        .post('/bot-config/service/telegram/${action.name}');
    ref.invalidate(botStatusProvider);
    ref.invalidate(botRuntimeProvider);
  }

  Future<int> resolveEnabledConfigId(String chatType) async {
    final platform = chatType.startsWith('qq_') ? 'qq' : 'telegram';
    final configs = await listConfigs();
    final candidates = configs.where(
      (config) => config.platform == platform && config.enabled,
    );
    if (candidates.isEmpty) {
      throw StateError(
        platform == 'telegram'
            ? '请先在上方配置并启用 Telegram Bot。'
            : '请先在上方配置并启用 QQ Bot。',
      );
    }
    return candidates.first.id;
  }

  Future<BotChatSyncResult> syncConfiguredChats() async {
    final configs = await listConfigs();
    final active = configs.where(
      (config) => config.enabled && config.hasUsableCredentials,
    );
    if (active.isEmpty) {
      return const BotChatSyncResult(configured: false);
    }

    var total = 0;
    var updated = 0;
    var created = 0;
    var failed = 0;
    final dio = ref.read(apiClientProvider);
    for (final config in active) {
      final response = await dio.post('/bot-config/${config.id}/sync-chats');
      final data = Map<String, dynamic>.from(response.data as Map);
      total += (data['total'] as num?)?.toInt() ?? 0;
      updated += (data['updated'] as num?)?.toInt() ?? 0;
      created += (data['created'] as num?)?.toInt() ?? 0;
      failed += (data['failed'] as num?)?.toInt() ?? 0;
    }

    ref.invalidate(botChatsProvider);
    ref.invalidate(botStatusProvider);
    await ref.read(botChatsProvider.future);
    return BotChatSyncResult(
      configured: true,
      total: total,
      updated: updated,
      created: created,
      failed: failed,
    );
  }
}
