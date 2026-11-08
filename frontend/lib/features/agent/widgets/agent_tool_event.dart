import 'package:material_ui/material_ui.dart';

import '../../../theme/design_tokens.dart';
import '../../../core/widgets/animated_expansion.dart';
import '../models/agent_result.dart';
import 'agent_citation_tile.dart';

class AgentToolEvent extends StatefulWidget {
  const AgentToolEvent({
    super.key,
    required this.event,
    required this.running,
    required this.showCitations,
  });

  final Map<String, dynamic> event;
  final bool running;
  final bool showCitations;

  @override
  State<AgentToolEvent> createState() => _AgentToolEventState();
}

class _AgentToolEventState extends State<AgentToolEvent> {
  bool _expanded = false;

  bool get _failed =>
      !widget.running &&
      (widget.event['ok'] == false || widget.event['error'] != null);

  Object? get _details {
    return {
      'tool': widget.event['tool'],
      if (widget.event['args'] != null) 'args': widget.event['args'],
      if (widget.event['error'] != null) 'error': widget.event['error'],
      if (widget.event['result'] != null) 'result': widget.event['result'],
    };
  }

  bool get _hasDetails {
    final details = _details;
    if (details == null) return false;
    if (details is String) return details.isNotEmpty;
    if (details is Iterable) return details.isNotEmpty;
    if (details is Map) return details.isNotEmpty;
    return true;
  }

  void _setExpanded(bool expanded) => setState(() => _expanded = expanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final citations = citationsFromToolResult(widget.event);
    final actionSummary = actionSummaryFromToolResult(widget.event);
    final statusLabel = widget.running
        ? '进行中'
        : _failed
        ? '失败'
        : '已完成';
    final showEvidence =
        actionSummary != null || (widget.showCitations && citations.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppShape.cardBorder,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: _hasDetails,
              expanded: _hasDetails ? _expanded : null,
              child: InkWell(
                borderRadius: AppShape.cardBorder,
                onTap: _hasDetails ? () => _setExpanded(!_expanded) : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                          widget.running
                              ? Icons.build_circle_outlined
                              : _failed
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          color: _failed ? theme.colorScheme.error : null,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.xxs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _toolLabel(widget.event['tool']),
                                style: theme.textTheme.labelLarge,
                              ),
                              Text(
                                statusLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: _failed
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_hasDetails)
                          AnimatedRotation(
                            turns: _expanded ? .5 : 0,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : AppMotion.stateChange,
                            child: const Icon(Icons.expand_more_rounded),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (showEvidence)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (actionSummary != null)
                      Text(actionSummary, style: theme.textTheme.bodyMedium),
                    if (widget.showCitations && citations.isNotEmpty) ...[
                      if (actionSummary != null) const SizedBox(height: 10),
                      for (final citation in citations.take(5))
                        AgentCitationTile(citation: citation),
                    ],
                  ],
                ),
              ),
            if (_hasDetails)
              AnimatedExpansion(
                expanded: _expanded,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    showEvidence ? 4 : 0,
                    12,
                    12,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      prettyJson(_details),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _toolLabel(Object? tool) => switch (tool) {
  'search_content' => '搜索内容',
  'read_content' => '阅读内容',
  'read_image' => '识别图片',
  'capture_content' => '保存内容',
  'get_stats' => '查看统计',
  'list_groups' => '查询推送目标',
  'push_batch' => '加入推送队列',
  'organize_knowledge_event' => '整理事件',
  'api_catalog' => '查看可用操作',
  'api_get' => '查询数据',
  'api_mutation' => '更新数据',
  _ => '工具操作',
};
