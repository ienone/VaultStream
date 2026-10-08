import '../../routing/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/design_tokens.dart';
import '../settings/presentation/tabs/connection_tab.dart';
import '../settings/providers/platform_health_provider.dart';

class AccountCenterPage extends ConsumerWidget {
  const AccountCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(platformHealthProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('账号中心'),
        actions: [
          IconButton(
            tooltip: '刷新账号状态',
            onPressed: health.isLoading
                ? null
                : () => ref.invalidate(platformHealthProvider),
            icon: health.isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
          child: ConnectionTab(
            accountsOnly: true,
            onOpenPlatform: (platform) =>
                context.push('/accounts/${platform.platform}'),
          ),
        ),
      ),
    );
  }
}
