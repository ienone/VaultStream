class BotConfig {
  const BotConfig({
    required this.id,
    required this.platform,
    required this.name,
    required this.enabled,
    required this.isPrimary,
    required this.chatCount,
    this.botUsername,
    this.napcatHttpUrl,
    this.napcatWsUrl,
  });

  factory BotConfig.fromJson(Map<String, dynamic> json) {
    return BotConfig(
      id: json['id'] as int,
      platform: json['platform']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      enabled: json['enabled'] == true,
      isPrimary: json['is_primary'] != false,
      chatCount: json['chat_count'] is int ? json['chat_count'] as int : 0,
      botUsername: json['bot_username'] as String?,
      napcatHttpUrl: json['napcat_http_url'] as String?,
      napcatWsUrl: json['napcat_ws_url'] as String?,
    );
  }

  final int id;
  final String platform;
  final String name;
  final bool enabled;
  final bool isPrimary;
  final int chatCount;
  final String? botUsername;
  final String? napcatHttpUrl;
  final String? napcatWsUrl;
}
