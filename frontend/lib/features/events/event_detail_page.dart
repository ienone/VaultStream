import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/toast.dart';
import '../../core/widgets/platform_badge.dart';
import '../../theme/design_tokens.dart';
import 'models/knowledge_event.dart';
import 'providers/knowledge_event_provider.dart';

class EventDetailPage extends ConsumerWidget {
  const EventDetailPage({super.key, required this.eventId});

  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(knowledgeEventDetailProvider(eventId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('事件详情'),
        actions: [
          event.maybeWhen(
            data: (value) => _EventMenu(event: value),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: event.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _EventError(eventId: eventId, error: error),
        data: (value) => _EventBody(event: value),
      ),
    );
  }
}

class _EventBody extends StatelessWidget {
  const _EventBody({required this.event});

  final KnowledgeEventDetail event;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final metrics = WindowMetrics.fromSize(
        Size(constraints.maxWidth, constraints.maxHeight),
      );
      if (metrics.supportsSupportingPane) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _EventTimeline(event: event, expanded: true)),
            const VerticalDivider(width: 1),
            SizedBox(
              width: AppPane.supportingWidth,
              child: _EventOverview(event: event),
            ),
          ],
        );
      }
      return _EventTimeline(event: event, expanded: false);
    },
  );
}

class _EventTimeline extends StatelessWidget {
  const _EventTimeline({required this.event, required this.expanded});

  final KnowledgeEventDetail event;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final padding = expanded ? AppSpacing.xl : AppSpacing.md;
    return ListView(
      key: const ValueKey('knowledge-event-timeline'),
      padding: EdgeInsets.all(padding),
      children: [
        if (!expanded) ...[
          _EventHeader(event: event),
          const SizedBox(height: AppSpacing.xl),
        ],
        Text('事件时间线', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        for (var index = 0; index < event.members.length; index++)
          _TimelineEntry(
            event: event,
            member: event.members[index],
            isLast: index == event.members.length - 1,
          ),
      ],
    );
  }
}

class _TimelineEntry extends ConsumerWidget {
  const _TimelineEntry({
    required this.event,
    required this.member,
    required this.isLast,
  });

