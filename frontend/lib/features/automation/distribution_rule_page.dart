import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/toast.dart';
import '../../theme/design_tokens.dart';
import 'models/distribution_rule.dart';
import 'models/distribution_target.dart';
import 'providers/bot_chats_provider.dart';
import 'providers/distribution_rules_provider.dart';
import 'providers/distribution_targets_provider.dart';
import 'providers/queue_provider.dart';
import 'widgets/distribution_rule_editor.dart';

class DistributionRulePage extends ConsumerWidget {
  const DistributionRulePage({super.key, this.ruleId});

  final int? ruleId;

  bool get isEditing => ruleId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(botChatsProvider);
    final ruleAsync = ruleId == null
        ? const AsyncValue<DistributionRule?>.data(null)
        : ref.watch(distributionRuleDetailProvider(ruleId!));
    final targetsAsync = ruleId == null
        ? const AsyncValue<List<DistributionTarget>>.data([])
        : ref.watch(distributionTargetsProvider(ruleId!));

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑分发规则' : '创建分发规则'),
        leading: IconButton(
          tooltip: '返回分发',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/automation/distribution'),
        ),
      ),
      body: SafeArea(
        child: switch ((chatsAsync, ruleAsync, targetsAsync)) {
          (
            AsyncValue(hasValue: true, value: final chats?),
            AsyncValue(hasValue: true, value: final rule),
            AsyncValue(hasValue: true, value: final targets?),
          ) =>
            Center(
              child: DistributionRuleEditor(
                rule: rule,
                onManageTargets: () => context.push('/settings?tab=targets'),
                availableChats: chats,
                initialSelectedChatIds: targets
                    .map((target) => target.botChatId)
                    .toList(growable: false),
                onCancel: () => context.go('/automation/distribution'),
                onCreate: (data, chatIds, mode, recentDays) =>
                    _createRule(context, ref, data, chatIds, mode, recentDays),
                onUpdate: (id, data, chatIds, mode, recentDays) => _updateRule(
                  context,
                  ref,
                  id,
                  data,
                  targets,
                  chatIds,
                  mode,
                  recentDays,
                ),
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
      ),
    );
  }

  Future<void> _createRule(
    BuildContext context,
    WidgetRef ref,
    DistributionRuleCreate data,
    List<int> chatIds,
    String backfillMode,
    int? backfillRecentDays,
  ) async {
    try {
      final rule = await ref
          .read(distributionRulesProvider.notifier)
          .createRule(data);
      if (!context.mounted) return;
      final uniqueChatIds = chatIds.toSet();
      final confirmed = await _confirmBackfillIfNeeded(
        context,
        ref,
        ruleId: rule.id,
        chatIds: uniqueChatIds,
        backfillMode: backfillMode,
        backfillRecentDays: backfillRecentDays,
      );
      if (!confirmed) {
        if (context.mounted) {
          Toast.show(context, '规则已创建，目标回填已取消');
          context.go('/automation/distribution');
        }
        return;
      }

      var backfilledCount = 0;
      for (final chatId in uniqueChatIds) {
        final result = await ref
            .read(distributionTargetsProvider(rule.id).notifier)
            .createTargetWithResult(
              rule.id,
              DistributionTargetCreate(botChatId: chatId),
              backfillMode: backfillMode,
              backfillRecentDays: backfillRecentDays,
            );
        backfilledCount += result.backfilledCount;
      }
      ref.invalidate(botChatsProvider);
      ref.invalidate(contentQueueProvider);
      ref.invalidate(queueStatsProvider(null));
      if (context.mounted) {
        Toast.show(
          context,
          backfilledCount > 0 ? '规则创建成功，已补建 $backfilledCount 条队列' : '规则创建成功',
        );
        context.go('/automation/distribution');
      }
    } catch (error) {
      if (context.mounted) {
        Toast.show(context, '创建失败: $error', isError: true);
      }
    }
  }

  Future<void> _updateRule(
    BuildContext context,
    WidgetRef ref,
    int id,
    DistributionRuleUpdate data,
    List<DistributionTarget> existingTargets,
    List<int> chatIds,
    String backfillMode,
    int? backfillRecentDays,
  ) async {
    try {
      await ref.read(distributionRulesProvider.notifier).updateRule(id, data);
      if (!context.mounted) return;
      final existingByChatId = {
        for (final target in existingTargets) target.botChatId: target,
      };
      final selected = chatIds.toSet();
      final addedChatIds = selected
          .where((chatId) => !existingByChatId.containsKey(chatId))
          .toSet();
      final confirmed = await _confirmBackfillIfNeeded(
        context,
        ref,
        ruleId: id,
        chatIds: addedChatIds,
        backfillMode: backfillMode,
        backfillRecentDays: backfillRecentDays,
      );
      if (!confirmed) {
        if (context.mounted) {
          Toast.show(context, '规则已更新，目标回填已取消');
          context.go('/automation/distribution');
        }
        return;
      }

      var addedCount = 0;
      var removedCount = 0;
      var backfilledCount = 0;
      for (final target in existingTargets) {
        if (!selected.contains(target.botChatId)) {
          await ref
              .read(distributionTargetsProvider(id).notifier)
              .deleteTarget(id, target.id);
          removedCount++;
        }
      }
      for (final chatId in addedChatIds) {
        final result = await ref
            .read(distributionTargetsProvider(id).notifier)
            .createTargetWithResult(
              id,
              DistributionTargetCreate(botChatId: chatId),
              backfillMode: backfillMode,
              backfillRecentDays: backfillRecentDays,
            );
        addedCount++;
        backfilledCount += result.backfilledCount;
      }
      ref.invalidate(distributionTargetsProvider(id));
      ref.invalidate(contentQueueProvider);
      ref.invalidate(queueStatsProvider(null));
      if (context.mounted) {
        final parts = <String>['规则更新成功'];
        if (addedCount > 0) parts.add('新增 $addedCount 个目标');
        if (removedCount > 0) parts.add('移除 $removedCount 个目标');
        if (backfilledCount > 0) parts.add('补建 $backfilledCount 条队列');
        Toast.show(context, parts.join('，'));
        context.go('/automation/distribution');
      }
    } catch (error) {
      if (context.mounted) {
        Toast.show(context, '更新失败: $error', isError: true);
      }
    }
  }

  Future<bool> _confirmBackfillIfNeeded(
    BuildContext context,
    WidgetRef ref, {
    required int ruleId,
    required Set<int> chatIds,
    required String backfillMode,
    required int? backfillRecentDays,
  }) async {
    if (backfillMode == 'new_only' || chatIds.isEmpty) return true;

    var candidateCount = 0;
    for (final chatId in chatIds) {
      candidateCount += await ref
          .read(distributionTargetsProvider(ruleId).notifier)
          .previewBackfill(
            ruleId,
            chatId,
            backfillMode: backfillMode,
            backfillRecentDays: backfillRecentDays,
          );
    }
    if (candidateCount <= 0 || !context.mounted) return true;

    final modeLabel = backfillMode == 'recent_days'
        ? '最近 ${backfillRecentDays ?? 30} 天'
        : '全部历史';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认回填历史内容'),
        content: Text('将为 $modeLabel 中匹配规则的内容补建约 $candidateCount 条分发队列。'),
        shape: RoundedRectangleBorder(borderRadius: AppShape.sheetBorder),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认回填'),
          ),
        ],
      ),
    );
    return confirmed == true;
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
            Text('无法加载分发规则：$error', textAlign: TextAlign.center),
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
