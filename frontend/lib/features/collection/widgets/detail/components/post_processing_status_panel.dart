import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/utils/toast.dart';
import '../../../../../theme/design_tokens.dart';
import '../../../models/processing_status.dart';
import '../../../providers/collection_provider.dart';
import '../../../providers/content_actions_controller.dart';

/// 内容后处理状态面板。
///
/// 只消费 `/contents/{id}/processing-status` 的 typed contract：
/// 状态来自 [ProcessingStageState]，可执行动作来自 [ProcessingStageAction]。
/// 面板不推断动作、不解析状态字符串，写操作全部经由
/// [ContentActions] 控制层。
class PostProcessingStatusPanel extends ConsumerWidget {
  const PostProcessingStatusPanel({
    super.key,
    required this.contentId,
    this.initiallyExpanded = false,
  });

  final int contentId;

  /// 默认是否展开全部阶段。窄屏默认折叠，只显示需要关注的阶段。
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(contentProcessingStatusProvider(contentId));

    return statusAsync.when(
      data: (status) => _StatusPanelBody(
        status: status,
        initiallyExpanded: initiallyExpanded,
      ),
      loading: () => const _PanelShell(
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('处理状态加载中'),
          ],
        ),
      ),
      error: (_, _) => _PanelShell(
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(child: Text('处理状态加载失败')),
            TextButton(
              onPressed: () =>
                  ref.invalidate(contentProcessingStatusProvider(contentId)),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppShape.paneBorder,
      ),
      child: child,
    );
  }
}

class _StatusPanelBody extends StatefulWidget {
  const _StatusPanelBody({
    required this.status,
    required this.initiallyExpanded,
  });

  final ContentProcessingStatus status;
  final bool initiallyExpanded;

  @override
  State<_StatusPanelBody> createState() => _StatusPanelBodyState();
}

class _StatusPanelBodyState extends State<_StatusPanelBody> {
  late bool _showAll = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = widget.status;

    // 默认只显示与当前内容相关的阶段；不适用和已关闭的阶段折叠起来，
    // 避免"暂未匹配分发规则"这类信息与真实问题同权。
    final visible = _showAll ? status.stages : status.activeStages;
    final hiddenCount = status.stages.length - visible.length;

    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '处理状态',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StateChip(state: status.state),
            ],
          ),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '该内容没有进行中的后处理',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final stage in visible)
            _StageRow(contentId: status.contentId, stage: stage),
          if (hiddenCount > 0 || _showAll)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(_showAll ? '收起不适用阶段' : '显示其余 $hiddenCount 个阶段'),
              ),
            ),
        ],
      ),
    );
  }
}

