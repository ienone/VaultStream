import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class PlatformHealthStatus {
  PlatformHealthStatus.fromJson(Map<String, dynamic> json)
    : platform = json['platform'] as String,
      label = json['label'] as String,
      login = json['login'] as String,
      browserAuthSupported = json['qr_login'] as bool,
      favoritesSupported = json['favorites_supported'] as bool;

  final String platform;
  final String label;
  final String login;
  final bool browserAuthSupported;
  final bool favoritesSupported;
  bool get hasCookie => login != 'not_configured';
}

class PlatformHealthResponse {
  PlatformHealthResponse.fromJson(Map<String, dynamic> json)
    : platforms = (json['platforms'] as List)
          .map(
            (p) => PlatformHealthStatus.fromJson(Map<String, dynamic>.from(p)),
          )
          .toList();
  final List<PlatformHealthStatus> platforms;
}

final platformHealthProvider = FutureProvider<PlatformHealthResponse>((
  ref,
) async {
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  final response = await ref
      .watch(apiClientProvider)
      .get('/platform-health', cancelToken: cancelToken);
  return PlatformHealthResponse.fromJson(
    Map<String, dynamic>.from(response.data as Map),
  );
}, retry: (_, _) => null);
