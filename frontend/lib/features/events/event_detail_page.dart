import '../../routing/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/discard_changes_dialog.dart';

import '../../core/widgets/adaptive_form_dialog.dart';
import '../../core/widgets/browser_leave_guard.dart';
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
        leading: const AppBackButton(fallback: '/collection'),
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
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppPane.readableMaxWidth + AppSpacing.xl * 2,
      ),
      child: ListView(
        key: PageStorageKey('knowledge-event-${event.id}'),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _EventHeader(event: event),
          const SizedBox(height: AppSpacing.xxl),
          Text('事件时间线', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          for (var index = 0; index < event.members.length; index++)
            _TimelineEntry(
              event: event,
              member: event.members[index],
              isLast: index == event.members.length - 1,
            ),
        ],
      ),
    ),
  );
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
    final saved = await showDialog<bool>(
      context: context,
      animationStyle: _editAnimation(context),
      builder: (_) => _EventEditDialog(event: event, member: member),
    );
    if (saved == true && context.mounted) Toast.show(context, '事件关系已更新');
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title == null || title.isEmpty
                                    ? '无标题内容'
                                    : title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            const Icon(Icons.chevron_right_rounded, size: 20),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                _roleLabel(member.role),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            _EvidenceTag(state: member.evidenceState),
                            if ([
                              'http',
                              'https',
                            ].contains(Uri.tryParse(member.url)?.scheme))
                              PlatformBadge(platform: member.platform),
                          ],
                        ),
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

class _EvidenceTag extends StatelessWidget {
  const _EvidenceTag({required this.state, this.count});
  final String state;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppShape.cardMediaBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _evidenceIcon(state),
              size: 16,
              color: _evidenceColor(theme.colorScheme, state),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${_evidenceLabel(state)}${count == null ? '' : ' $count'}',
                style: theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        Semantics(
          container: true,
          header: true,
          child: Text(
            event.title,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
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
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final state in _evidenceLabels.keys)
              if (event.members
                      .where((member) => member.evidenceState == state)
                      .length
                  case final count when count > 0)
                _EvidenceTag(state: state, count: count),
          ],
        ),
      ],
    );
  }
}

class _EventMenu extends ConsumerWidget {
  const _EventMenu({required this.event});

  final KnowledgeEventDetail event;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      animationStyle: _editAnimation(context),
      builder: (_) => _EventEditDialog(event: event),
    );
    if (saved == true && context.mounted) Toast.show(context, '事件信息已更新');
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

AnimationStyle _editAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: AppMotion.surfaceEnter,
        reverseDuration: AppMotion.surfaceExit,
        curve: AppMotion.standardCurve,
      );

class _EventEditDialog extends ConsumerStatefulWidget {
  const _EventEditDialog({required this.event, this.member});
  final KnowledgeEventDetail event;
  final KnowledgeEventMember? member;

  @override
  ConsumerState<_EventEditDialog> createState() => _EventEditDialogState();
}

class _EventEditDialogState extends ConsumerState<_EventEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _role;
  late String _evidenceState;
  bool _saving = false;
  bool _confirmingExit = false;
  String? _error;
  bool get _editingMember => widget.member != null;
  String get _initialDescription =>
      (_editingMember ? widget.member!.note : widget.event.description) ?? '';

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.event.title)
      ..addListener(_changed);
    _description = TextEditingController(text: _initialDescription)
      ..addListener(_changed);
    _role = widget.member?.role ?? '';
    _evidenceState = widget.member?.evidenceState ?? '';
  }

  void _changed() => setState(() {});

  Map<String, dynamic> get _changes {
    final description = _description.text.trim();
    return {
      if (!_editingMember && _title.text.trim() != widget.event.title)
        'title': _title.text.trim(),
      if (description != _initialDescription)
        (_editingMember ? 'note' : 'description'): description.isEmpty
            ? null
            : description,
      if (_editingMember && _role != widget.member!.role) 'role': _role,
      if (_editingMember && _evidenceState != widget.member!.evidenceState)
        'evidence_state': _evidenceState,
    };
  }

  bool get _dirty =>
      (!_editingMember && _title.text != widget.event.title) ||
      _description.text != _initialDescription ||
      (_editingMember &&
          (_role != widget.member!.role ||
              _evidenceState != widget.member!.evidenceState));

  Future<void> _close() async {
    if (_saving || _confirmingExit) return;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    _confirmingExit = true;
    final editingFocus = FocusManager.instance.primaryFocus;
    editingFocus?.unfocus();
    final discard = await showDiscardChangesDialog(
      context,
      title: '放弃未保存的修改？',
      message: '退出后，本次编辑不会保存。',
      animationStyle: _editAnimation(context),
    );
    _confirmingExit = false;
    if (!mounted) return;
    if (discard == true) {
      Navigator.pop(context);
    } else if (editingFocus?.context != null) {
      editingFocus!.requestFocus();
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _changes.isEmpty ||
        (!_editingMember && _title.text.trim().isEmpty)) {
      return;
    }
    final changes = _changes;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final actions = ref.read(knowledgeEventActionsProvider);
      if (_editingMember) {
        await actions.updateMember(
          eventId: widget.event.id,
          contentId: widget.member!.contentId,
          changes: changes,
        );
      } else {
        await actions.updateEvent(widget.event.id, changes);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = formatApiErrorMessage(error, fallbackMessage: '保存失败，请重试');
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Widget _selector(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    itemHeight: null,
    menuMaxHeight: 400,
    borderRadius: AppShape.cardBorder,
    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final item in options.entries)
        DropdownMenuItem(value: item.key, child: Text(item.value)),
    ],
    onChanged: _saving
        ? null
        : (value) {
            if (value != null) onChanged(value);
          },
  );

  @override
  Widget build(BuildContext context) => BrowserLeaveGuard(
    enabled: _saving || _dirty,
    child: PopScope<bool>(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AdaptiveFormDialog(
        title: _editingMember ? '编辑事件关系' : '编辑事件',
        contentBuilder: (context, width, short) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_editingMember) ...[
              _selector(
                '内容角色',
                _role,
                _roleLabels,
                (value) => setState(() => _role = value),
              ),
              const SizedBox(height: AppSpacing.md),
              _selector(
                '证据状态',
                _evidenceState,
                _evidenceLabels,
                (value) => setState(() => _evidenceState = value),
              ),
            ] else
              TextField(
                controller: _title,
                enabled: !_saving,
                minLines: 1,
                maxLines: short ? 1 : 3,
                maxLength: 240,
                decoration: InputDecoration(
                  labelText: '标题',
                  errorText: _title.text.trim().isEmpty ? '请输入事件标题' : null,
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _description,
              enabled: !_saving,
              maxLength: _editingMember ? 2000 : 4000,
              minLines: short ? 1 : 3,
              maxLines: short ? 2 : 6,
              decoration: InputDecoration(
                labelText: _editingMember ? '关系说明' : '事件说明',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: _saving ? null : _close,
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed:
                  _saving ||
                      _changes.isEmpty ||
                      (!_editingMember && _title.text.trim().isEmpty)
                  ? null
                  : _save,
              child: Text(_saving ? '正在保存' : '保存'),
            ),
          ],
        ),
      ),
    ),
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
