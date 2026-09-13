import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
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

class _AgentToolEventState extends State<AgentToolEvent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final Animation<double> _height;
  late bool _expanded;

  bool get _failed =>
      !widget.running &&
      (widget.event['ok'] == false || widget.event['error'] != null);

  Object? get _details {
    if (widget.running) return widget.event['args'];
    return {
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

  @override
  void initState() {
    super.initState();
    _expanded = _failed;
    _animation =
        AnimationController(
          vsync: this,
          duration: AppMotion.stateChange,
          value: _expanded ? 1 : 0,
        )..addStatusListener((status) {
          if (status == AnimationStatus.dismissed && mounted) setState(() {});
        });
    _height = _animation.drive(CurveTween(curve: AppMotion.standardCurve));
  }

  @override
  void didUpdateWidget(covariant AgentToolEvent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasFailed =
        !oldWidget.running &&
        (oldWidget.event['ok'] == false || oldWidget.event['error'] != null);
    if (_failed && !wasFailed) _setExpanded(true);
  }

  void _setExpanded(bool expanded) {
    setState(() => _expanded = expanded);
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = expanded ? 1 : 0;
    } else if (expanded) {
      _animation.forward();
    } else {
      _animation.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = _expanded ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final citations = citationsFromToolResult(widget.event);
    final actionSummary = actionSummaryFromToolResult(widget.event);
    final statusLabel = widget.running
        ? '调用中'
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
                          child: Text(
                            '${widget.event['tool'] ?? 'tool'} $statusLabel',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (_hasDetails)
                          RotationTransition(
                            turns: _height.drive(Tween(begin: 0.0, end: 0.5)),
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
            if (_hasDetails && (_expanded || !_animation.isDismissed))
              SizeTransition(
                sizeFactor: _height,
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
