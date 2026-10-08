import 'package:frontend/core/network/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/toast.dart';
import 'models/distribution_rule.dart';
import 'models/distribution_target.dart';
import 'providers/bot_chats_provider.dart';
import 'providers/distribution_rules_provider.dart';
import 'providers/distribution_targets_provider.dart';
import 'providers/queue_provider.dart';
import 'providers/rule_editor_key_provider.dart';
import 'widgets/distribution_rule_editor.dart';

class DistributionRulePage extends ConsumerWidget {
  const DistributionRulePage({super.key, required this.routeKey, this.ruleId});

  final ValueKey<String> routeKey;

  final int? ruleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorKey = ref.watch(ruleEditorKeyProvider(routeKey));
    final chatsAsync = ref.watch(botChatsProvider);
    final ruleAsync = ruleId == null
        ? const AsyncValue<DistributionRule?>.data(null)
        : ref.watch(distributionRuleDetailProvider(ruleId!));
    final targetsAsync = ruleId == null
        ? const AsyncValue<List<DistributionTarget>>.data([])
        : ref.watch(distributionTargetsProvider(ruleId!));

    final body = SafeArea(
      child: switch ((chatsAsync, ruleAsync, targetsAsync)) {
        (
          AsyncValue(hasValue: true, value: final chats?),
          AsyncValue(hasValue: true, value: final rule),
          AsyncValue(hasValue: true, value: final targets?),
        ) =>
          Center(
            child: DistributionRuleEditor(
              key: editorKey,
              rule: rule,
              onManageTargets: () => context.push('/settings?tab=targets'),
              availableChats: chats,
              initialSelectedChatIds: targets
                  .map((target) => target.botChatId)
                  .toList(growable: false),
              onCancel: () => context.go('/automation/distribution'),
              onSave: (data, chatIds) => _save(context, ref, data, chatIds),
            ),
          ),
        (AsyncError(error: final error), _, _) ||
        (_, AsyncError(error: final error), _) ||
        (_, _, AsyncError(error: final error)) => _RuleLoadError(
          error: error,
          onRetry: () {
            ref.invalidate(botChatsProvider);
            if (ruleId case final id?) {
              ref.invalidate(distributionRuleDetailProvider(id));
              ref.invalidate(distributionTargetsProvider(id));
            }
          },
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
    return body;
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    DistributionRuleCreate data,
    List<int> chatIds,
  ) async {
    try {
      final actions = ref.read(distributionRulesProvider.notifier);
      if (ruleId == null) {
        await actions.createRule(data, chatIds: chatIds);
      } else {
        await actions.updateRule(
          ruleId!,
          DistributionRuleUpdate.fromJson(data.toJson()),
          chatIds: chatIds,
        );
        ref.invalidate(distributionRuleDetailProvider(ruleId!));
        ref.invalidate(distributionTargetsProvider(ruleId!));
      }
      ref.invalidate(botChatsProvider);
      ref.invalidate(contentQueueProvider);
      ref.invalidate(queueStatsProvider);
      if (context.mounted) {
        Toast.show(context, '规则已保存');
        ref
            .read(ruleEditorKeyProvider(routeKey))
            .currentState
            ?.allowExitAfterSave();
        context.go('/automation/distribution');
      }
    } catch (error) {
      if (context.mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(error, fallbackMessage: '保存失败'),
          isError: true,
        );
      }
    }
  }
}

class _RuleLoadError extends StatelessWidget {
  const _RuleLoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              formatApiErrorMessage(error, fallbackMessage: '无法加载分发规则'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