/// 规范化状态的视觉表达。
///
/// 状态不只依赖颜色：每个状态同时有图标和文字标签。
class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final ProcessingStageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = stateColor(theme.colorScheme, state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(stateIcon(state), size: 16, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          stateLabel(state),
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 状态到颜色的映射。
///
/// 只使用 `ColorScheme` 角色：`error` 仅用于真实失败，`tertiary` 表达
/// "部分完成 / 被阻塞"，成功保持安静，不适用使用 outline。
Color stateColor(ColorScheme scheme, ProcessingStageState state) {
  return switch (state) {
    ProcessingStageState.failed => scheme.error,
    ProcessingStageState.partial ||
    ProcessingStageState.blocked => scheme.tertiary,
    ProcessingStageState.running ||
    ProcessingStageState.pending => scheme.primary,
    ProcessingStageState.success => scheme.onSurfaceVariant,
    ProcessingStageState.disabled ||
    ProcessingStageState.notApplicable => scheme.outline,
  };
}

IconData stateIcon(ProcessingStageState state) {
  return switch (state) {
    ProcessingStageState.failed => Icons.error_rounded,
    ProcessingStageState.partial => Icons.incomplete_circle_rounded,
    ProcessingStageState.blocked => Icons.lock_clock_rounded,
    ProcessingStageState.running => Icons.autorenew_rounded,
    ProcessingStageState.pending => Icons.schedule_rounded,
    ProcessingStageState.success => Icons.check_circle_rounded,
    ProcessingStageState.disabled => Icons.do_not_disturb_on_rounded,
    ProcessingStageState.notApplicable => Icons.remove_circle_outline_rounded,
  };
}

String stateLabel(ProcessingStageState state) {
  return switch (state) {
    ProcessingStageState.failed => '失败',
    ProcessingStageState.partial => '部分完成',
    ProcessingStageState.blocked => '受阻',
    ProcessingStageState.running => '进行中',
    ProcessingStageState.pending => '待处理',
    ProcessingStageState.success => '完成',
    ProcessingStageState.disabled => '已关闭',
    ProcessingStageState.notApplicable => '不适用',
  };
}

class _StageRow extends ConsumerWidget {
  const _StageRow({required this.contentId, required this.stage});

  final int contentId;
  final ProcessingStage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pending = ref.watch(contentActionsProvider);
    final progress = stage.progress;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                stateIcon(stage.state),
                size: 18,
                color: stateColor(theme.colorScheme, stage.state),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stage.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (stage.message.isNotEmpty)
                      Text(
                        stage.message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (progress != null && progress < 1)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                          ),
                        ),
                      ),
                    for (final issue in stage.issues)
                      _HintLine(
                        icon: Icons.report_problem_outlined,
                        text: issue,
                        color: theme.colorScheme.error,
                      ),
                    for (final hint in stage.hints)
                      _HintLine(
                        icon: Icons.lightbulb_outline_rounded,
                        text: hint,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                stateLabel(stage.state),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: stateColor(theme.colorScheme, stage.state),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (stage.actions.isNotEmpty || stage.failures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xl + AppSpacing.xxs,
                top: AppSpacing.xs,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final action in stage.actions)
                    _ActionButton(
                      contentId: contentId,
                      action: action,
                      busy: pending.contains('$contentId:${action.kind.name}'),
                    ),
                  if (stage.failures.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _showFailures(context, stage),
                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                      label: Text('失败详情 (${stage.failuresTotal})'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showFailures(BuildContext context, ProcessingStage stage) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${stage.label} · 失败详情'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.sheet),
        ),
        content: SizedBox(
          width: AppPane.formMaxWidth,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (stage.failuresTruncated)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      '共 ${stage.failuresTotal} 项失败，这里显示最近 ${stage.failures.length} 项。',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                for (final failure in stage.failures)
                  _FailureTile(failure: failure),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _FailureTile extends StatelessWidget {
  const _FailureTile({required this.failure});

  final ProcessingStageFailure failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attempts = failure.maxRetries == null
        ? '已重试 ${failure.retryCount} 次'
        : '已重试 ${failure.retryCount}/${failure.maxRetries} 次';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failure.reference ?? '未命名对象',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SelectableText(
            failure.reason ?? '未提供失败原因',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          Text(
            [
              if (failure.errorType != null) failure.errorType!,
              attempts,
              failure.retryable ? '可重试' : '不可直接重试',
              if (failure.occurredAt != null)
                failure.occurredAt!.toLocal().toString(),
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends ConsumerWidget {
  const _ActionButton({
    required this.contentId,
    required this.action,
    required this.busy,
  });

  final int contentId;
  final ProcessingStageAction action;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.tonalIcon(
      onPressed: busy ? null : () => _run(context, ref),
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_iconFor(action.kind), size: 16),
      label: Text(action.label),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    // 有外部副作用的动作（调用付费模型、向外部平台发送）必须显式确认。
    if (action.externalEffect) {
      final confirmed = await _confirm(context);
      if (confirmed != true) return;
    }
    if (!context.mounted) return;

    final result = await ref
        .read(contentActionsProvider.notifier)
        .runStageAction(contentId, action);

    if (!context.mounted) return;
    Toast.show(
      context,
      result.message,
      isError: !result.ok,
      action: result.runId == null
          ? null
          : SnackBarAction(
              label: '查看日志',
              onPressed: () =>
                  context.push('/tasks/${Uri.encodeComponent(result.runId!)}'),
            ),
    );
  }

  Future<bool?> _confirm(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.sheet),
        ),
        title: Text(action.label),
        content: Text(_confirmMessageFor(action)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }
}

String _confirmMessageFor(ProcessingStageAction action) {
  final count = action.targetIds.length;
  return switch (action.kind) {
    ProcessingActionKind.generateSummary => '将调用摘要模型重新生成摘要、标签和语义分块，会产生模型调用成本。',
    ProcessingActionKind.rebuildSemanticIndex =>
      '将重新计算该内容的全部语义分块向量，会产生 Embedding 调用成本。',
    ProcessingActionKind.retrySemanticChunk =>
      '将重试 $count 个失败分块，会产生 Embedding 调用成本。',
    ProcessingActionKind.retryDistributionItem =>
      '将重新向外部平台发送 $count 条分发项。这是对外发送操作。',
    ProcessingActionKind.rematchDistribution =>
      '将按当前分发规则重新入队。匹配成功后内容会被发送到外部平台。',
    ProcessingActionKind.patrolScore => '将调用模型对该内容重新评分，会产生模型调用成本。',
  };
}

IconData _iconFor(ProcessingActionKind kind) {
  return switch (kind) {
    ProcessingActionKind.generateSummary => Icons.auto_awesome_rounded,
    ProcessingActionKind.rebuildSemanticIndex => Icons.hub_rounded,
    ProcessingActionKind.retrySemanticChunk => Icons.replay_rounded,
    ProcessingActionKind.retryDistributionItem => Icons.outbox_rounded,
    ProcessingActionKind.rematchDistribution => Icons.rule_rounded,
    ProcessingActionKind.patrolScore => Icons.rate_review_rounded,
  };
}

class _HintLine extends StatelessWidget {
  const _HintLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
