import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../models/agent_result.dart';

class AgentConfirmationPanel extends StatelessWidget {
  const AgentConfirmationPanel({
    super.key,
    required this.confirmation,
    required this.onDecide,
    required this.pending,
  });

  final AgentConfirmation confirmation;
  final Future<void> Function(AgentConfirmation confirmation, bool approved)
  onDecide;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onTertiaryContainer;
    final detailStyle = theme.textTheme.bodySmall?.copyWith(color: foreground);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: AppShape.paneBorder,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 20,
                    color: foreground,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '需要确认',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                confirmation.summary,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
              const SizedBox(height: AppSpacing.xs),
              ExpansionTile(
                title: const Text('操作参数'),
                textColor: foreground,
                collapsedTextColor: foreground,
                iconColor: foreground,
                collapsedIconColor: foreground,
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
                expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
                    ? AnimationStyle.noAnimation
                    : const AnimationStyle(
                        duration: AppMotion.stateChange,
                        curve: AppMotion.standardCurve,
                      ),
                children: [
                  SelectableText(confirmation.toolName, style: detailStyle),
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(
                    prettyJson(confirmation.args),
                    style: detailStyle,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  FilledButton.icon(
                    onPressed: pending
                        ? null
                        : () => onDecide(confirmation, true),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(pending ? '处理中' : '确认'),
                  ),
                  OutlinedButton.icon(
                    onPressed: pending
                        ? null
                        : () => onDecide(confirmation, false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('拒绝'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
