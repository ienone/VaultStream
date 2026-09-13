import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/settings/presentation/tabs/connection_tab.dart';
import 'package:frontend/features/settings/providers/platform_auth_controller.dart';

class _AuthActions extends PlatformAuthActions {
  final pending = Completer<PlatformAuthSession>();
  final cancelled = <String>[];
  @override
  Set<String> build() => {};
  @override
  Future<PlatformAuthSession> startSession(String platform) => pending.future;
  @override
  Future<void> cancelSession(String sessionId) async =>
      cancelled.add(sessionId);
}

void main() {
  for (final delayed in [false, true]) {
    testWidgets(
      'closing login releases ${delayed ? "late" : "active"} server session',
      (tester) async {
        final actions = _AuthActions();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformAuthActionsProvider.overrideWith(() => actions),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const PlatformLoginDialog(
                        platform: 'bilibili',
                        label: 'Bilibili',
                      ),
                    ),
                    child: const Text('login'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('login'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        const session = PlatformAuthSession(
          sessionId: 'session-owned-by-dialog',
          platform: 'bilibili',
          status: 'waiting_scan',
        );
        if (!delayed) {
          actions.pending.complete(session);
          await tester.pump();
        }
        // A system back/Escape dismissal must clean up too, not just Cancel.
        Navigator.of(tester.element(find.byType(PlatformLoginDialog))).pop();
        await tester.pumpAndSettle();
        if (delayed) {
          actions.pending.complete(session);
          await tester.pumpAndSettle();
        }
        expect(actions.cancelled, ['session-owned-by-dialog']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
