import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class FavoritesPlatformStatus {
  const FavoritesPlatformStatus({
    required this.platform,
    required this.enabled,
    required this.available,
    required this.authenticated,
    required this.ratePerMinute,
    required this.lastResult,
    required this.error,
    required this.statusError,
  });

  final String platform;
  final bool enabled;
  final bool available;
  final bool authenticated;
  final double ratePerMinute;
  final Map<String, dynamic>? lastResult;
  final String? error;
  final Map<String, dynamic>? statusError;

  factory FavoritesPlatformStatus.fromJson(Map<String, dynamic> json) {
    final rawRate = json['rate_per_minute'];
    final rate = rawRate is num
        ? rawRate.toDouble()
        : double.tryParse('$rawRate') ?? 0;
    return FavoritesPlatformStatus(
      platform: (json['platform'] ?? '').toString(),
      enabled: json['enabled'] == true,
      available: json['available'] != false,
      authenticated: json['authenticated'] == true,
      ratePerMinute: rate,
      lastResult: json['last_result'] is Map<String, dynamic>
          ? json['last_result'] as Map<String, dynamic>
          : null,
      error: json['error']?.toString(),
      statusError: json['status_error'] is Map<String, dynamic>
          ? json['status_error'] as Map<String, dynamic>
          : null,
    );
  }
}

class FavoritesSyncStatus {
  const FavoritesSyncStatus({
    required this.running,
    required this.intervalMinutes,
    required this.maxItems,
    required this.enabledPlatforms,
    required this.lastSyncAt,
    required this.platforms,
  });

  final bool running;
  final int intervalMinutes;
  final int maxItems;
  final List<String> enabledPlatforms;
  final String? lastSyncAt;
  final List<FavoritesPlatformStatus> platforms;

  factory FavoritesSyncStatus.fromJson(Map<String, dynamic> json) {
    final interval = json['interval_minutes'];
    final max = json['max_items'];
    final enabled = json['enabled_platforms'];
    final list = json['platforms'];

    return FavoritesSyncStatus(
      running: json['running'] == true,
      intervalMinutes: interval is num ? interval.toInt() : 360,
      maxItems: max is num ? max.toInt() : 50,
      enabledPlatforms: enabled is List
          ? enabled.map((e) => e.toString()).toList()
          : const <String>[],
      lastSyncAt: json['last_sync_at']?.toString(),
      platforms: list is List
          ? list
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(FavoritesPlatformStatus.fromJson)
              .toList()
          : const <FavoritesPlatformStatus>[],
    );
  }
}

final favoritesSyncStatusProvider = FutureProvider<FavoritesSyncStatus>((ref) async {
  final dio = ref.read(apiClientProvider);
  final response = await dio.get('/favorites-sync/status');
  final data = response.data as Map<String, dynamic>;
  return FavoritesSyncStatus.fromJson(data);
});

final favoritesSyncActionsProvider = Provider<FavoritesSyncActions>(
  (ref) => FavoritesSyncActions(ref),
);

class FavoritesSyncActions {
  FavoritesSyncActions(this._ref);

  final Ref _ref;

  Future<void> triggerSync({String? platform}) async {
    final dio = _ref.read(apiClientProvider);
    final payload = <String, dynamic>{};
    if (platform != null && platform.isNotEmpty) {
      payload['platform'] = platform;
    }
    await dio.post('/favorites-sync/sync', data: payload);
    _ref.invalidate(favoritesSyncStatusProvider);
  }
}
