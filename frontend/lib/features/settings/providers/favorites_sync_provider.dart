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
    required this.recentRuns,
    required this.platforms,
  });

  final bool running;
  final int intervalMinutes;
  final int maxItems;
  final List<String> enabledPlatforms;
  final String? lastSyncAt;
  final List<Map<String, dynamic>> recentRuns;
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
      recentRuns: json['recent_runs'] is List
          ? (json['recent_runs'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const <Map<String, dynamic>>[],
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

class FavoritesSyncPlatformPreview {
  const FavoritesSyncPlatformPreview({
    required this.platform,
    required this.status,
    required this.authenticated,
    required this.maxItems,
    required this.cursorPresent,
    required this.fetched,
    required this.unique,
    required this.existing,
    required this.estimatedNew,
    required this.skipped,
    required this.nextCursorAvailable,
    required this.error,
    required this.errorCode,
    required this.errorHint,
    required this.authRequired,
    required this.retryable,
    required this.items,
  });

  final String platform;
  final String status;
  final bool authenticated;
  final int maxItems;
  final bool cursorPresent;
  final int fetched;
  final int unique;
  final int existing;
  final int estimatedNew;
  final int skipped;
  final bool nextCursorAvailable;
  final String? error;
  final String? errorCode;
  final String? errorHint;
  final bool authRequired;
  final bool retryable;
  final List<Map<String, dynamic>> items;

  factory FavoritesSyncPlatformPreview.fromJson(Map<String, dynamic> json) {
    return FavoritesSyncPlatformPreview(
      platform: (json['platform'] ?? '').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      authenticated: json['authenticated'] == true,
      maxItems: _asInt(json['max_items']),
      cursorPresent: json['cursor_present'] == true,
      fetched: _asInt(json['fetched']),
      unique: _asInt(json['unique']),
      existing: _asInt(json['existing']),
      estimatedNew: _asInt(json['estimated_new']),
      skipped: _asInt(json['skipped']),
      nextCursorAvailable: json['next_cursor_available'] == true,
      error: json['error']?.toString(),
      errorCode: json['error_code']?.toString(),
      errorHint: json['error_hint']?.toString(),
      authRequired: json['auth_required'] == true,
      retryable: json['retryable'] == true,
      items: json['items'] is List
          ? (json['items'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const <Map<String, dynamic>>[],
    );
  }
}

class FavoritesSyncPreview {
  const FavoritesSyncPreview({
    required this.platform,
    required this.status,
    required this.fetched,
    required this.unique,
    required this.existing,
    required this.estimatedNew,
    required this.skipped,
    required this.platforms,
  });

  final String platform;
  final String status;
  final int fetched;
  final int unique;
  final int existing;
  final int estimatedNew;
  final int skipped;
  final List<FavoritesSyncPlatformPreview> platforms;

  bool get hasFailures => platforms.any((item) => item.status == 'failed');

  factory FavoritesSyncPreview.fromJson(Map<String, dynamic> json) {
    final platforms = json['platforms'];
    return FavoritesSyncPreview(
      platform: (json['platform'] ?? 'all').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      fetched: _asInt(json['fetched']),
      unique: _asInt(json['unique']),
      existing: _asInt(json['existing']),
      estimatedNew: _asInt(json['estimated_new']),
      skipped: _asInt(json['skipped']),
      platforms: platforms is List
          ? platforms
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .map(FavoritesSyncPlatformPreview.fromJson)
                .toList()
          : const <FavoritesSyncPlatformPreview>[],
    );
  }
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

final favoritesSyncStatusProvider = FutureProvider<FavoritesSyncStatus>((
  ref,
) async {
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

  Future<String?> triggerSync({String? platform}) async {
    final dio = _ref.read(apiClientProvider);
    final payload = <String, dynamic>{};
    if (platform != null && platform.isNotEmpty) {
      payload['platform'] = platform;
    }
    final response = await dio.post('/favorites-sync/sync', data: payload);
    _ref.invalidate(favoritesSyncStatusProvider);
    final data = response.data;
    if (data is Map && data['run_id'] != null) {
      return data['run_id'].toString();
    }
    return null;
  }

  Future<FavoritesSyncPreview> previewSync({String? platform}) async {
    final dio = _ref.read(apiClientProvider);
    final payload = <String, dynamic>{};
    if (platform != null && platform.isNotEmpty) {
      payload['platform'] = platform;
    }
    final response = await dio.post('/favorites-sync/preview', data: payload);
    final data = response.data as Map<String, dynamic>;
    return FavoritesSyncPreview.fromJson(data);
  }

  Future<String?> retryRun(String runId) async {
    final dio = _ref.read(apiClientProvider);
    final response = await dio.post('/favorites-sync/runs/$runId/retry');
    _ref.invalidate(favoritesSyncStatusProvider);
    final data = response.data;
    if (data is Map && data['run_id'] != null) {
      return data['run_id'].toString();
    }
    return null;
  }
}