  final KnowledgeEventDetail event;
  final KnowledgeEventMember member;
  final bool isLast;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_MemberEditResult>(
      context: context,
      builder: (_) => _MemberEditDialog(member: member),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(knowledgeEventActionsProvider)
          .updateMember(
            eventId: event.id,
            contentId: member.contentId,
            changes: {
              'role': result.role,
              'evidence_state': result.evidenceState,
              'note': result.note,
            },
          );
      if (context.mounted) Toast.show(context, '事件关系已更新');
    } catch (error) {
      if (context.mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(error, fallbackMessage: '更新事件关系失败'),
          isError: true,
        );
      }
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(knowledgeEventActionsProvider)
          .removeMember(eventId: event.id, contentId: member.contentId);
      if (!context.mounted) return;
      Toast.show(
        context,
        '已从事件移除',
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            try {
              await ref
                  .read(knowledgeEventActionsProvider)
                  .addContent(
                    eventId: event.id,
                    contentId: member.contentId,
                    role: member.role,
                    evidenceState: member.evidenceState,
                    note: member.note,
                  );
            } catch (error) {
              if (context.mounted) {
                Toast.show(
                  context,
                  formatApiErrorMessage(error, fallbackMessage: '撤销失败'),
                  isError: true,
                );
              }
            }
          },
        ),
      );
    } catch (error) {
      if (context.mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(error, fallbackMessage: '移除事件关系失败'),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final title = member.title?.trim();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _evidenceColor(scheme, member.evidenceState),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: scheme.outlineVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/collection/${member.contentId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatDate(member.occurredAt),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: '事件关系操作',
                              onSelected: (value) {
                                if (value == 'edit') _edit(context, ref);
                                if (value == 'remove') _remove(context, ref);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('编辑分类'),
                                ),
                                if (event.members.length > 1)
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Text('从事件移除'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        Text(
                          title == null || title.isEmpty ? '无标题内容' : title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            Chip(label: Text(_roleLabel(member.role))),
                            Chip(
                              avatar: Icon(
                                _evidenceIcon(member.evidenceState),
                                size: 17,
                              ),
                              label: Text(_evidenceLabel(member.evidenceState)),
                            ),
                            if ([
                              'http',
                              'https',
                            ].contains(Uri.tryParse(member.url)?.scheme))
                              PlatformBadge(platform: member.platform),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (member.summary?.trim() case final summary?
                            when summary.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (member.note?.trim() case final note?
                            when note.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: AppShape.cardMediaBorder,
                            ),
                            child: Text('关系说明：$note'),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            const Icon(Icons.article_outlined, size: 18),
                            const SizedBox(width: AppSpacing.xs),
                            const Text('查看原内容'),
                            const Spacer(),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventOverview extends StatelessWidget {
  const _EventOverview({required this.event});

  final KnowledgeEventDetail event;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      _EventHeader(event: event),
      const SizedBox(height: AppSpacing.lg),
      Text('证据概览', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      for (final state in const [
        'confirmed',
        'unverified',
        'disputed',
        'viewpoint',
      ])
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(_evidenceIcon(state)),
          title: Text(_evidenceLabel(state)),
          trailing: Text(
            '${event.members.where((member) => member.evidenceState == state).length}',
          ),
        ),
    ],
  );
}

class _EventHeader extends StatelessWidget {
  const _EventHeader({required this.event});

  final KnowledgeEventDetail event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(event.title, style: Theme.of(context).textTheme.headlineSmall),
        if (event.description?.trim() case final description?
            when description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(description),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${_statusLabel(event.status)} · ${event.memberCount} 条关联内容',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _EventMenu extends ConsumerWidget {
  const _EventMenu({required this.event});

  final KnowledgeEventDetail event;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _EventEditDialog(event: event),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(knowledgeEventActionsProvider).updateEvent(event.id, {
        'title': result.$1,
        'description': result.$2,
      });
      if (context.mounted) Toast.show(context, '事件信息已更新');
    } catch (error) {
      if (context.mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(error, fallbackMessage: '更新事件失败'),
          isError: true,
        );
      }
    }
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    String status,
  ) async {
    try {
      await ref.read(knowledgeEventActionsProvider).updateEvent(event.id, {
        'status': status,
      });
      if (context.mounted) Toast.show(context, '事件状态已更新');
    } catch (error) {
      if (context.mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(error, fallbackMessage: '更新事件状态失败'),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: '事件操作',
    onSelected: (value) {
      if (value == 'edit') _edit(context, ref);
      if (value.startsWith('status:')) {
        _setStatus(context, ref, value.substring('status:'.length));
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'edit', child: Text('编辑标题与说明')),
      if (event.status != 'resolved')
        const PopupMenuItem(value: 'status:resolved', child: Text('标记为已解决')),
      if (event.status != 'archived')
        const PopupMenuItem(value: 'status:archived', child: Text('归档事件')),
      if (event.status != 'active')
        const PopupMenuItem(value: 'status:active', child: Text('恢复为进行中')),
    ],
  );
}

class _EventEditDialog extends StatefulWidget {
  const _EventEditDialog({required this.event});

  final KnowledgeEventDetail event;

  @override
  State<_EventEditDialog> createState() => _EventEditDialogState();
}

class _EventEditDialogState extends State<_EventEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.event.title);
    _description = TextEditingController(text: widget.event.description);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑事件'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppPane.formMaxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            maxLength: 240,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _description,
            maxLength: 4000,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '事件说明',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final title = _title.text.trim();
          if (title.isEmpty) return;
          final description = _description.text.trim();
          Navigator.pop(context, (
            title,
            description.isEmpty ? null : description,
          ));
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _MemberEditResult {
  const _MemberEditResult(this.role, this.evidenceState, this.note);

  final String role;
  final String evidenceState;
  final String? note;
}

class _MemberEditDialog extends StatefulWidget {
  const _MemberEditDialog({required this.member});

  final KnowledgeEventMember member;

  @override
  State<_MemberEditDialog> createState() => _MemberEditDialogState();
}

class _MemberEditDialogState extends State<_MemberEditDialog> {
  late String _role;
  late String _evidenceState;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _role = widget.member.role;
    _evidenceState = widget.member.evidenceState;
    _note = TextEditingController(text: widget.member.note);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑事件关系'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppPane.formMaxWidth),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: '内容角色',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final value in _roleLabels.keys)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_roleLabel(value)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _role = value);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _evidenceState,
              decoration: const InputDecoration(
                labelText: '证据状态',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final value in _evidenceLabels.keys)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_evidenceLabel(value)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _evidenceState = value);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _note,
              maxLength: 2000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '关系说明',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final note = _note.text.trim();
          Navigator.pop(
            context,
            _MemberEditResult(
              _role,
              _evidenceState,
              note.isEmpty ? null : note,
            ),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _EventError extends ConsumerWidget {
  const _EventError({required this.eventId, required this.error});

  final int eventId;
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48),
          const SizedBox(height: AppSpacing.md),
          Text(
            formatApiErrorMessage(error, fallbackMessage: '无法加载事件'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonal(
            onPressed: () =>
                ref.invalidate(knowledgeEventDetailProvider(eventId)),
            child: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}

const _roleLabels = <String, String>{
  'source': '原始来源',
  'report': '独立报道',
  'commentary': '评论观点',
  'background': '背景资料',
  'correction': '更正信息',
  'evidence': '现场证据',
};

const _evidenceLabels = <String, String>{
  'unverified': '尚未确认',
  'confirmed': '已确认',
  'disputed': '存在争议',
  'viewpoint': '观点',
};

String _roleLabel(String value) => _roleLabels[value] ?? value;

String _evidenceLabel(String value) => _evidenceLabels[value] ?? value;

String _statusLabel(String value) => switch (value) {
  'active' => '进行中',
  'resolved' => '已解决',
  'archived' => '已归档',
  _ => value,
};

IconData _evidenceIcon(String value) => switch (value) {
  'confirmed' => Icons.verified_outlined,
  'disputed' => Icons.gpp_maybe_outlined,
  'viewpoint' => Icons.record_voice_over_outlined,
  _ => Icons.help_outline_rounded,
};

Color _evidenceColor(ColorScheme scheme, String value) => switch (value) {
  'confirmed' => scheme.primary,
  'disputed' => scheme.error,
  'viewpoint' => scheme.tertiary,
  _ => scheme.outline,
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
