import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../theme/design_tokens.dart';
import '../settings/presentation/tabs/connection_tab.dart';
import '../settings/providers/platform_health_provider.dart';

class AccountCenterPage extends ConsumerWidget {
  const AccountCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = WindowMetrics.of(context);
    final horizontalPadding = metrics.widthClass.isCompact
        ? 0.0
        : AppSpacing.xl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('账号中心'),
        actions: [
          IconButton(
            tooltip: '刷新账号状态',
            onPressed: () => ref.invalidate(platformHealthProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: ConnectionTab(
                accountsOnly: true,
                onOpenPlatform: (platform) =>
                    context.push('/accounts/${platform.platform}'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
