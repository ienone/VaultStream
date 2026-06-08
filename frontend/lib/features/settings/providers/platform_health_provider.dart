import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class PlatformHealthStatus {
  const PlatformHealthStatus({
    required this.platform,
    required this.label,
    required this.health,
    required this.issues,
    required this.auth,
    required this.favoritesSync,
  });

  final String platform;
  final String label;
  final String health;
  final List<String> issues;
  final Map<String, dynamic> auth;
  final Map<String, dynamic> favoritesSync;

  bool get hasCookie => auth['cookie_configured'] == true;
  bool? get browserAuthValid => auth['browser_auth_valid'] is bool
      ? auth['browser_auth_valid'] as bool
      : null;
  bool get favoritesEnabled => favoritesSync['enabled'] == true;
  bool get favoritesSupported => favoritesSync['supported'] == true;
  bool? get favoritesAuthenticated => favoritesSync['authenticated'] is bool
      ? favoritesSync['authenticated'] as bool
      : null;
  Map<String, dynamic>? get lastFavoritesRun =>
      favoritesSync['last_run'] is Map<String, dynamic>
      ? favoritesSync['last_run'] as Map<String, dynamic>
      : null;

  factory PlatformHealthStatus.fromJson(Map<String, dynamic> json) {
    final issues = json['issues'];
    return PlatformHealthStatus(
      platform: (json['platform'] ?? '').toString(),
      label: (json['label'] ?? json['platform'] ?? '').toString(),
      health: (json['health'] ?? 'unknown').toString(),
      issues: issues is List
          ? issues.map((item) => item.toString()).toList()
          : const <String>[],
      auth: json['auth'] is Map
          ? Map<String, dynamic>.from(json['auth'] as Map)
          : const <String, dynamic>{},
      favoritesSync: json['favorites_sync'] is Map
          ? Map<String, dynamic>.from(json['favorites_sync'] as Map)
          : const <String, dynamic>{},
    );
  }
}

class PlatformHealthResponse {
  const PlatformHealthResponse({
    required this.platforms,
    required this.recentFavoritesRuns,
    required this.cookieKeepalive,
  });

  final List<PlatformHealthStatus> platforms;
  final List<Map<String, dynamic>> recentFavoritesRuns;
  final Map<String, dynamic> cookieKeepalive;

  factory PlatformHealthResponse.fromJson(Map<String, dynamic> json) {
    final platforms = json['platforms'];
    final runs = json['recent_favorites_runs'];
    return PlatformHealthResponse(
      platforms: platforms is List
          ? platforms
                .whereType<Map>()
                .map(
                  (item) => PlatformHealthStatus.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const <PlatformHealthStatus>[],
      recentFavoritesRuns: runs is List
          ? runs
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const <Map<String, dynamic>>[],
      cookieKeepalive: json['cookie_keepalive'] is Map
          ? Map<String, dynamic>.from(json['cookie_keepalive'] as Map)
          : const <String, dynamic>{},
    );
  }
}

final platformHealthProvider = FutureProvider<PlatformHealthResponse>((
  ref,
) async {
  final response = await ref.read(apiClientProvider).get('/platform-health');
  return PlatformHealthResponse.fromJson(
    Map<String, dynamic>.from(response.data as Map),
  );
});
