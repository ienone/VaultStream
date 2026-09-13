import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/providers/local_settings_provider.dart';
import 'package:frontend/core/providers/system_status_provider.dart';
import 'package:frontend/features/player/global_playback_controller.dart';
import 'package:frontend/features/player/global_player_widgets.dart';
import 'package:frontend/routing/app_router.dart';

class _Disconnected extends LocalSettings {
  @override
  LocalSettingsState build() =>
      LocalSettingsState(baseUrl: 'http://localhost/api/v1', apiToken: '');
}

class _Status extends SystemStatusNotifier {
  @override
  Future<SystemStatus> build() async => SystemStatus(isLoaded: true);
}

void main() {
  testWidgets('connection page does not restore or reveal private media', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localSettingsProvider.overrideWith(_Disconnected.new),
          systemStatusProvider.overrideWith(_Status.new),
        ],
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(goRouterProvider)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('连接到 VaultStream'), findsOneWidget);
    expect(find.byType(GlobalMiniPlayer), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.exists(globalPlaybackProvider), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
