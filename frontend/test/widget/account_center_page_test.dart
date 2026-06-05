import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/features/accounts/account_center_page.dart';
import 'package:frontend/features/settings/providers/platform_health_provider.dart';

void main() {
  testWidgets('AccountCenterPage renders platform health overview', (
    tester,
  ) async {
    final response = PlatformHealthResponse(
      platforms: [
        PlatformHealthStatus(
          platform: 'zhihu',
          label: '知乎',
          health: 'error',
          issues: const ['登录状态不可用'],
          auth: const {
            'cookie_configured': true,
            'browser_auth_supported': true,
            'browser_auth_valid': false,
          },
          favoritesSync: const {
            'supported': true,
            'enabled': true,
            'authenticated': false,
            'last_run': {'status': 'error'},
          },
        ),
        PlatformHealthStatus(
          platform: 'bilibili',
          label: 'Bilibili',
          health: 'inactive',
          issues: const [],
          auth: const {
            'cookie_configured': false,
            'browser_auth_supported': false,
          },
          favoritesSync: const {'supported': false, 'enabled': false},
        ),
      ],
      recentFavoritesRuns: const [
        {'run_id': 'abcdef123456', 'status': 'error', 'scope': 'zhihu'},
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformHealthProvider.overrideWith((ref) async => response),
        ],
        child: const MaterialApp(home: AccountCenterPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账号中心'), findsOneWidget);
    expect(find.text('知乎'), findsOneWidget);
    expect(find.text('登录状态不可用'), findsOneWidget);
    expect(find.text('预览同步'), findsOneWidget);
    expect(find.text('最近收藏同步'), findsOneWidget);
    expect(find.textContaining('abcdef12'), findsOneWidget);
  });
}
